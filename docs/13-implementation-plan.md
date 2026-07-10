# Implementation Plan

This plan turns the roadmap (`docs/11-roadmap.md`) into concrete work packages that multiple agents can execute in parallel. Agent roles are defined in `docs/08-agents.md`. The decision hierarchy in `AGENTS.md` applies to every work package.

## How to use this plan

- Each work package (WP) has an ID, an owning agent role, dependencies, deliverables, and acceptance criteria.
- A WP is claimable when all its dependencies are done.
- WPs in the same milestone with no dependency between them can run in parallel.
- Every WP follows the definition of done in `AGENTS.md`: docs updated with the change, permissions declared, errors handled, audit output where relevant.
- If a WP requires a decision not covered by the docs, the owning agent writes the decision into the relevant doc first (or raises it), then implements. Do not implement around an open question silently.

## Coordination rules for multiple agents

1. **One WP, one agent.** Do not split a WP across agents; split the WP instead.
2. **Interfaces before implementations.** When a WP produces something another WP consumes (schemas, protocols, table definitions), the interface lands first as a doc or a Swift protocol, and the consumer codes against it.
3. **Docs are the contract.** If two agents disagree, the spec wins; if the spec is silent, extend the spec first.
4. **No cross-milestone shortcuts.** Do not pull relay/cloud/registry work forward to unblock local work; stub locally instead.
5. **Branch per WP**, named `wp/<id>-<slug>`, merged to `main` only when acceptance criteria pass.

## Current documentation checkup

The full documentation audit is in `docs/14-documentation-checkup.md`.

Summary:

- product direction is coherent;
- architecture direction is coherent;
- implementation should not start on plugin/runtime internals until Milestone 0 closes the contract gaps;
- Milestone 1 skeleton and mocked UI can run in parallel with Milestone 0;
- the biggest risks are data model ambiguity, plugin schema ambiguity, mapping-language scope, event deduplication semantics, OAuth, plugin signing, iOS data posture, and missing test strategy.
- plugin distribution is planned for Cloudflare: Pages for the site, R2 for packages, Workers for the registry API.
- product terminology is now Plugin for available packages and App for configured user instances created from plugins.

Use the checkup as the rationale for Milestone 0. Use this file as the execution plan.

For a no-questions implementation run, use `docs/20-handoff-checklist.md`. It defines the working target, default decisions, first-pass checklist, validation expectations, and stop conditions.

## Milestone 0 — Spec hardening (docs only, no code)

The existing docs define the product well but leave implementation-blocking gaps. Close them first. All WPs in this milestone are parallel except where noted.

### WP-0.1 Database schema v0 — Architecture Agent

`docs/03-architecture.md` names tables but no columns. Write `docs/15-data-model.md` defining every table (columns, types, indexes, foreign keys) for: plugins, plugin_versions, plugin_permissions, accounts, account_resources, resources, events, status_items, metrics, metric_points, triggers, jobs, rules, action_runs, notifications, audit_entries, sync_state. Include the Keychain-reference pattern for credentials and a migration versioning approach.

Acceptance: every object in `SPEC.md` maps to tables; the field lists in `docs/05-events-automation.md` (job, event, notification, audit fields) are all covered; no secret column exists anywhere.

### WP-0.2 Plugin package JSON Schemas — Plugin Agent

`docs/04-plugin-system.md` shows examples but no canonical schemas. Produce formal JSON Schema files under `schemas/plugin/v1/` for: manifest, auth, setup.schema, requests, mappings, triggers, events, actions, views, rules.presets. Resolve the current ambiguity where `manifest.json` `capabilities.sources` duplicates `events.json` declarations — pick one source of truth and update `docs/04-plugin-system.md`.

Acceptance: every example in `docs/04-plugin-system.md` validates against the schemas (fix the examples or the schemas until they agree); schemas are versioned; unknown-field policy is stated.

### WP-0.3 Mapping and expression language spec — Architecture Agent

The declarative mapping engine is the heart of the plugin system and is currently only sketched (`"when": "$.attributes.appStoreState == 'REJECTED'"`). Write `docs/16-mapping-language.md` covering: selector syntax (JSONPath subset — define exactly which subset), comparison operators, template string syntax (`{{...}}` — available variables and escaping), severity mapping, conditional event emission, pagination definitions, and explicit non-goals (no loops, no function calls, no arbitrary code). Depends on WP-0.2 landing its draft shape (can run concurrently with coordination).

