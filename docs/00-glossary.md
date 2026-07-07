# Glossary

Canonical definitions for the core Status terms. When a doc or implementation disagrees with this glossary, fix the doc or the code, not the glossary — unless the change is deliberate and made here first.

## Pipeline terms

### Trigger

A registered reason for work to start: cron schedule, manual refresh, incoming push/webhook, another event, or an app lifecycle signal. Triggers create jobs. Triggers do not fetch data or emit events themselves.

### Job

One execution attempt started by a trigger. A job runs a plugin request or handler, and its result is success or failure plus any emitted events, updated resources, updated metrics, and audit entries. Jobs are retryable when safe.

### Event

A normalized record that something happened: `app.review.rejected`, `website.down`, `github.workflow.failed`. Events are immutable facts with a severity, a timestamp, an associated resource, and a fingerprint for deduplication. Events are the input to rules and the source of most status items and notifications. An event is not a to-do; it does not carry user state such as dismissed or snoozed.

### StatusItem

A user-facing, stateful attention item derived from events or from current resource state: "1 app waiting for review", "lezin.app is down". Unlike events, status items have a lifecycle: they can be open, resolved (automatically, by a recovery or transition event), dismissed, or snoozed. The attention inbox is the UI for status items; an "inbox item" is a StatusItem, not a separate object. Lifecycle rules live in `docs/17-event-semantics.md`.

### Metric

A numeric or time-series value attached to a resource: views over 28 days, response time, open issue count. Metrics are stored as points over time. Baseline and delta analysis over metrics (for example "views down 18%") is computed by the core, and can emit events.

### Rule

A user-owned automation definition: when this event happens, and these conditions match, then run these actions. Rules are declarative, explainable, and can be enabled, disabled, and previewed. Rules never execute code.

### Action

A controlled operation a rule (or the user) can run: show notification, add to inbox, open URL, send webhook, create a GitHub or Jira issue. Every action has a safety level (safe, review-required, dangerous, unsupported) and a permission requirement. An action is the definition; an ActionRun is one execution.

### ActionRun

One recorded execution of an action: its inputs, result, error if any, and timestamp. Every action run produces an audit entry.

### Notification

A user-facing alert owned by the core app, produced from an event by user preferences and rules — never sent directly by a plugin. A notification has a mode: immediate, digest, dashboard-only, silent-automation, or disabled. One event produces at most one notification decision.

### AuditEntry

The permanent record of what an automation or action did and why: the rule, the triggering event, the action, the inputs, the result, and the time. Audit entries exist so every automated behavior is explainable after the fact.

## Structural terms

### Plugin

A declarative integration package: manifest, auth definition, requests, mappings, triggers, events, actions, views, and rule presets. A plugin is an adapter, not a mini-app: it ships no executable code and no custom UI. Formal schemas live in `schemas/plugin/v1/`.

### Account

A connected user identity at a provider: an Apple Developer account, a GitHub account or organization, an Atlassian site. Accounts hold Keychain references to credentials, never the credentials themselves.

### Resource

A thing inside an account that Status watches: an app, a repository, a channel, a website, a Jira project, a Worker. Resources are what events, status items, and metrics attach to.

### ActionLink

A direct URL from a status item, event, or resource into the source tool — "Open App Store Connect". ActionLinks are navigation, not actions: following one changes nothing and is not audited.

### Severity

The shared scale for events and status items: `ok`, `notice`, `warning`, `critical`. Severity drives dashboard ordering and default notification behavior; the color language is defined in `docs/10-domains-brand.md`.

## Distinctions worth restating

- **Event vs StatusItem**: an event is an immutable fact; a status item is the stateful attention it demands. Many events can feed one status item; a status item can exist without a new event (derived from current state).
- **StatusItem vs Notification**: the status item is what appears in the dashboard and inbox; the notification is the optional interruption about it.
- **Action vs ActionLink**: an action does something and is audited; an action link just takes the user somewhere.
- **Rule vs Action**: the rule decides; the action does.
