# Event Semantics

This document specifies how the core turns observations into events, how duplicates are suppressed, how paired events form incidents, and how StatusItems are created, updated, and resolved. It closes the gaps named in WP-0.4 of `docs/13-implementation-plan.md`.

The rule this document exists to enforce: polling every 15 minutes must not re-emit `app.review.rejected` every 15 minutes. One thing happened; one event exists; one status item exists; at most one notification decision is made.

Storage for the objects described here (resource state snapshots, events, incidents, status items) is defined in `docs/15-data-model.md`. The mapping syntax plugins use to declare transition conditions (`changed`, `changed_to`, `changed_from`) is defined in `docs/16-mapping-language.md`. This document defines semantics, not tables or syntax.

## Implementation status

The current `StatusCore` implementation contains the first ingestion slice:

- `EventIngestor` accepts normalized events after mapping and before rules.
- Existing fingerprints are suppressed as duplicates, increment `dedup_count`, update `last_seen_at`, and write an audit entry.
- New warning and critical events create event-backed `StatusItem` rows.
- New notice events are stored and audited, but do not create inbox items by default.
- `StateChangeDetector` records resource state snapshots and classifies observations as first sighting, unchanged, or changed.
- `MappingConditionEvaluator` evaluates `changed`, `changed_to`, and `changed_from` against current and previous resource state.

The remaining semantics in this document are still planned work: full mapping-engine integration, first-observation event policy, date-bucketed fingerprints, incident open/close handling, status item attachment/update, auto-resolution, notification decisions, and rule evaluation integration.

## Three emission models

Every event enters the pipeline through exactly one of three emission models. A plugin declares the model per event type; the core enforces the behavior.

```txt
state-transition
→ resource state moved from A to B; emitted by comparing against the stored snapshot

condition / metric-threshold
→ a condition holds over current data (no meaningful prior state per se);
  emitted whenever the condition is true, deduplicated by fingerprint and date bucket

pass-through
→ an external system already decided something happened (webhook, push, RSS item);
  emitted as received, deduplicated by delivery identity
```

State-transition is the default and the preferred model. Condition-based emission applies only when there is no prior state to compare against, or when the interesting fact is "this is still true" rather than "this changed" — for example `youtube.channel.views_dropped` (a computed comparison against a baseline) or `jira.issue.overdue`.

## 1. State-change detection

### Resource state snapshots

After every successful poll, the mapping engine writes a state snapshot per resource: the small set of fields the plugin declares as state-relevant (for an App Store app: review state, latest version state, latest build state). Snapshots are stored per resource as defined in `docs/15-data-model.md`; the previous snapshot is what the next poll compares against.

### Transition = event

On each poll the mapping engine compares the newly mapped state against the stored snapshot.

```txt
previous snapshot state == new state
→ no event, snapshot timestamp updated

previous snapshot state != new state
→ one event emitted for the transition, snapshot replaced
```

The event describes the transition into the target state. `app.review.rejected` means "review state became REJECTED", not "review state is REJECTED". A poll that observes REJECTED when the snapshot already says REJECTED emits nothing.

If a resource skips through states between polls (submitted and rejected within one 15-minute window), the engine only sees the endpoints. Emit one event for the observed transition into the final state. Do not synthesize intermediate events.

### First observation

When a resource is seen for the first time — new account connected, new app appears, plugin freshly installed — there is no prior snapshot.

Decision: **a first observation emits the event for the current state, once, marked as an initial observation.**

```json
{
  "type": "app.review.rejected",
  "resourceId": "app_tiko_yes_no",
  "initialObservation": true,
  "severity": "critical"
}
```

Rationale: the alternative (stay silent until the next transition) means a user who connects an account with an already-rejected app sees nothing until Apple changes the state — which is exactly the situation Status exists to surface. The `initialObservation` flag lets rules and notification preferences treat setup noise differently (a reasonable default rule: initial observations create status items but do not send immediate notifications for anything below `critical`).

First observations of unremarkable states (`ok`-severity, for example an app that is READY_FOR_SALE) write the snapshot and emit nothing. Only attention-relevant states (severity `notice` or above) emit an initial-observation event.

### When condition-based emission applies

Use condition-based emission (no snapshot comparison) only when:

- the event is a computed comparison against a baseline or threshold (`views_dropped`, `worker.error_rate_high`);
- the event is inherently recurring and time-scoped (`no_upload_recently`, `issue.overdue`);
- the source is pass-through (webhook, feed item).

Condition-based events rely entirely on the fingerprint (section 2) to avoid re-emitting every poll. State-transition events use the fingerprint only as a safety net (restarts, replayed jobs, overlapping manual refreshes).

## 2. Fingerprint specification

Every event carries a fingerprint, computed by the core before the event enters the bus:

```txt
fingerprint = hash(provider + ":" + event_type + ":" + resource_id + ":" + relevant_state [ + ":" + date_bucket ])
```

### relevant_state per event category