Acceptance: every mapping example in docs/04 and docs/06 can be expressed in the language; the grammar is small enough to implement without a scripting engine.

### WP-0.4 Event semantics: state change, dedup, StatusItem lifecycle — Product Agent + Architecture Agent

Three underspecified areas, one doc (`docs/17-event-semantics.md`):

1. **State-change detection.** Polling every 15 minutes must not re-emit `app.review.rejected` each poll. Define how the mapping engine compares against prior resource state (state snapshot per resource, transition = event) versus pure fingerprint dedup, and when each applies.
2. **Fingerprint spec.** Make `provider + event_type + resource_id + relevant_state + date_bucket` precise: what is `relevant_state` per event, what bucket sizes exist, what happens on fingerprint collision.
3. **StatusItem lifecycle.** StatusItem is the least-specified core object. Define its fields, how it derives from events/current state, how it resolves (auto-resolve on `website.recovered`? manual dismiss? snooze?), and its relationship to the attention inbox idea in `docs/12-ideas-backlog.md`. Promote the inbox from ideas to spec if it is in fact the StatusItem UI, which it appears to be.

Acceptance: the App Store rejection and website down/recovered flows can be traced end-to-end on paper with no ambiguity about how many events and status items exist after N polls.

### WP-0.5 Auth flows decision: OAuth on native — Integration Agent + Security Agent

Status: implemented for the native v1 path. OAuth plugins declare provider metadata,
public app/client IDs, authorization/token endpoints, redirect URI, and scopes.
Status owns PKCE authorization URL creation, `status://oauth/...` callback handling,
state validation, authorization-code exchange, Keychain-backed token-set storage,
expired-token refresh, and request header injection. Plugins never ship client
secrets and never receive token material directly.

`auth.json` lists `oauth2`, and YouTube/Google integrations are roadmapped, but a declarative plugin cannot ship an OAuth client secret. Write the decision into `docs/07-security-privacy.md` (new section) and `docs/04-plugin-system.md`: who owns OAuth client IDs (the Status app itself per provider? user-supplied client?), PKCE flow, redirect URI scheme, token refresh responsibility, and which auth types are actually v1 (api-key/jwt-api-key/bearer may be enough for MVP — ASC, GitHub PAT, Jira token all work without OAuth).

Acceptance: each roadmapped integration through Phase 7 has a named, feasible auth path; OAuth plugin packages can be installed and connected through the native PKCE/callback/token-storage flow without plugin-owned executable code.

### WP-0.6 Plugin signing and registry security spec — Security Agent

Status: implemented for the current development registry path. `docs/07-security-privacy.md` defines Ed25519 package signatures over raw ZIP bytes, SHA-256 package hashes, app-pinned signing keys, registry signature metadata, revocation targets, and the unsigned-plugin Developer Mode boundary. The Swift verifier enforces hash, signature, trusted key, and revocation checks before install. Production distribution still needs release key custody and rotation to replace the repository development key.

Acceptance: an agent could implement package verification from the doc alone; threat model section updated.

### WP-0.7 iOS companion data decision — Product Agent

The docs are currently contradictory: "iOS connects separately" (local-first, per-device secrets) yet MVP acceptance requires "iOS app can read the same data model in companion form" with no sync mechanism specified. Decide and document in `SPEC.md`: v1 iOS = independent account setup per device (duplicate connect flows), or read-only iCloud sync of non-secret data, or iOS deferred past MVP. Update `docs/02-requirements.md` MVP acceptance to match.

Acceptance: no doc implies data sharing between devices that no specced mechanism provides.

### WP-0.8 Testing strategy — QA Agent

No testing doc exists despite a QA agent role. Write `docs/18-testing.md`: unit test expectations per package, mapping-engine golden tests (fixture payload → expected resources/events), plugin schema validation tests, mock provider fixtures (recorded API responses for ASC/GitHub/Jira), rules-engine scenario tests, and what CI runs. Include the plugin compatibility test suite shape (currently a "could have").

Acceptance: every Milestone 1–3 WP below has a named test approach it can follow.

### WP-0.9 Glossary and doc consistency fixes — Product Agent

