# Events and Automation

Status should be fully event-based.

Plugins emit events. The core owns the event bus, notification decisions, rules, actions, and audit log.

## Universal pipeline

```txt
Trigger
→ Job
→ Event
→ Rule
→ Action
→ Notification
→ Audit Log
```

The same pipeline is used for:

- cron jobs;
- manual refreshes;
- incoming pushes/webhooks;
- local checks;
- plugin state changes;
- event-based follow-up rules.

## Implementation status

`StatusCore` currently includes the first local execution primitives:

- `TriggerDefinition` and `TriggerScheduler` classify cron/manual/push/event/app-lifecycle triggers.
- Cron triggers can be evaluated deterministically and enqueue jobs when due.
- Manual triggers enqueue only when explicitly requested, and installed plugin trigger metadata now retains the declarative request ID needed to execute the queued job.
- Failure backoff and success reset logic are implemented in core.
- `InMemoryJobQueue` tracks queued/running/success/failed job lifecycle for tests and app scaffolding.
- `StatusPersistenceStore` can round-trip trigger definitions and job records through SQLite.
- `PluginRuntimeService` can enqueue a configured manual plugin job and execute a specific queued job, preserving `Trigger → Job → request/mapping → audit` provenance for app-initiated refreshes.
- Audit entries can now attach job, event, and action-run provenance; persisted event ingestion and job lifecycle audit rows use those references.
- The core action runner executes safe built-in local actions, records deterministic action-run rows, and denies review-required or unsupported actions until explicit permission/provider support exists.
- `AutomationPipeline` evaluates inserted events against rules, runs matching actions, and persists both action-run records and audit entries.
- Rules persist to SQLite with structured condition/action JSON, and the automation pipeline can evaluate the stored local rule set for an event.

Background timers, retry execution, timeouts, and platform delivery adapters for local notifications/open-URL remain planned work.

## Triggers

A trigger starts work.

Types:

```txt
cron
manual
push
event
app-lifecycle
```

### Cron trigger

Runs on a schedule.

Examples:

- check App Store Connect every 15 minutes;
- check uptime every 5 minutes;
- check YouTube stats every 6 hours;
- check GitHub PRs every 30 minutes.

### Manual trigger

Runs when the user clicks refresh or a command is executed.

### Push trigger

Runs when an external service sends a webhook or push payload.

Examples:

- GitHub workflow event;
- Stripe payment event;
- Sentry issue event;
- custom webhook from a deployment script.

### Event trigger

Runs when another event happens.

Example:

```txt
When github.workflow.failed happens
→ run rule that creates a Jira issue
```

## Jobs

A job is one execution attempt.

Fields:

```txt
id
plugin_id
trigger_id
account_id
status
started_at
finished_at
error
emitted_event_ids
metadata_json
```

Job statuses:

```txt
queued
running
success
failed
cancelled
skipped
```

Jobs should be retryable when safe.

## Events

An event is a normalized thing that happened.

Example:

```json
{
  "id": "evt_123",
  "provider": "appstoreconnect",
  "type": "app.review.rejected",
  "resourceId": "app_tiko_yes_no",
  "resourceName": "Tiko Yes No",
  "severity": "critical",
  "title": "App rejected",
  "summary": "Reviewer could not complete login.",
  "timestamp": "2026-07-07T12:00:00Z",
  "actionUrl": "https://appstoreconnect.apple.com/..."
}
```

Event fields:

```txt
id
provider
type
resource_id
resource_name
severity
title
summary
timestamp
action_url
payload_json
raw_payload_ref
fingerprint
```

## Event severity

Severity levels:

```txt
ok
notice
warning
critical
```

Rules:

- `ok` should rarely notify;
- `notice` may appear in dashboard;
- `warning` may notify depending on preferences;
- `critical` should be notification-worthy by default.

## Event deduplication

Events should have a fingerprint.

Example fingerprint inputs:

```txt
provider + event_type + resource_id + relevant_state + date_bucket
```

This prevents repeated polling from creating duplicate notifications.

## Rules

Rules are the IFTTT-ish layer.

Structure:

```txt
When this happens
And these conditions match
Then do these actions
```

Example:

```json
{
  "name": "App rejected → Jira ticket",
  "enabled": true,
  "when": {
    "eventType": "app.review.rejected",
    "provider": "appstoreconnect"
  },
  "if": [
    {
      "field": "resourceName",
      "operator": "contains",
      "value": "Tiko"
    }
  ],
  "then": [
    {
      "action": "notification.show",
      "title": "{{event.title}}",
      "body": "{{event.summary}}"
    },
    {
      "action": "jira.createIssue",
      "project": "TIKO",
      "summary": "{{event.resourceName}} rejected",
      "description": "{{event.summary}}\n\n{{event.actionUrl}}"
    }
  ]
}
```

