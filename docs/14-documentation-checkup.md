# Documentation Checkup

This checkup reviews the current documentation for product coherence, implementation readiness, and multi-agent execution.

## Overall assessment

The documentation makes sense and has a strong product spine. The doctrine, canonical spec, architecture, plugin system, automation model, security posture, roadmap, and agent roles all point in the same direction:

```txt
Native app
Shared core
Declarative plugins
Event pipeline
Local-first execution
Permissioned actions
Auditable automation
```

The main risk is not product confusion. The main risk is implementation ambiguity. The docs define the right system, but several core contracts are still examples rather than specifications. If agents start coding before those contracts are hardened, they will make incompatible decisions about storage, plugin schemas, mapping semantics, event deduplication, iOS data sharing, OAuth, signing, and StatusItem lifecycle.

## What is strong

### Product doctrine

`DOCTRINE.md` is clear and useful. The product is not trying to become a generic dashboard, Zapier clone, BI tool, or cloud-first automation platform. The constraints are strong enough to guide implementation decisions.

Strengths:

- "The app owns the experience" prevents plugin UI fragmentation.
- "Plugins are adapters" keeps extensibility bounded.
- "Everything is an event" creates a single architecture.
- "Read-only first" and "notifications are user-owned" reduce trust risk.
- The common object list gives integrations a shared target.

### Canonical spec

`SPEC.md` gives the right top-level model and platform split. The macOS/iOS responsibility split is especially important: macOS is the primary runner, iOS is initially a companion.

Strengths:

- The core pipeline is explicit.
- The object model is compact and product-shaped.
- Plugin restrictions are stated plainly.
- Local storage and Keychain boundaries are clear.
- MVP success criteria are useful and user-centered.

### Architecture direction

`docs/03-architecture.md` is structurally sound. The package split (`StatusCore`, `StatusUI`, `StatusMac`, `StatusiOS`) matches the product doctrine and is practical for Swift/SwiftUI.

Strengths:

- Core responsibilities are separated from native shells.
- The plugin registry and relay are designed as later layers.
- The security boundary around plugins is explicit.
- Error handling and scheduler needs are recognized early.

### Plugin system

`docs/04-plugin-system.md` gives a good mental model for declarative plugins. The package shape is understandable, and the examples are concrete enough to show intent.

Strengths:

- Plugins cannot run arbitrary code.
- Requests, mappings, events, views, and actions are separated.
- Permissions and declared domains are core concepts.
- Developer mode is scoped as local and warning-heavy.

### Events and automation

`docs/05-events-automation.md` has the right automation shape: explainable rules, bounded operators, controlled actions, notification modes, and audit logs.

Strengths:

- The rule model is simple enough for v1.
- Action safety levels are useful.
- Dry run is correctly treated as later but designed for.
- The audit log example is human-readable.

### Security and privacy

`docs/07-security-privacy.md` is aligned with the product. It treats security as product behavior, not infrastructure cleanup.

Strengths:

- Secrets are Keychain-only.
- Plugins are constrained by domains and permissions.
- Relay privacy is bounded.
- Telemetry guidance is conservative.
- Threat model is present and actionable.

### Agent execution

`docs/08-agents.md` and `docs/13-implementation-plan.md` are strong foundations for multi-agent work. The agent roles map well to the architecture, and the implementation plan already breaks the roadmap into claimable work packages.

## Gaps that should be closed before coding

These are implementation blockers, not polish items.

### 1. Database schema is not specified

The docs list tables, but not columns, indexes, relationships, retention rules, or migration strategy.

Impact:

- Agents will invent incompatible persistence models.
- Event, StatusItem, job, notification, and audit behavior will drift.
- Plugin install/update/revocation state may be hard to migrate.

Required fix:

- Add `docs/15-data-model.md` or similar.
- Define table columns, IDs, foreign keys, indexes, timestamps, JSON fields, migration versioning, and Keychain reference patterns.

Covered by implementation plan:

- `WP-0.1 Database schema v0`.

### 2. Plugin JSON schemas are examples, not contracts

The plugin package shape is clear, but there are no formal JSON Schemas.

Impact:

- Plugin authors and agents cannot validate packages consistently.
- Manifest fields, events, mappings, views, actions, and rule presets may diverge.
- The relationship between `manifest.json` capabilities and `events.json` declarations is ambiguous.

Required fix:

- Add versioned schemas under `schemas/plugin/v1/`.
- Decide unknown-field policy.
- Make every example validate.

Covered by implementation plan:

- `WP-0.2 Plugin package JSON Schemas`.

### 3. Mapping language is underspecified

Examples use JSONPath-like selectors and expressions, but there is no exact grammar.

Impact:

- Implementers may accidentally create a scripting language.
- Declarative plugin safety depends on this being small and deterministic.
- Pagination, conditions, template variables, and escaping need exact behavior.

Required fix:

- Define the JSONPath subset.
- Define comparison operators, templates, conditional emission, pagination, severity mapping, and explicit non-goals.

Covered by implementation plan:

- `WP-0.3 Mapping and expression language spec`.

### 4. Event semantics and StatusItem lifecycle are underdefined

The docs say events should deduplicate and status items derive from events/current state, but lifecycle rules are not formal.

Impact:

- Polling may emit repeated events.
- Down/recovered flows may create unresolved stale items.
- The relationship between StatusItem, attention inbox, notification, and event is unclear.

