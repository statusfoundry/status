# Agent Instructions

This repository is documentation-first. Agents should preserve the product doctrine and make implementation decisions that follow the canonical specification.

## Repository status

This repository currently contains documentation only. There is no code, build system, or test suite yet. Code, when added, must follow the docs — not redefine the product. When build tooling is added, document the build/test commands here.

## Read in this order

1. This file — work rules, non-negotiables, definition of done, decision hierarchy.
2. `DOCTRINE.md` — non-negotiable product beliefs.
3. `SPEC.md` — canonical product and technical spec: the core pipeline (`Trigger → Job → Event → Rule → Action → Notification → Audit log`), the common object model all plugins normalize into, storage, and MVP scope.
4. `docs/00`–`docs/12` — detailed docs (glossary in `00`, architecture in `03`, plugin system in `04`, events/automation in `05`).
5. `docs/13-implementation-plan.md` — the execution plan: work packages, dependencies, agent assignments.
6. `docs/20-handoff-checklist.md` — the operational runbook and non-stop defaults for implementation runs.

Implementation contracts: data model in `docs/15`, mapping language in `docs/16`, event semantics in `docs/17`, testing strategy in `docs/18`, plugin schemas in `schemas/plugin/v1/`.

## Mission

Build Status as a native macOS and iOS event-based personal operations hub.

The product should help a user understand what changed, what is stuck, what needs attention, and where to act next across many tools and accounts.

## Non-negotiables

1. Native app first.
2. Shared core across macOS and iOS.
3. Plugins are declarative adapters, not mini-apps.
4. The app owns all UI.
5. Everything flows through the event pipeline.
6. Read-only integrations first.
7. Write actions require explicit permission.
8. Notifications are controlled by the core app and user rules.
9. Local-first for v1.
10. Audit logs for every automation/action.

## Preferred implementation direction

Use Swift and SwiftUI.

Suggested package split:

```txt
StatusCore
- plugin loading
- validation
- scheduling
- job queue
- event bus
- rules engine
- action runner
- notification engine
- persistence models

StatusUI
- shared SwiftUI components
- dashboard views
- plugin store views
- setup forms
- automation builder
- audit log views

StatusMac
- macOS shell
- sidebar
- menu bar
- background runner
- local notifications

StatusiOS
- iOS shell
- tabs/navigation
- alerts
- companion dashboard
```

## Product tone

Status should be calm, clear, structured, and practical.

Avoid:

- hype language;
- over-automation;
- generic SaaS dashboard patterns;
- unnecessary charts;
- noisy notification defaults;
- vague AI features;
- magical claims.

Prefer:

- explicit status;
- direct action links;
- clear severity;
- readable audit logs;
- native controls;
- small useful workflows.

## Plugin work rules

When designing or implementing plugins:

- keep plugin schemas declarative;
- do not add arbitrary executable code in v1;
- declare all requested domains;
- declare all permissions;
- normalize into common resources/events/metrics;
- keep UI data-driven using app-owned views;
- make dangerous actions impossible by default;
- add suggested rules only when genuinely useful.

## Automation work rules

Rules should always be explainable.

Every automation must have:

- trigger;
- conditions;
- actions;
- permission requirements;
- dry-run/preview potential;
- audit log output.

Avoid irreversible actions in v1.

Allowed v1 actions:

- show notification;
- add to Status inbox;
- open URL;
- create Jira issue;
- create GitHub issue;
- send webhook;
- create email draft, if email support exists.

Avoid v1 actions:

- delete data;
- submit app builds;
- change App Store metadata;
- transition Jira issues automatically;
- send emails automatically;
- modify billing/payment state.

## Documentation rules

When adding features, update docs before or with code.

Relevant docs:

- `DOCTRINE.md` for product beliefs;
- `SPEC.md` for canonical product spec;
- `docs/03-architecture.md` for architecture;
- `docs/04-plugin-system.md` for plugins;
- `docs/05-events-automation.md` for events, rules, and actions.

## Definition of done for features

A feature is not done unless:

- the user-facing behavior is clear;
- the event model is defined;
- permissions are declared;
- errors are handled;
- audit output exists where relevant;
- the UI follows the app-owned view system;
- docs are updated.

## Decision hierarchy

When instructions conflict, follow this order:

1. Security and privacy.
2. Product doctrine.
3. Canonical spec.
4. Platform conventions.
5. Implementation convenience.

Do not sacrifice the doctrine for a quick shortcut.