## Conditions

Supported operators for v1:

```txt
equals
not_equals
contains
not_contains
starts_with
ends_with
greater_than
less_than
is_empty
is_not_empty
matches_severity
```

Avoid complex scripting in v1.

## Actions

Actions are controlled outputs.

Built-in actions:

```txt
notification.show
notification.digest
status.inbox.add
status.open_url
webhook.post
audit.note
```

Plugin actions:

```txt
jira.createIssue
github.createIssue
github.comment
email.createDraft
```

Future illustrative examples, not planned for v1 and not backed by any planned integration:

```txt
slack.sendMessage
calendar.createEvent
```

Actions must declare permissions.

Current implementation status:

- `notification.show`, `status.inbox.add`, `status.open_url`, and `audit.note` are safe local core actions.
- `webhook.post`, `jira.createIssue`, `github.createIssue`, `github.comment`, and `email.createDraft` are review-required and are denied by the core runner until explicit write permission and provider execution are wired.
- Unknown actions are recorded as unsupported rather than executed.

## Action safety levels

```txt
safe
review-required
dangerous
unsupported
```

### Safe

Low-risk actions.

Examples:

- show notification;
- add to inbox;
- open URL;
- create local note.

### Review-required

External write actions that are usually safe but visible.

Examples:

- create Jira issue;
- create GitHub issue;
- send Slack message;
- create email draft.

### Dangerous

Avoid in v1.

Examples:

- delete issue;
- submit app build;
- change billing setting;
- send email automatically;
- transition production state.

## Notifications

Plugins do not send notifications directly.

Plugins declare notification-worthy events. The core decides based on user settings.

Notification modes:

```txt
immediate
digest
dashboard-only
silent-automation
disabled
```

Notification object:

```txt
id
event_id
rule_id
title
body
mode
delivered_at
dismissed_at
action_url
```

## Automation builder UI

The UI should be compact and native.

Example:

```txt
When
[App Store Connect] [App review status changes to] [Rejected]

Conditions
[App name] [contains] [Tiko]

Then
[Show notification]
[Create Jira issue in] [TIKO]
```

## Rule presets

Plugins can ship rule presets.

Examples:

- Notify me when an app is rejected.
- Create a Jira issue when a GitHub workflow fails.
- Notify me when a website is down.
- Add to inbox when YouTube views drop below normal.
- Send webhook when Stripe payment fails.

Presets should be optional and explain permissions.

## Dry run

The rules engine should later support dry run:

```txt
This rule would have triggered 3 times in the last 30 days.
```

Useful for avoiding noisy rules.

## Audit log

Every action run must be logged.

Audit entry example:

```txt
Rule: App rejected → Jira ticket
Triggered by: Tiko Yes No rejected
Action: Create Jira issue
Result: Created TIKO-184
Time: Jul 7, 2026, 13:12
```

Audit fields:

```txt
id
job_id
rule_id
event_id
action_id
action_type
status
input_json
result_json
error
timestamp
```

## Incoming push layer

For local-only v1, external pushes are difficult because a Mac app does not usually have a stable public URL.

The architecture should support a later relay:

```txt
External service
→ hooks.status.app
→ validate token/signature
→ store payload
→ notify devices
→ device pulls payload
→ local rules engine processes event
```

The relay should be minimal at first.

Relay responsibilities:

- receive payload;
- validate signature;
- store briefly;
- deliver to user devices;
- avoid executing automations in v1.

## Generic webhook plugin

Generic Webhook should be bundled.

Example payload:

```json
{
  "type": "deploy.failed",
  "resource": "lezin.app",
  "title": "Deploy failed",
  "summary": "Production deploy failed on main branch.",
  "severity": "critical",
  "url": "https://github.com/..."
}
```

This lets users connect anything before official plugins exist.

## v1 automation scope

Build:

- event store;
- notification rules;
- basic condition matching;
- safe built-in actions;
- one external create action, such as GitHub issue or Jira issue;
- audit log.

Do not build:

- arbitrary code rules;
- deeply nested logic;
- loops;
- automatic destructive actions;
- cloud execution;
- multi-user workflow approvals.

## Guiding sentence

```txt
Events explain what happened. Rules decide what matters. Actions handle the follow-up.
```
