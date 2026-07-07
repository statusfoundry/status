# Agents

Status should be designed so AI coding/product agents can work safely inside the project.

This document defines the agent workflow, responsibilities, and boundaries.

## Agent philosophy

Agents should help build the product, not redefine it.

The product doctrine and canonical spec are the source of truth. Agents may propose improvements, but should not silently change the direction.

## Agent roles

### Product Agent

Responsibilities:

- refine requirements;
- update docs;
- maintain roadmap;
- identify unclear decisions;
- turn conversations into specs.

### Architecture Agent

Responsibilities:

- maintain package boundaries;
- design event pipeline;
- design plugin schema;
- review cross-platform architecture;
- prevent shortcuts that break the doctrine.

### macOS Agent

Responsibilities:

- implement macOS app shell;
- menu bar status;
- background runner;
- notification handling;
- native macOS views.

### iOS Agent

Responsibilities:

- implement iOS companion app;
- compact dashboard;
- notification handling;
- platform-specific navigation;
- widgets later.

### Plugin Agent

Responsibilities:

- create plugin manifests;
- validate schemas;
- build official plugins;
- maintain example plugins;
- keep plugins declarative.

### Integration Agent

Responsibilities:

- research provider APIs;
- define auth flows;
- map provider resources/events/actions;
- document permissions;
- create test payloads.

### Security Agent

Responsibilities:

- review secret handling;
- review plugin permissions;
- review relay design;
- review action safety;
- review logging/audit behavior.

### Design Agent

Responsibilities:

- maintain native UI direction;
- create UI flows;
- keep visual hierarchy calm;
- prevent dashboard clutter;
- define component behavior.

### QA Agent

Responsibilities:

- test event flows;
- test plugin install/update;
- test account setup failures;
- test notification rules;
- test action audit logs;
- test macOS/iOS parity.

## Agent workflow

Recommended flow:

```txt
1. Read README.md, DOCTRINE.md, SPEC.md, and relevant docs.
2. Identify the specific feature or doc area.
3. Update docs/spec if behavior changes.
4. Implement only within agreed architecture.
5. Add tests or validation where possible.
6. Summarize decisions and tradeoffs.
```

## Agent constraints

Agents must not:

- add arbitrary plugin code execution in v1;
- let plugins own custom UI;
- store secrets outside Keychain;
- bypass the event pipeline;
- add write actions without permission/audit;
- turn the app into generic BI;
- make iOS the always-on runner;
- introduce cloud dependency for local MVP;
- add noisy notification defaults;
- silently change product positioning.

## Required context before coding

Agents should read:

```txt
README.md
DOCTRINE.md
SPEC.md
docs/03-architecture.md
docs/04-plugin-system.md
docs/05-events-automation.md
docs/07-security-privacy.md
```

For integration work, also read:

```txt
docs/06-integrations.md
```

## Codex prompt template

Use this when asking a coding agent to work on the repo:

```txt
You are working on Status, a native macOS/iOS personal operations dashboard.

Before changing code, read:
- README.md
- DOCTRINE.md
- SPEC.md
- docs/03-architecture.md
- docs/04-plugin-system.md
- docs/05-events-automation.md
- docs/07-security-privacy.md

Follow the doctrine:
- native first;
- shared core;
- plugins are declarative adapters;
- app owns all UI;
- everything flows through triggers/jobs/events/rules/actions/audit;
- read-only first;
- write actions require explicit permission and audit logs.

Task:
<insert task>

Deliver:
- implementation;
- tests/validation where possible;
- docs update if behavior/schema changes;
- short summary of decisions.
```

## Documentation agent prompt

```txt
You are maintaining Status product documentation.

Read README.md, DOCTRINE.md, and SPEC.md first.

Update docs to keep them aligned with the product direction:
- native macOS/iOS;
- shared core;
- declarative plugins;
- event-based pipeline;
- local-first automation;
- optional relay later;
- security-first permissions.

Do not invent a new product direction.
```

## Plugin agent prompt

```txt
You are creating a declarative Status plugin.

Read docs/04-plugin-system.md and docs/05-events-automation.md.

Create plugin files for <provider>:
- manifest.json
- auth.json
- setup.schema.json
- requests.json
- mappings.json
- triggers.json
- events.json
- actions.json if needed
- views.json
- rules.presets.json

Do not add executable plugin code.
The plugin must normalize into Status resources, events, metrics, and actions.
```

## Review checklist for agents

Before finishing, answer:

- Does this follow the event pipeline?
- Does this keep plugins declarative?
- Does this preserve app-owned UI?
- Are secrets protected?
- Are permissions explicit?
- Are write actions audited?
- Does macOS/iOS sharing still work?
- Were docs updated?

## Final rule

Agents may help build Status quickly, but must not make it incoherent.