Add a glossary (in `SPEC.md` or `docs/00-glossary.md`) for: Event vs StatusItem vs Notification vs inbox item vs Metric vs ActionLink. Fix small inconsistencies: README's MVP names GitHub while SPEC says "GitHub or Jira" (pick one phrasing); `docs/05` action lists include `slack.sendMessage`/`calendar.createEvent` which appear in no integration plan (mark as illustrative or remove); clarify what "generic webhook local model" (roadmap Phase 4) means before the relay exists — local HTTP listener, polling a file, or deferred to Phase 10.

Acceptance: grep for each fixed term shows consistent usage across all docs.

## Milestone 1 — Native skeleton (roadmap Phase 1)

### WP-1.1 Swift workspace and package structure — Architecture Agent

Blocking WP for all code. Create the workspace: `StatusCore` and `StatusUI` as local Swift packages, `StatusMac` and `StatusiOS` app targets, both shells compiling and importing the shared packages. Establish lint/format config and CI build.

Depends: none (can start alongside Milestone 0).
Acceptance: `xcodebuild` succeeds for both platforms; a shared type from StatusCore renders in both shells.

### WP-1.2 Persistence layer — macOS Agent or Architecture Agent

GRDB (or chosen wrapper) setup in StatusCore, schema v0 from WP-0.1, migration runner, typed record types for all tables.

Depends: WP-0.1, WP-1.1.
Acceptance: round-trip tests for every record type; migration from empty DB passes.

### WP-1.3 Keychain wrapper — Security Agent

Credential storage API in StatusCore: store/read/delete by credential reference, never exposing raw secrets to plugin-facing code paths.

Depends: WP-1.1.
Acceptance: unit tests with a test keychain; API takes/returns references matching the WP-0.1 pattern.

### WP-1.4 Mocked dashboard UI — Design Agent + macOS Agent

StatusUI view primitives fed by mocked normalized data: overview cards, alert list, resource list, resource detail, status pills, severity colors per `docs/10-domains-brand.md`. macOS shell with sidebar. This validates the app-owned view system before plugins exist.

Depends: WP-1.1 (not on WP-1.2 — use in-memory mock data).
Acceptance: dashboard answers the five questions in `docs/02-requirements.md` from mock data; renders on macOS.

### WP-1.5 iOS shell — iOS Agent

Tab navigation (Overview, Alerts, Apps, Settings), rendering the same StatusUI primitives compactly with mock data.

Depends: WP-1.1, WP-1.4 (shares primitives).
Acceptance: same mock model renders natively on iOS; no macOS-only API leaks into StatusUI.

## Milestone 2 — Event engine (roadmap Phase 2)

All WPs depend on WP-1.2. WP-2.1/2.2 are sequential; 2.3–2.6 can proceed in parallel against agreed protocols.

### WP-2.1 Trigger registry and scheduler — Architecture Agent

Trigger model (cron, manual, push-stub, event, app-lifecycle), interval/cron scheduling, backoff after failures, per-plugin and global limits per `docs/03-architecture.md`.

Acceptance: a registered cron trigger enqueues jobs on schedule; backoff observable after simulated failures.

### WP-2.2 Job queue — macOS Agent

Job lifecycle (queued/running/success/failed/cancelled/skipped), persistence, retry policy, timeout enforcement; failures produce structured results per `docs/03-architecture.md` error handling.

Depends: WP-2.1.
Acceptance: roadmap Phase 2 criteria — mock trigger creates job, failures stored cleanly.

### WP-2.3 Event bus, dedup, and StatusItem derivation — Architecture Agent

Event emission, fingerprint dedup, and StatusItem lifecycle exactly per WP-0.4's spec.

Depends: WP-0.4, WP-2.2.
Acceptance: repeated identical polls create one event and one status item; recovery events resolve status items per spec.

### WP-2.4 Metric store — Plugin Agent or Architecture Agent

Metric and metric_point storage, retention, and the baseline/delta computation needed for "views down 18% vs previous 28 days" style events (core-side, since mappings are declarative comparisons only).

Acceptance: golden tests: given point series, delta events fire at the specced thresholds.

### WP-2.5 Audit log model — Security Agent

AuditEntry writing wired into the job and (future) action paths; every job result creates its audit trail.

Acceptance: end-to-end mock flow produces readable audit entries with all fields from `docs/05-events-automation.md`.

