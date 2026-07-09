# Status Canonical Specification

This is the canonical product and technical specification for Status.

## Product summary

Status is a native macOS and iOS app that gives the user one operational overview across services such as App Store Connect, YouTube, Jira, GitHub, Cloudflare, Stripe, uptime checks, RSS feeds, and custom webhooks.

Status is built around events, not pages. Apps emit events through declarative plugins. The core evaluates those events, turns them into status cards, notifications, actions, automations, and audit entries.

## Platform targets

### macOS

Primary platform.

Responsibilities:

- full dashboard;
- plugin installation and management;
- account setup;
- local scheduler;
- background refresh;
- event processing;
- rules engine;
- notifications;
- action execution;
- menu bar status;
- audit log;
- local developer plugin mode.

### iOS

Companion platform initially.

Responsibilities:

- dashboard overview;
- alerts;
- resource details;
- manual refresh;
- notification handling;
- quick actions;
- rule viewing;
- limited rule editing later.

Do not assume iOS can act as an always-on automation runner.

v1 data posture: the iOS app is a dashboard shell built on the same shared models, using mocked or locally refreshed data. Real cross-device data sync (iCloud or relay-based) is deferred and must be specced before it is claimed anywhere. See `docs/00-glossary.md` and `docs/02-requirements.md`.

## Core pipeline

Everything enters one pipeline:

```txt
Trigger
→ Job
→ Plugin Request/Handler
→ Event
→ Rule Evaluation
→ Action Queue
→ Notification
→ Audit Log
```

Trigger sources:

- cron schedule;
- manual refresh;
- incoming push/webhook;
- event-based trigger;
- local system signal;
- app lifecycle event.

## Main object model

### Plugin

A declarative integration package available from the registry, bundled with the app, or installed locally in Developer Mode.

Fields:

- id;
- name;
- version;
- author;
- description;
- category;
- icon;
- accent color;
- supported platforms;
- minimum core version;
- permissions;
- domains;
- auth methods;
- triggers;
- requests;
- events;
- actions;
- views;
- suggested rules.

### App

A configured user-facing instance created from a plugin.

Rules:

- a plugin can be available without any configured app;
- one plugin can create many apps with different accounts, credentials, settings, rules, notification preferences, dashboard tile configuration, resources, metrics, and source links;
- the dashboard and sidebar show apps, not raw plugin packages;
- the plugin catalog shows available plugins and starts app setup;
- each app has an editable local display name;
- app settings open separately from the plugin catalog;
- removing an app deletes that configured app's local setup, schedules, app-scoped rules, notification overrides, credential reference, active resources, metrics, and sync state without uninstalling the plugin or deleting historical events and audit entries;
- rules and notification preferences are app-scoped by default;
- cross-app rules exist only when the user explicitly links two or more apps.

Examples:

- `Status Foundry GitHub` and `Hakobs GitHub` can both use the GitHub plugin;
- `Hakobs App Store Connect` can use the App Store Connect plugin;
- `status.hakobs.com uptime` can use the Website Uptime plugin.

Implementation note: the current local `accounts` and configured-plugin records are the v1 storage start for Apps. Product language should use **Plugin** for registry/package availability and **App** for configured instances. A later persistence migration may add an explicit `apps` table if the `accounts` name becomes limiting.

### Account

A connected user account for a provider.

Examples:

- Apple Developer account;
- Google account;
- Atlassian site;
- GitHub account or organization;
- Cloudflare account.

### Resource

A thing inside an account.

Examples:

- app;
- YouTube channel;
- Jira project;
- GitHub repository;
- Cloudflare Worker;
- website;
- feed.

### Event

A normalized thing that happened.

Examples:

- `app.review.rejected`;
- `youtube.channel.views_dropped`;
- `jira.issue.assigned`;
- `github.workflow.failed`;
- `website.down`;
- `webhook.received`.

### StatusItem

A user-facing status derived from an event or current state.

### Metric

A numeric or time-series value.

Examples:

- views last 28 days;
- subscriber delta;
- open issues;
- failed deploys;
- uptime percentage;
- response time.

### Rule

An IFTTT-like automation definition:

```txt
When this happens
And these conditions match
Then perform these actions
```

