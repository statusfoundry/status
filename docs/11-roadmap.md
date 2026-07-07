# Roadmap

This roadmap is intentionally staged. Status should not start as a giant integration platform. It should start as a useful native app, then grow into a plugin-based event system.

## Phase 0: Documentation and doctrine

Goal: define the product clearly before implementation.

Deliverables:

- README;
- doctrine;
- canonical spec;
- architecture;
- plugin system;
- events/automation spec;
- integrations plan;
- security/privacy doctrine;
- agent instructions;
- monetization notes;
- brand/domain notes.

Acceptance:

- product direction is clear;
- agents can work from docs;
- first implementation tasks are obvious.

## Phase 1: Native skeleton

Goal: create the app foundation.

Deliverables:

- Swift package structure;
- macOS app shell;
- iOS app shell;
- shared StatusCore package;
- shared StatusUI package;
- local database setup;
- Keychain wrapper;
- basic dashboard screen;
- settings screen;
- placeholder plugin store screen.

Acceptance:

- macOS and iOS compile;
- shared core is used by both;
- app can render mocked status items;
- local database can store events/resources;
- Keychain wrapper exists.

## Phase 2: Event engine

Goal: implement the core pipeline.

Deliverables:

- trigger model;
- job queue;
- event model;
- resource model;
- status item model;
- metric model;
- scheduler abstraction;
- event bus;
- deduplication;
- audit log model.

Acceptance:

- mock trigger creates job;
- job emits event;
- event appears in dashboard;
- audit entry is created;
- failures are stored cleanly.

## Phase 3: Declarative plugin engine

Goal: install and run config-based plugins.

Deliverables:

- plugin manifest parser;
- plugin validator;
- plugin installer;
- local plugin developer mode;
- request definitions;
- mapping engine;
- setup schema renderer;
- permission screen;
- plugin view descriptors;
- sample plugin.

Acceptance:

- app can install local sample plugin;
- app validates manifest;
- setup screen is generated from schema;
- request runs through core;
- response maps into resources/events;
- plugin-provided view descriptor renders through native UI.

## Phase 4: Built-in plugins

Goal: make Status useful without account setup.

Deliverables:

- website uptime plugin;
- manual status plugin;
- RSS/feed plugin;
- generic webhook local model;
- network check plugin, optional;
- weather plugin, optional.

Acceptance:

- user can add URL uptime check;
- down/up events are emitted;
- RSS item can become event;
- manual status can be created;
- notifications can be configured.

## Phase 5: First official external plugin

Goal: prove real integration value.

Recommended first plugin: App Store Connect.

Deliverables:

- App Store Connect plugin package;
- JWT API key setup;
- app list;
- app status mapping;
- version/build mapping;
- review state events;
- direct links;
- error handling.

Acceptance:

- user can connect Apple Developer API credentials;
- apps appear in Status;
- review states appear;
- rejected/in-review/waiting states generate events;
- direct link opens source tool.

## Phase 6: Notifications and rules

Goal: turn events into attention and action.

Deliverables:

- notification preferences;
- event-to-notification rules;
- basic rule builder;
- built-in actions;
- audit log UI;
- rule enable/disable;
- rule presets.

Acceptance:

- event can trigger notification;
- user can disable notifications for event type;
- rule can add item to inbox;
- action run appears in audit log.

## Phase 7: GitHub/Jira actions

Goal: prove cross-plugin automations.

Deliverables:

- GitHub read plugin;
- GitHub create issue action;
- Jira read plugin;
- Jira create issue action;
- rule preset: failed workflow → issue;
- rule preset: app rejected → issue.

Acceptance:

- event from one plugin can create action in another;
- write permission is requested explicitly;
- action is audited;
- direct result link is stored.

## Phase 8: Plugin registry

Goal: move from local plugins to installable plugins.

Deliverables:

- hosted registry index;
- plugin ZIP package format;
- hash verification;
- signature verification;
- install/update/uninstall UI;
- compatibility checks;
- revocation list.

Acceptance:

- app can browse registry;
- app can install plugin;
- app rejects invalid package;
- app can update plugin;
- app can remove plugin.

## Phase 9: iOS companion

Goal: make iOS useful without pretending it is always-on.

Deliverables:

- overview tab;
- alerts tab;
- integration detail;
- manual refresh;
- notification handling;
- optional config sync research.

Acceptance:

- iOS can show same normalized data model;
- iOS can refresh connected plugins where possible;
- iOS presents native compact views;
- no background reliability overpromising.

## Phase 10: Relay

Goal: support incoming pushes/webhooks.

Deliverables:

- relay endpoint;
- user/plugin hook URLs;
- token/signature verification;
- payload storage;
- device delivery/pull;
- generic webhook plugin integration.

Acceptance:

- external webhook can create event;
- relay validates request;
- Mac receives event;
- event enters normal pipeline;
- audit/log trail exists.

## Phase 11: Cloud runner

Goal: optional always-on execution.

This is not v1.

Deliverables:

- Status account;
- encrypted token handling;
- server-side scheduler;
- server-side rule engine;
- push notifications;
- billing;
- retention policy;
- cloud audit logs.

Acceptance:

- user can opt in;
- local-only still works;
- cloud actions are auditable;
- token storage is secure enough to justify trust.

## Near-term issue candidates

Create implementation issues for:

1. Set up Swift package structure.
2. Define database schema v0.
3. Define plugin JSON schema.
4. Build mocked dashboard UI.
5. Build event model and event store.
6. Build local scheduler.
7. Build sample plugin.
8. Build setup schema renderer.
9. Build permission screen.
10. Build uptime plugin.
11. Build App Store Connect plugin.
12. Build notification rule v0.
13. Build audit log UI.

## Roadmap doctrine

```txt
First: useful native dashboard.
Second: plugin-powered events.
Third: safe automations.
Fourth: relay.
Fifth: cloud runner.
```