## Milestone 3 — Declarative plugin engine (roadmap Phase 3)

### WP-3.1 Manifest parser and validator — Plugin Agent

Parse and validate all package files against the WP-0.2 schemas; permission and domain extraction; compatibility checks.

Depends: WP-0.2, WP-1.2.
Acceptance: sample valid/invalid fixture packages pass/fail correctly with useful errors.

### WP-3.2 Request engine — Architecture Agent

Declarative HTTP execution: auth injection from Keychain references, declared-domain enforcement (fail closed), pagination, timeouts, rate limiting.

Depends: WP-0.5, WP-1.3, WP-3.1.
Acceptance: request to an undeclared domain is rejected and audited; pagination fixture walks all pages.

### WP-3.3 Mapping engine — Architecture Agent or Plugin Agent

Implement the WP-0.3 language: payload → resources, events, metrics, with state-change detection per WP-0.4.

Depends: WP-0.3, WP-0.4, WP-2.3.
Acceptance: golden-test suite from WP-0.8 passes; docs/04 examples execute.

### WP-3.4 Setup form renderer and permission screens — Design Agent + macOS Agent

Render setup.schema.json into native forms; secrets go to Keychain; permission review screens at install and account setup.

Depends: WP-3.1, WP-1.3, WP-1.4.
Acceptance: sample plugin's setup schema renders, stores, and can reconnect after credential failure.

### WP-3.5 View descriptor renderer — Design Agent

Status: Implemented for the v1 native settings surface.

views.json descriptors → StatusUI primitives with plugin-specified fields.
Plugin packages now decode `views.json`, bundled packages include basic
descriptors, the package builder validates view type/resource references, and
app settings render descriptor-driven native lists, detail panels,
metric-style grids, timelines, and alert lists from persisted resources.
App rows, sidebars, and the collapsed macOS app strip use plugin-declared SF
Symbol icons plus `#RRGGBB` accent colors from manifest metadata. The Plugins
page remains a catalog for bundled/installed/registry plugins; creating or
editing a configured App opens separately, with macOS using a dedicated app
settings window.

Depends: WP-3.1, WP-1.4.
Acceptance: sample plugin's overview/list/detail views render natively on macOS and iOS.

### WP-3.6 Developer mode and sample plugin — Plugin Agent

Status: Implemented in core/tooling/UI for the native development flow. `LocalPluginInstaller` can install
a local folder as `local-dev` with explicit unsigned warnings, the macOS
plugin catalog exposes an **Install Local** developer-mode folder picker
with structured validation diagnostics for manifest/package failures,
the macOS app settings surface exposes a non-persisting **Preview
Fixture** JSON mapping preview, the local plugin validator prints package
checksums without publishing, the native app settings can run a
non-persisting live request test against a saved app/account, and
`plugins/examples/mock-operations` exercises every package file plus request
fixtures through native mapping tests.

Remaining: no WP-3.6 native developer-mode blockers are known.

Local plugin folder install with unsigned warnings, schema validation UI, test-request runner, mapped-output preview; a `plugins/examples/mock-operations` sample plugin exercising every package file.

Depends: WP-3.1–3.5.
Acceptance: roadmap Phase 3 acceptance criteria all pass using the sample plugin.

### WP-3.7 Plugin/App terminology migration — Product Agent + Design Agent

Status: Implemented for the current native shell and docs contract. The
product/spec language defines **Plugins** as bundled/local/registry packages
and **Apps** as configured user instances created from a plugin. The native
dashboard, sidebar, collapsed macOS app strip, and detail pages show configured
apps/accounts. The native **Plugins** tab is the plugin catalog; app setup and
settings open separately, with macOS using a dedicated app settings window.
Swift persistence still uses `accounts` for configured apps in v1 to avoid an
unnecessary schema migration.

Update user-facing app language without renaming persistence tables yet: Plugins are available packages; Apps are configured user instances created from plugins. Rename navigation, empty states, settings titles, install/setup copy, and documentation. Keep Swift model/database names stable unless a separate schema migration is explicitly planned.

Depends: WP-3.1–3.5.
Acceptance: the UI no longer presents configured instances as "integrations"; the plugin catalog and app settings are distinct; one plugin can visibly create multiple apps with separate display names.

### WP-3.8 App dashboard tiles and detail pages — Design Agent + macOS Agent

