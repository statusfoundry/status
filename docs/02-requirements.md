# Requirements

This document captures product and technical requirements for Status.

## Product requirements

### Must have

- Native macOS app.
- Native iOS companion app.
- Shared core package used by both apps.
- Plugin registry/store.
- Declarative plugin format.
- Built-in plugin view primitives.
- Local plugin installation.
- Plugin signature/hash verification.
- Account connection flow.
- Keychain secret storage.
- Local database.
- Event pipeline.
- Cron/scheduled triggers.
- Manual refresh triggers.
- Incoming webhook/push trigger model.
- Rules engine.
- Notification engine.
- Action runner.
- Audit log.
- Overview dashboard.
- Integration detail views.
- Resource lists.
- Resource detail panels.
- Plugin permissions screen.
- Rule builder.
- Basic built-in plugins.

### Should have

- Menu bar status on macOS.
- Quick global search/command palette.
- Status digest.
- Dry-run rule preview.
- Suggested automation presets.
- Import/export of local config.
- Developer mode for local plugin manifests.
- Generic webhook plugin.
- Website uptime plugin.
- App Store Connect plugin.
- GitHub plugin.
- Jira plugin.
- YouTube plugin.
- Cloudflare plugin.

### Could have

- iCloud sync for non-secret config.
- Optional Status Cloud relay.
- Push notifications to iOS.
- Optional always-on cloud runner.
- Widgets.
- Shortcuts support.
- Markdown/report export.
- Plugin developer tooling.
- Public plugin directory.
- Plugin compatibility test suite.

### Will not have in v1

- Arbitrary plugin UI.
- Arbitrary plugin code execution.
- Full Zapier-style workflow complexity.
- Multi-user collaboration.
- Enterprise RBAC.
- Cloud-only operation.
- Server-side action execution.
- Irreversible write actions.
- App Store submission automation.
- YouTube posting automation.
- Email auto-send.

## Functional requirements

### Dashboard

The dashboard must show:

- current overall state;
- critical items;
- notices;
- recently changed items;
- connected integrations;
- last sync time;
- action links.

The dashboard should answer:

- Is everything okay?
- What changed?
- What needs attention?
- What is stuck?
- Where do I click?

### Integrations

The app must support installable integrations.

Each integration must provide:

- identity;
- icon;
- description;
- setup schema;
- permissions;
- auth configuration;
- triggers;
- emitted events;
- view descriptors;
- optional action capabilities;
- optional rule presets.

### Plugin store

The plugin store must support:

- available plugin list;
- installed plugin list;
- plugin search/filtering;
- plugin install;
- plugin update;
- plugin uninstall;
- compatibility check;
- permission review;
- signature/hash verification;
- revocation/blocklist support.

### Events

The event system must support:

- normalized event objects;
- event severity;
- resource association;
- timestamps;
- raw payload reference;
- deduplication;
- event history;
- event-to-status mapping;
- event-to-rule triggering.

### Rules

Rules must support:

- event triggers;
- cron triggers;
- manual triggers;
- conditions;
- actions;
- templates;
- enable/disable;
- audit log;
- preview/dry-run later.

### Notifications

Notifications must support:

- immediate notification;
- digest notification;
- dashboard-only events;
- per-plugin defaults;
- per-event preferences;
- quiet mode later.

### Actions

Actions must be explicit and permissioned.

Initial safe actions:

- show notification;
- add to Status inbox;
- open URL;
- send webhook;
- create GitHub issue;
- create Jira issue;
- create draft message later.

## Non-functional requirements

### Performance

- App launch should feel instant.
- Dashboard should render from local cache first.
- Refresh should run in the background.
- Slow integrations should not block the UI.
- Each plugin sync should have timeout and retry limits.

### Reliability

- Failed plugin syncs should not crash the app.
- Failed actions should be logged.
- Credentials should fail closed.
- Plugin updates should be reversible where possible.
- Events should be deduplicated.

### Security

- Secrets only in Keychain.
- Plugin packages verified before installation.
- Plugins can call only declared domains.
- Write actions require explicit user approval.
- Dangerous actions should not exist in v1.
- Audit logs should be available for actions.

### Privacy

- Local-first by default.
- No unnecessary telemetry.
- No hidden cloud dependency for v1.
- User should understand what each plugin can access.
- Cloud relay should be optional when introduced.

### Portability

- Plugin format should be platform-neutral.
- Same plugin should work on macOS and iOS where platform capabilities allow.
- View descriptors should render into platform-native layouts.

## MVP acceptance criteria

MVP is acceptable when:

- user can install the app on macOS;
- user can connect at least two integrations;
- dashboard shows normalized status from both;
- events are stored locally;
- notifications can be configured;
- at least one rule can be created;
- at least one safe action can run;
- audit log explains the action;
- plugin docs and schema exist;
- iOS app renders the same shared models in companion form, with mocked or locally refreshed data; cross-device sync is explicitly out of MVP scope.

## Product quality bar

The app should not ship if it feels like a generic Electron dashboard.

Status must feel like a real Apple-platform utility: fast, direct, quiet, readable, native.