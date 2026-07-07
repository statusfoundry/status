# Architecture

Status should be built as a shared core with native shells.

```txt
StatusCore
→ shared product engine

StatusUI
→ shared SwiftUI view primitives

StatusMac
→ macOS app shell

StatusiOS
→ iOS app shell

Plugin Registry
→ hosted plugin metadata and packages

Optional Relay
→ incoming webhooks and push delivery
```

## High-level system

```txt
Plugin Store
    ↓
Installed Plugins
    ↓
Trigger Registry
    ↓
Scheduler / Push Ingestion / Manual Refresh
    ↓
Job Queue
    ↓
Request + Mapping Engine
    ↓
Event Bus
    ↓
Rules Engine
    ↓
Action Runner + Notification Engine
    ↓
Audit Log + Dashboard
```

## Packages

### StatusCore

Responsibilities:

- plugin loading;
- plugin validation;
- plugin registry client;
- account model;
- authentication abstraction;
- credential references;
- request runner;
- mapping engine;
- trigger registry;
- scheduler;
- job queue;
- event bus;
- rules engine;
- action runner;
- notification model;
- audit logging;
- persistence.

### StatusUI

Responsibilities:

- shared view primitives;
- dashboard cards;
- resource lists;
- resource details;
- setup forms;
- plugin store;
- permission screens;
- automation builder;
- audit views;
- status pills;
- metric views;
- timelines.

The UI package should render based on normalized data and view descriptors. It should not know service-specific API details.

### StatusMac

Responsibilities:

- macOS app lifecycle;
- sidebar/window shell;
- menu bar item;
- background runner;
- local notification delivery;
- command palette later;
- local plugin developer mode;
- file import/export if needed.

### StatusiOS

Responsibilities:

- companion dashboard;
- compact navigation;
- alerts screen;
- integration detail views;
- manual refresh;
- notification handling;
- widgets later.

## Core execution model

Every unit of work is a job.

Jobs can be created by:

- cron triggers;
- manual refresh;
- app launch;
- plugin install;
- incoming push/webhook;
- another event.

Job result should be:

- success;
- failure;
- events emitted;
- metrics updated;
- resources updated;
- audit entries created.

## Data flow example: App Store rejected

```txt
Cron trigger fires
→ job queued: appstoreconnect.poll_apps
→ request engine calls App Store Connect API
→ mapping engine detects state change
→ event emitted: app.review.rejected
→ dashboard status item created
→ rules engine matches notification rule
→ notification action queued
→ notification delivered
→ audit entry written
```

## Data flow example: GitHub webhook

```txt
GitHub webhook arrives at relay
→ relay validates signature
→ relay stores/forwards raw payload
→ device pulls payload
→ job queued: github.handle_webhook
→ mapping engine emits github.workflow.failed
→ rules engine matches automation
→ action runner creates Jira issue
→ audit entry written
```

## Persistence

Use a local database for all non-secret data.

Suggested tables:

```txt
plugins
plugin_versions
plugin_permissions
accounts
account_resources
resources
events
status_items
metrics
metric_points
triggers
jobs
rules
action_runs
notifications
audit_entries
sync_state
```

Secrets are never stored in the database. Store only references to Keychain entries.

Current implementation status:

- macOS and iOS open the local SQLite database from Application Support at launch.
- The dashboard renders persisted status items, events, metrics, accounts, and audit entries through `StatusPersistenceStore.dashboardSnapshot`.
- Shared SwiftUI now includes focused read-only operational surfaces for alerts, disabled/enabled rules, audit entries, and local runtime settings. macOS exposes Overview, Integrations, Rules, Audit Log, and Settings in the sidebar; iOS exposes Overview, Alerts, Integrations, Rules, and Settings as companion tabs.
- The app shells can run installed declarative plugin requests through `PluginRuntimeService`: load the installed package, enqueue a configured manual job from the plugin trigger, execute the queued request/mapping pipeline, persist resources/events/status items, and write a job audit entry. Website Uptime also has the first native setup path for a user-configured host, persisted as non-secret account configuration.
- Empty local databases render a calm empty state; `MockDashboard` is reserved for previews and tests.

## Plugin registry

The registry will be hosted on Cloudflare. The initial shape is static registry metadata plus signed ZIP packages, with a Cloudflare Worker providing the registry API.

```txt
Cloudflare Pages
→ marketing website
→ public plugin directory
→ developer docs

Cloudflare R2
→ immutable signed plugin ZIP packages
→ package signatures/checksums
→ registry snapshots

Cloudflare Workers
→ registry API
→ compatibility filtering
→ revocation/blocklist API
```

Canonical public endpoints:

```txt
https://plugins.status.app/v1/plugins
https://plugins.status.app/v1/plugins/{pluginId}
https://plugins.status.app/v1/revocations
https://plugins.status.app/plugins/{pluginId}/{version}/{pluginId}-{version}.statusplugin.zip
```

The app should verify:

- plugin ID;
- version;
- compatibility;
- hash;
- signature;
- revocation status;
- requested permissions;
- declared domains.

Cloudflare helps distribute plugins, but the native app still makes the local trust decision. Package verification must not depend only on a Worker response.

See `docs/19-cloudflare-platform.md` for the hosting plan.

## Relay architecture

The relay is optional for v1, but should be designed early.

Relay responsibilities:

- receive webhooks;
- validate relay token;
- validate provider signature where possible;
- store payload temporarily;
- notify registered devices;
- allow devices to pull payload;
- keep minimal state.

The relay should not execute arbitrary automations in v1.

## Cloud runner architecture

Future cloud runner responsibilities:

- scheduled jobs when no Mac is running;
- always-on rules;
- push notifications;
- server-side actions;
- encrypted token storage;
- billing/account management.

Do not build this first.

## Local-first model

v1 should work without a Status account.

Possible v1 modes:

```txt
Local only
- config stored locally
- secrets in Keychain
- Mac runs jobs
- iOS connects separately

Local + iCloud later
- sync non-secret config
- secrets remain local per device

Local + Relay later
- relay only receives incoming pushes
- device still evaluates rules
```

## Error handling

Every job should produce a result.

Failures should include:

- plugin ID;
- trigger ID;
- account ID;
- error code;
- user-facing summary;
- retry eligibility;
- timestamp.

A failed integration should create a status item if it affects trust.

Example:

```txt
GitHub could not refresh because token expired.
Reconnect account.
```

## Scheduling

The scheduler should support:

- interval schedules;
- cron-like schedules;
- manual run;
- disabled triggers;
- backoff after failures;
- per-plugin limits;
- global network limits.

Avoid overly frequent polling by default.

## Security boundary

The core must mediate all plugin capabilities.

Plugins cannot:

- read arbitrary files;
- access Keychain directly;
- call undeclared domains;
- execute native code;
- create UI outside the view system;
- access other plugin accounts;
- run uncontrolled background work.

The core can:

- fetch declared URLs;
- provide secrets to allowed auth flows;
- map responses;
- emit events;
- queue actions;
- render views;
- log everything.

## Recommended implementation stack

- Swift;
- SwiftUI;
- SQLite using GRDB or another mature wrapper;
- Keychain Services;
- URLSession;
- local package modules;
- signed plugin ZIP packages;
- hosted registry on Cloudflare Workers/R2 or static hosting;
- direct macOS distribution first;
- iOS via TestFlight/App Store.