Status: Implemented for v1 app-owned tiles and detail pages. The macOS sidebar and collapsed top app strip now list configured apps/accounts separately, and selecting one opens a read-only app detail page rendered from plugin view descriptors with resources filtered to that configured app. Dashboard app entries render as configurable tiles with plugin colors/icons, app state, severity, last sync state, a typed primary field, compact secondary fields, and resource provenance; selecting a dashboard app tile opens the same app detail page on macOS and iOS. App settings expose dashboard tile field toggles from plugin-declared `dashboardTile` defaults, plugin view fields, and collected resource fields, storing selections per configured app. New apps seed their first tile fields from `views.json` `dashboardTile.primaryFields` and `secondaryFields`; existing user choices are preserved across setup edits. Settings remain separate. Remaining future work: richer plugin-declared layout variants beyond the current app-owned typed tile layout.

Extend view descriptors and StatusUI so every configured app can render a dashboard tile and an app detail page. The plugin declares supported tile/detail fields; the user can choose the tile content for each configured app. Clicking a dashboard tile, sidebar item, or collapsed app-strip icon opens the configured app detail page.

Depends: WP-3.5, WP-3.7.
Acceptance: GitHub can show recent workflow runs/commits/review requests in its app detail page; App Store Connect can show review/build state; every configured app has a tile even when the plugin exposes only minimal data.

### WP-3.8a Packaged plugin brand icons — Design Agent + Plugin Agent

Status: Implemented for v1 packaged SVG assets. The package builders include `icon.svg` in deterministic plugin archives, the validator requires static SVG assets for official GitHub and App Store Connect packages, the package decoder exposes the asset separately from the manifest SF Symbol fallback, and the shared `IntegrationIcon` renderer prefers packaged assets across the catalog, sidebar, collapsed app strip, dashboard tiles, and settings. Local-dev and third-party packages may still omit `icon.svg` and rely on the fallback symbol/color.

Add native support for packaged `icon.svg` assets while keeping the manifest `icon` SF Symbol as fallback. Update bundled GitHub and App Store Connect plugins with legally usable, recognizable icons, validate icon presence for official plugins, and render the packaged icon in the plugin catalog, app sidebar, collapsed app strip, app settings, dashboard tiles, and notification surfaces.

Depends: WP-3.7.
Acceptance: GitHub and App Store Connect no longer rely on generic SF Symbol fallbacks; missing/invalid SVG assets fail official plugin validation but local-dev plugins may still use fallback symbols.

### WP-3.9 App-scoped rules and notifications — Architecture Agent + Design Agent

Status: Implemented for the v1 local automation surface. The SQLite schema now stores rule `scope`, rule `account_id`, notification preference `account_id`, app defaults, plugin defaults, and account-specific event overrides. Runtime notification resolution prefers app event override, app default, plugin event override, plugin default, then package/rule default. Stored rule evaluation resolves the event's configured app/account and only loads app-scoped rules for that matching account, with plugin-scoped rules still available as broad defaults. macOS and iOS settings group notification controls by configured app/account when apps exist. Plugin-suggested rules now appear in each configured app's settings and enabling one creates an app-scoped copy for that account. Preset rows show required write permission state and audit preview text; review-required presets ask for explicit confirmation before enabling. Per-app custom rules include provider-backed request previews for custom provider actions and require a current preview before saving provider-backed write actions. The global rules screen now filters to explicit `cross_app` automations and can create, edit, enable/disable, and delete safe cross-app rules. It also loads installed plugin action declarations into the cross-app rule editor, renders provider-declared input fields, and can save reviewed provider-backed actions that target a different plugin than the source event. Runtime action effects now preserve both the source event provider and the target action provider, so flows such as GitHub workflow failure -> Jira issue execute through the declaring plugin with the target plugin's `write-actions` grant.

Remaining future work: optionally add provider request previews directly to suggested preset rows and richer rule-builder affordances for selecting source/target apps by display name instead of plugin IDs.

Move ordinary rules and notification preferences into configured app settings. Keep a global automation surface only for explicit cross-app rules that connect a source app event to a target app action. Plugin presets remain disabled and must be enabled per configured app.

Depends: WP-2.3, WP-3.7.
Acceptance: app settings show event-level notification controls and plugin-suggested rules for that app; the global rules screen shows only cross-app automations; enabling a preset records required permissions and audit preview data.