```txt
state-transition events
→ relevant_state = the target state (e.g. "REJECTED")
→ no date bucket

metric-threshold / condition events
→ relevant_state = the threshold identity:
  metric_id + operator + threshold value + comparison window
  (e.g. "views_28d:lt:baseline_0.8:28d")
→ date bucket applies

incident-paired recurring events (website.down, website.recovered)
→ relevant_state = the incident id (see section 3)
→ no date bucket while the incident is open

pass-through events
→ relevant_state = provider delivery id if the provider supplies one
  (GitHub delivery GUID, Stripe event id, RSS item GUID);
  otherwise a hash of the normalized payload
→ date bucket applies only in the payload-hash fallback
```

### Date buckets

A date bucket makes a condition-based event re-emittable after enough time has passed, without re-emitting every poll.

```txt
bucket sizes: 15m | 1h | 1d | 7d
default for metric-threshold events: 1d
default for payload-hash pass-through fallback: 15m
```

Buckets are calendar-aligned in the user's local time zone (a `1d` bucket is the local calendar date). Plugins may declare a bucket per event type from the allowed sizes; the core rejects anything else.

Buckets never apply to state-transition events. A transition is a point fact; if the state genuinely flaps A → B → A → B, those are four real events, and the snapshot comparison already guarantees one event per real transition. Bucketing transitions would silently swallow real changes.

### Collision behavior

When a new candidate event's fingerprint matches an existing event within the dedup window (the date bucket for bucketed events; the lifetime of the open incident for incident events; a fixed 24 hours for un-bucketed transition events, as a replay guard):

```txt
- the candidate is suppressed: it is not stored as a new event,
  does not enter rule evaluation, and cannot notify;
- the original event's dedup_count is incremented;
- the original event's last_seen_at is updated;
- the suppression is visible in the audit trail of the job that produced it.
```

A suppressed duplicate is bookkeeping, not an event. Nothing downstream of the event bus ever sees it.

## 3. Incident semantics

Some event types come in open/close pairs. The canonical pair is `website.down` / `website.recovered`. Plugins declare pairs explicitly:

```json
{
  "type": "website.down",
  "opensIncident": "downtime",
  "closedBy": "website.recovered"
}
```

Behavior:

```txt
opening event (website.down)
→ if no open incident of this kind exists for the resource:
    emit the event, create an incident (open), link the event to it
→ if an open incident exists:
    suppress (fingerprint uses the incident id), increment the incident's
    observation count, update its last_observed_at — no new event

closing event (website.recovered)
→ if an open incident exists:
    emit the event once, close the incident, record duration
→ if no open incident exists:
    emit nothing (a recovery without a known outage is not news);
    write the snapshot so future downs are detected
```

An incident records: id, resource_id, kind, opening event id, closing event id, opened_at, closed_at, observation count. Incident storage is defined in `docs/15-data-model.md`.

This pattern generalizes to any paired events: `cloudflare.zone.ssl_issue` / resolution, `app.build.processing_failed` / next successful build, integration-error / reconnect. If a plugin declares an open/close pair, the core applies exactly the semantics above; plugins do not implement their own incident logic.

While an incident is open, the "still down" fact lives on the incident and its StatusItem (section 4), not in new events.

## 4. StatusItem lifecycle

A StatusItem is the user-facing unit of attention. Events are history; StatusItems are the present. Events are immutable and accumulate; StatusItems are mutable and resolve.

### Fields

```txt
id
resource_id
kind                 event | current-state
source_event_ids     events that created or updated this item
incident_id          optional, when backed by an incident
severity
title
summary
action_url
state                open | snoozed | resolved | dismissed
created_at
updated_at
resolved_at
snooze_until
dismissed_reason     optional free text ("not relevant", "handled in Jira")
stuck                derived flag, see staleness
```

### Derivation rules

```txt
event-derived items (kind = event)
- an event with severity warning or critical creates a StatusItem,
  unless an open item already exists for the same (resource_id, event_type) —
  then the event attaches to it and updates severity/summary/updated_at
- notice events create items only if the plugin marks the event inbox-worthy
  or a rule uses status.inbox.add
- ok events do not create items; they resolve paired ones

current-state items (kind = current-state)
- derived from resource snapshots after each poll, with no event behind them
- example: "1 app waiting for review", "3 PRs need your review"
- recomputed each poll: created when the state condition starts holding,
  updated while it holds, auto-resolved when it stops holding
- current-state items never notify; they exist for the dashboard and inbox
```

At most one open StatusItem exists per (resource_id, event_type) and per (resource_id, current-state condition). Repetition updates; it never multiplies.

### Resolution

```txt
auto-resolve
- the closing event of an incident resolves the incident's item
- a state transition out of the state that created an item resolves it
  (app leaves REJECTED → the rejection item resolves, whatever state comes next)
- a current-state item resolves when its condition stops holding

manual dismiss
- terminal for that item; optional dismissed_reason
- dismissal does not suppress future events: if the resource transitions
  into the same bad state again later, that is a new event and a new item

snooze
- the item leaves the inbox until snooze_until
- if it auto-resolves while snoozed, it resolves silently
- if snooze_until passes and it is still unresolved, it returns to open,
  updated_at is bumped, and no new notification is sent by default
```