Required fix:

- Define state-change detection versus fingerprint deduplication.
- Define event fingerprint fields and collision behavior.
- Define StatusItem fields, resolution, dismissal, snooze, stale handling, and inbox relationship.

Covered by implementation plan:

- `WP-0.4 Event semantics: state change, dedup, StatusItem lifecycle`.

### 5. Native OAuth is not decided

`oauth2` is listed, and YouTube/Google are roadmapped, but declarative plugins cannot safely own client secrets.

Impact:

- OAuth integrations could be implemented insecurely.
- Agents may hardcode provider-specific assumptions into plugins.
- YouTube may look MVP-ready when auth is not yet specced.

Required fix:

- Decide whether OAuth is v1 or deferred.
- If v1, define PKCE, redirect URI scheme, client ownership, token refresh, and Keychain storage.
- If deferred, move OAuth-heavy integrations later.

Covered by implementation plan:

- `WP-0.5 Auth flows decision: OAuth on native`.

### 6. Plugin signing is named but not specified

The signing scheme is now defined and implemented for the development registry path.

Impact:

- Production registry signing still needs release key custody and rotation.
- Developer Mode unsigned install UX remains future work.

Required fix:

- Replace the repository development signing key with production release custody before public distribution.
- Finish the Developer Mode unsigned install surface.

Covered by implementation plan:

- `docs/07-security-privacy.md` and the implemented `PluginPackageVerifier`.

### 7. iOS companion data model is contradictory

The docs say iOS is companion and should read the same model, while architecture also says local-first can mean iOS connects separately.

Impact:

- Agents may build iCloud sync, duplicate account setup, or defer iOS data without agreement.
- MVP acceptance cannot be evaluated.

Required fix:

- Pick one v1 posture:
  - independent account setup per device;
  - read-only non-secret iCloud sync;
  - iOS deferred until after local macOS MVP.

Covered by implementation plan:

- `WP-0.7 iOS companion data decision`.

### 8. Testing strategy is missing

There is no testing doctrine for a product that depends on schemas, mappings, event semantics, and action safety.

Impact:

- Agents may add code without fixture coverage.
- Mapping changes may silently break plugins.
- Rule/action/audit flows may become hard to trust.

Required fix:

- Add test strategy for packages, schemas, mapping golden tests, provider fixtures, rules, action audit, and CI.

Covered by implementation plan:

- `WP-0.8 Testing strategy`.

## Smaller inconsistencies

These are not blockers, but they should be cleaned up during spec hardening.

### MVP integration wording

`SPEC.md` says "GitHub or Jira" for MVP, while `README.md` suggests GitHub specifically. This is minor, but agents need one target.

Suggested decision:

- Use GitHub as the first cross-plugin external target, then Jira for action proof if needed.

### Weather plugin scope

Weather appears as optional bundled functionality. It is low-risk, but it can distract from the product's operational focus.

Suggested decision:

- Keep weather optional and after uptime/RSS/manual/generic webhook.

### Illustrative actions

`docs/05-events-automation.md` lists `slack.sendMessage` and `calendar.createEvent`, but those integrations are not planned in the same detail as GitHub/Jira.

Suggested decision:

- Mark them explicitly as future illustrative examples or remove them from v1 action lists.

### Generic webhook before relay

Roadmap Phase 4 says "generic webhook local model", but local-only webhook behavior is not defined.

Suggested decision:

- Decide whether v1 means local HTTP listener, manual payload import, polling a local file, or defer true inbound webhooks until relay.

### Glossary

The docs use Event, StatusItem, Notification, inbox item, Metric, Action, ActionRun, and AuditEntry. The terms are sensible but not always sharply separated.

Suggested decision:

- Add `docs/00-glossary.md` or a glossary section in `SPEC.md`.

## Does the product need to be extended?

Not with new features yet. The current product is already broad. The next work should narrow and formalize, not expand.

Do extend the docs in these ways:

- formal schema docs;
- formal data model;
- formal mapping language;
- formal event/status lifecycle;
- formal auth and signing decisions;
- formal testing strategy.

Do not extend v1 into:

- cloud runner;
- broad OAuth provider set;
- generic workflow automation;
- plugin marketplace monetization;
- custom plugin UI;
- destructive actions;
- team collaboration.

## Implementation readiness verdict

Current state:

```txt
Product direction: ready
Architecture direction: ready
Implementation contracts: not ready
Multi-agent planning: mostly ready
Coding readiness: only for skeleton/UI scaffolding
```

Safe to start immediately:

- Swift workspace/package skeleton.
- Mock dashboard UI.
- Native shell exploration.
- Documentation hardening work packages.

Do not start yet:

- Real plugin engine.
- Mapping engine.
- Database implementation beyond a throwaway prototype.
- OAuth provider integrations.
- Plugin registry verification.
- Cross-plugin actions.

## Recommended execution

Use `docs/13-implementation-plan.md` as the operating plan. Start with Milestone 0 and only allow Milestone 1 skeleton work in parallel.

Suggested first assignments:

1. Product Agent: glossary and doc consistency.
2. Architecture Agent: data model and event semantics.
3. Plugin Agent: plugin JSON Schemas.
4. Security Agent: signing and auth decisions.
5. QA Agent: testing strategy.
6. Design/macOS Agent: mocked dashboard shell only, using mock data.

This keeps the project moving while preventing agents from inventing core contracts independently.