## Milestone 4 — Built-in plugins (roadmap Phase 4)

Fully parallel once Milestone 3 is done; each is a self-contained package under `plugins/bundled/`, each meeting the integration acceptance criteria in `docs/06-integrations.md`.

- **WP-4.1 Website uptime** — Plugin Agent. Down/recovered/slow events, response-time metric.
- **WP-4.2 Manual status** — Plugin Agent.
- **WP-4.3 RSS/feed** — Plugin Agent.
- **WP-4.4 Generic webhook (local model per WP-0.9 decision)** — Plugin Agent + Security Agent.
- **WP-4.6 GitLab read plugin** — Plugin Agent. Status: implemented as a bundled official package with project setup, `PRIVATE-TOKEN` api-key auth, project details, failed pipeline events, merge request/issue opened events, native views, disabled notification presets, bundled artifacts, and registry metadata.
- **WP-4.7 Jira read/action plugin** — Plugin Agent. Status: implemented as a bundled official package with Atlassian site/project setup, basic-auth API-token auth, project issue reads, native issue views, dashboard-only issue events, disabled app-scoped presets, and controlled `jira.createIssue` action metadata for reviewed rule actions.

### WP-4.5 Official plugin documentation template — Product Agent + Plugin Agent

Status: Implemented for the v1 source-published documentation path. Every
bundled and example plugin ships a `README.md` using the official template,
the website generator renders those source READMEs into plugin detail pages,
publisher pages link back to package authorship metadata, and the docs check
fails if a plugin README omits required operational sections or fails to name
declared permissions, domains, event types, or action IDs. This gives plugin
agents a concrete source contract without adding public upload or plugin-owned
UI.

Create the source documentation template every official plugin must ship: purpose, boundaries, setup prerequisites, credential steps, permissions/domains, resources, events, metrics, actions, dashboard tile options, app detail views, app-scoped rules/notifications, troubleshooting, and fixtures. Wire the website/docs generator to render plugin docs from plugin source metadata without hand-copying.

Depends: WP-3.7.
Acceptance: App Store Connect, GitHub, Website Uptime, and Mock Operations each have renderable plugin documentation pages.

## Milestone 5 — App Store Connect plugin (roadmap Phase 5)

### WP-5.1 ASC API research and fixtures — Integration Agent

Recorded fixture responses, JWT auth details, rate limits, review-state field mapping table.

Depends: none after Milestone 0 (research can start early).

### WP-5.2 ASC plugin package — Plugin Agent

Full package with JWT api-key auth, app/version/build resources, review-state events, direct links, error handling.

Depends: WP-5.1, Milestone 3.
Acceptance: roadmap Phase 5 criteria against a real Apple Developer account.

### WP-5.3 ASC setup documentation — Product Agent + Integration Agent

Write and validate the App Store Connect plugin setup guide: issuer ID, API key creation, key ID, `.p8` private key, app ID, API access, least-privilege setup, expected events, dashboard tile options, and explicit non-goals.

Depends: WP-5.1, WP-4.5.
Acceptance: a new user can configure the ASC app from the documentation alone, and the website page is generated from the plugin source docs.

## Milestone 6 — Notifications and rules (roadmap Phase 6)

- **WP-6.1 Notification engine** — macOS Agent. Modes (immediate/digest/dashboard-only/silent/disabled), app-level defaults, per-event preferences. Depends: WP-2.3 and WP-3.9.
- **WP-6.2 Rules engine** — Architecture Agent. Trigger matching, v1 condition operators, action queueing, enable/disable, app-scoped defaults, and explicit cross-app automation bindings. Depends: WP-2.3 and WP-3.9.
- **WP-6.3 Built-in actions and action runner** — macOS Agent. notification.show, status.inbox.add, status.open_url, webhook.post, audit.note; safety levels enforced. Depends: WP-6.2, WP-2.5.
- **WP-6.4 Rule builder and audit log UI** — Design Agent. Compact native builder per `docs/05-events-automation.md`; audit log view. Depends: WP-6.2.
- **WP-6.5 Rule presets loading** — Plugin Agent. Depends: WP-6.2, WP-3.1.

## Milestone 7 — Cross-plugin actions (roadmap Phase 7)