Resolved and dismissed items remain queryable as history but leave the inbox.

### Staleness

An open item whose `updated_at` is older than a staleness threshold is flagged `stuck`. Default threshold: 7 days, configurable per severity. Stuck items surface in a "Stuck" section of the inbox — dashboard-only, never a notification. This is how Status answers "what is stuck?" from `SPEC.md` without adding noise.

### The attention inbox

The attention inbox from `docs/12-ideas-backlog.md` is hereby promoted from idea to spec: **the attention inbox is the StatusItem UI.** It is the list of open (and expiring-snooze) StatusItems, and its verbs are exactly the lifecycle verbs above:

```txt
dismiss  → state = dismissed
snooze   → state = snoozed, snooze_until set
resolve  → state = resolved (manual resolve, for items the user fixed at the source)
open     → follow action_url
convert  → run an action (create Jira/GitHub issue) linked to the item
```

There is no separate inbox item object. `status.inbox.add` (from `docs/05-events-automation.md`) creates or updates a StatusItem.

## 5. Notification interaction

- One event produces at most one notification decision, made once, at emission time, by the rules and notification engine.
- Suppressed duplicates (section 2) never reach rule evaluation and therefore never notify.
- StatusItem updates (attach, snooze expiry, stuck flag, current-state recompute) never notify.
- Incident re-notification ("example.com is still down, 2 hours") is a per-check or global user preference. Default: off. When enabled, the reminder is generated by the core from the open incident on the user's chosen interval; it references the original event and does not create a new one.
- The closing event of an incident is a normal event and gets its own single notification decision. Default preference: notify on close only if the opening event notified.

## 6. Worked traces

These traces are the acceptance test for this document. Any implementation must produce exactly these counts.

### Trace A: App Store rejection across N polls

Setup: App Store Connect polled every 15 minutes. App "Tiko Yes No" is a known resource; the stored snapshot says review state IN_REVIEW. A default rule notifies on `app.review.rejected`.

```txt
poll 1 — API returns REJECTED
- snapshot IN_REVIEW != REJECTED → transition
- 1 event: app.review.rejected (critical),
  fingerprint appstoreconnect:app.review.rejected:app_tiko_yes_no:REJECTED
- 1 StatusItem created (kind event, state open)
- 1 notification
totals: events 1, status items 1 open, notifications 1

poll 2 — API returns REJECTED
- snapshot REJECTED == REJECTED → no transition, no candidate event
totals: events 1, status items 1 open, notifications 1

polls 3..N — API returns REJECTED
- identical: nothing emitted
totals after poll N: events 1, status items 1 open, notifications 1

poll N+1 — developer resubmitted; API returns WAITING_FOR_REVIEW
- transition REJECTED → WAITING_FOR_REVIEW
- 1 event: app.review.waiting_for_review (notice)
- the rejection StatusItem auto-resolves (transition out of REJECTED),
  resolved_at set
- a current-state item "1 app waiting for review" is created (no notification)
- the waiting event notifies only if a rule says so; default: dashboard-only
totals: events 2, status items 1 resolved + 1 current-state open,
        notifications 1
```

If the app had instead been first observed while already REJECTED (fresh account connection): 1 event with `initialObservation: true`, 1 status item, and the notification decision follows the initial-observation preference. Every subsequent poll: unchanged, per poll 2 above.

### Trace B: website down for 3 checks, then recovered

Setup: uptime check every 5 minutes. Snapshot for `example.com` says up. `website.down` opens a `downtime` incident, closed by `website.recovered`. Default rule notifies on `website.down`.

```txt
check 1 — request fails
- transition up → down
- 1 event: website.down (critical)
- 1 incident opened (inc_1), event linked
- 1 StatusItem created (open, incident_id inc_1)
- 1 notification
totals: events 1, incidents 1 open, status items 1 open, notifications 1

check 2 — request fails
- candidate suppressed: open incident inc_1 exists;
  fingerprint uptime:website.down:example.com:inc_1 collides
- inc_1 observation count 2, last_observed_at updated
- StatusItem summary/updated_at refreshed ("down for 5 minutes")
- no event, no notification (still-down reminders default off)
totals: events 1, incidents 1 open, status items 1 open, notifications 1

check 3 — request fails
- same as check 2; inc_1 observation count 3
totals: events 1, incidents 1 open, status items 1 open, notifications 1

check 4 — request succeeds
- transition down → up, open incident inc_1 exists
- 1 event: website.recovered (ok), emitted once; inc_1 closed,
  duration recorded (~15 minutes)
- StatusItem auto-resolves, resolved_at set
- 1 notification (close notifies because the open notified; default on,
  user can disable)
totals: events 2, incidents 1 closed, status items 1 resolved,
        notifications 2

check 5 and onward — request succeeds
- snapshot up == up → nothing
totals unchanged
```

## Guiding sentence

```txt
The world is polled many times; a change happens once.
One change, one event, one status item, one notification decision.
```