### Action

A controlled operation performed by the core or a plugin.

Examples:

- show notification;
- create Jira issue;
- create GitHub issue;
- send webhook;
- create email draft;
- add to Status inbox;
- open URL;
- add audit note.

### Notification

A user-facing alert owned by the core app.

Modes:

- immediate;
- digest;
- dashboard only;
- silent automation;
- disabled.

### AuditEntry

A record of what happened and why.

Every action run should produce an audit entry.

## Plugin philosophy

Plugins are not executable apps. They are integration definitions used to create configured Status apps.

Allowed:

- auth schemas;
- setup form schemas;
- HTTP request definitions;
- response mappings;
- event declarations;
- action declarations;
- rule presets;
- view descriptors;
- icons and metadata.

Not allowed in v1:

- arbitrary native code;
- arbitrary JavaScript execution;
- arbitrary custom UI;
- filesystem access;
- plugin-to-plugin secret access;
- background daemons;
- unrestricted network access.

## View system

The app owns all views.

Supported view primitives:

- overview cards;
- resource list;
- resource detail;
- status table;
- metric grid;
- line chart;
- bar chart;
- timeline;
- alert list;
- log feed;
- setup form;
- permissions screen;
- automation builder;
- audit log.

Plugins may declare which views apply and which fields to show. Each configured app can choose which supported dashboard tile and detail views are enabled for that app. The app dashboard tile is intentionally compact: it should show the most important current state, recent critical events, or key metrics for that configured app. Clicking a tile or sidebar app opens that app's detail page, rendered from plugin-declared view descriptors and local app settings.

The same plugin should render differently but natively on macOS and iOS.

## Storage

Local data:

- SQLite database for cache, resources, events, metrics, rules, action runs, sync state, plugin installs.
- Configured apps are currently stored as account/configuration rows tied to a plugin. The product concept is App; the storage name can remain `accounts` for v1 until a migration is worth the churn.

Secrets:

- Keychain only.
- Never store tokens, API keys, private keys, or refresh tokens in plain SQLite or plugin files.

Plugin files:

- installed under app support directory;
- signed package metadata stored in database;
- version and hash tracked.

## Background execution

### v1

Mac is the primary runner.

- local cron scheduler;
- local queue;
- local rules;
- local actions;
- local notifications.

iOS is companion.

- refresh on open;
- manual refresh;
- best-effort background refresh;
- notifications where possible.

### v2

Optional relay service.

- receives incoming webhooks;
- validates signatures;
- forwards events to devices;
- supports push notifications.

### v3

Optional cloud runner.

- always-on cron execution;
- server-side rule evaluation;
- server-side notifications;
- server-side actions;
- encrypted token storage;
- account/billing model.

## Bundled plugins

Initial built-in plugins should be simple and universal:

- website uptime;
- network check;
- manual status;
- RSS/feed;
- generic webhook;
- weather, optional.

## Store plugins

Initial store plugins:

- App Store Connect;
- GitHub;
- Jira;
- YouTube;
- Cloudflare;
- Stripe;
- Sentry;
- Plausible/Fathom;
- Gmail, later;
- Google Calendar, later.

## MVP requirements

The first MVP should prove:

1. A native macOS dashboard can show normalized status from multiple sources.
2. Plugins can be installed without being bundled.
3. One plugin can create multiple configured apps with separate names, credentials, settings, dashboard tiles, and detail views.
4. A plugin can define auth, requests, mappings, events, actions, rules, and views.
5. Events can become app-scoped notifications.
6. App-scoped rules can run safe actions.
7. Cross-app rules can run only when explicitly configured.
8. The audit log can explain what happened.

Minimum MVP plugins:

- Website uptime;
- App Store Connect;
- GitHub (Jira follows as the second external target in Phase 7);
- Generic webhook.

## Naming

Working name: Status.

The name is simple, but may be difficult to own. Keep the working name until brand/domain research proves otherwise.

## Success criteria

Status is successful when opening the app answers these questions in under 10 seconds:

- Are all my important products okay?
- What changed since I last checked?
- What is stuck?
- What needs a reply, fix, or decision?
- Where do I click to resolve it?
- Did any automation run, and why?