- **WP-7.1 GitHub plugin (read)** — Integration Agent + Plugin Agent.
- **WP-7.2 GitHub create-issue action** — Plugin Agent + Security Agent. Explicit write-permission request flow, audit with result link.
- **WP-7.3 Jira plugin (read) and create-issue action** — Integration Agent + Plugin Agent.
- **WP-7.4 Cross-plugin rule presets** — Plugin Agent. Failed workflow → issue; app rejected → issue.

Acceptance for the milestone: roadmap Phase 7 criteria — an event from one plugin creates an audited action in another, with write permission requested explicitly.

## Milestone 8 — Cloudflare plugin registry and website (roadmap Phase 8)

Use `docs/19-cloudflare-platform.md` as the hosting contract. This milestone can be prepared before Milestone 7, but production rollout depends on the plugin package/signing work being stable.

- **WP-8.1 Cloudflare platform scaffold** — Architecture Agent. Create `web/`, `workers/registry/`, and deployment configuration for Cloudflare Pages and Workers. Define environment names for local/preview/production. Acceptance: preview deploy can serve a static site and a health endpoint from the registry Worker.
- **WP-8.2 Marketing and developer site** — Design Agent. Build the static marketing website, plugin directory shell, developer docs shell, privacy/security pages, and changelog. Acceptance: Pages deploy renders the site and plugin directory using static fixture metadata.
- **WP-8.3 R2 plugin package storage** — Plugin Agent + Security Agent. Define R2 bucket layout, immutable package naming, upload script, checksum/signature sidecars, and registry snapshot output. Acceptance: a signed sample plugin ZIP can be uploaded and fetched from the expected URL without overwriting prior versions.
- **WP-8.4 Registry Worker API** — Architecture Agent. Implement `GET /v1/plugins`, `GET /v1/plugins/{pluginId}`, `GET /v1/plugins/{pluginId}/versions`, `GET /v1/plugins/{pluginId}/versions/{version}`, `GET /v1/registry`, and `GET /v1/revocations`. Acceptance: API serves compatible plugin metadata from fixtures/R2 snapshot and never marks an unverified package as trusted.
- **WP-8.5 Native registry client and installer UI** — macOS Agent + Plugin Agent. Connect the app plugin store to the registry Worker, download packages from R2-backed URLs, verify locally, check revocations, then install. Acceptance: app can browse, download, verify, install, update, and remove a Cloudflare-hosted sample plugin.
- **WP-8.6 Registry security review** — Security Agent. Review CORS/cache headers, package immutability, revocation behavior, key handling, and local verification. Acceptance: a bad hash, bad signature, revoked package, and incompatible package are all rejected locally by the app.
- **WP-8.7 Open-source plugin governance** — Product Agent + Security Agent. Decide and document the GitHub organization/repository structure, official plugin license, contribution rules, trust levels (`official`, `verified-third-party`, `local-dev`), review checklist, and release flow from reviewed source to signed R2 package. Acceptance: third-party plugins have a review-based path without direct public upload to the registry.
- **WP-8.8 Plugin submission CI** — QA Agent + Plugin Agent. Status: implemented for the v1 review-based path. The `Plugin validation` CI job runs on plugin/schema/template changes, validates bundled and example packages, validates the standalone starter template, revalidates only changed plugin directories, builds deterministic package bytes, prints package SHA-256 values, and writes a reviewer summary with trust level, permission/domain diffs, events, resources, triggers, views, actions, write actions, and changed fixture files. A sample third-party-style plugin change can now be validated without publishing it. Remaining future work: richer fixture-output diffing for provider-specific golden files once third-party plugin PR volume justifies it.

## Later milestones

Phases 9–11 (iOS companion completion, relay, cloud runner) stay as roadmap phases; break them into WPs only when Milestone 7 is done, informed by what shipped. Relay should use a separate Cloudflare Worker from the registry API. Do not design cloud runner components beyond the boundaries already in `docs/03-architecture.md`.

## Critical path

```txt
WP-0.1 → WP-1.2 → WP-2.x → WP-3.3 → WP-3.6 → WP-5.2 → WP-6.x → WP-7.x
WP-0.2 → WP-3.1 ↗
WP-0.3/0.4 → WP-3.3
```

Milestone 0 docs and WP-1.1/1.4 UI work parallelize fully; the mapping-engine chain (0.3 → 0.4 → 3.3) is the schedule risk and should be staffed first.
