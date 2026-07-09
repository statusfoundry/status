# Handoff Checklist

This checklist is the operational runbook for keeping Status moving without stopping for product questions.

The repository is no longer documentation-only. It now contains the Swift package, macOS app, iOS app, Vue website, plugin packages, Cloudflare registry Worker, schemas, tests, and CI/deploy workflows. Keep this checklist current when the working baseline changes.

Use this together with:

- `AGENTS.md`;
- `DOCTRINE.md`;
- `SPEC.md`;
- `docs/13-implementation-plan.md`;
- `docs/14-documentation-checkup.md`;
- `docs/19-cloudflare-platform.md`.

## Working target

The immediate target is not the complete product. The immediate target is a working foundation that can compile, run, and prove the architecture.

Tomorrow's "working project" means:

```txt
1. Repository has real project structure. DONE
2. macOS app target builds. DONE
3. iOS app target builds. DONE
4. Shared core package exists. DONE
5. Shared UI package exists. DONE
6. App renders native persisted dashboard data, with mock dashboard reserved for previews/tests. DONE
7. Documentation gaps are either closed or tracked in concrete files. DONE
8. Validation commands are documented in AGENTS.md. DONE
9. Changes are committed and pushed to origin/main. DONE PER SLICE
```

Continue with product hardening, launch polish, and deployment readiness. Do not add arbitrary plugin code, provider-owned UI, destructive actions, or public self-service plugin upload.

## Non-stop defaults

Use these decisions when implementation needs a default. Do not stop to ask unless the repository is impossible to build.

### Product scope

- Build native Apple-platform app first.
- macOS is primary.
- iOS is companion.
- Local-first remains mandatory.
- No cloud dependency for core local operation.
- No arbitrary plugin code.
- No plugin-owned UI.
- No destructive actions.
- No direct public third-party plugin upload in v1.

### First working app

- Build against persisted local data; keep `MockDashboard` for previews and tests.
- Include overview, needs-attention list, integration list, recent events, and audit preview.
- Render plugin-declared `views.json` descriptors with app-owned native views in integration settings.
- Use native SwiftUI controls.
- Keep the UI calm, compact, and practical.

### Package shape

Use this structure unless the platform tooling requires a small adjustment:

```txt
Package.swift or workspace/project files
Sources/
  StatusCore/
  StatusUI/
Apps/
  StatusMac/
  StatusiOS/
schemas/
  plugin/v1/
plugins/
  bundled/
  examples/
web/
workers/
  registry/
docs/
```

If Xcode project generation is easier, use XcodeGen and document the command. If a plain Xcode workspace is faster and stable, use that and document the build commands.

### Storage

- Use the local SQLite wrapper in `StatusCore`; do not add an ORM unless it removes real complexity.
- Secrets are Keychain references only.
- Persistence is implemented. New behavior must include migrations, tests, and docs.

### Plugin contracts

- Formal schemas come before real plugin runtime.
- Use `schemas/plugin/v1/`.
- Unknown plugin fields should fail validation by default unless explicitly allowed.
- Package downloads will be Cloudflare-hosted later, but local sample plugins are enough for the first working app.

### Cloudflare

- Cloudflare Pages hosts the marketing/developer site.
- Cloudflare R2 stores immutable signed plugin ZIPs.
- Cloudflare Workers serve the registry API.
- Current Pages domain: `status.hakobs.com`.
- Current registry Worker domain: `status-registry.hakobs.com`.
- Current Cloudflare account: `me@sil.mt` / `8cef251b5fdcf6c6f63db98b7aa49f9a`.
- Registry and relay are separate Workers.
- Do not build relay before registry.

### Third-party plugins

- Official plugins are open source by default.
- Third-party plugins go through pull request review.
- Public upload is later and only an intake path, not automatic publishing.
- Status signs packages that appear in the hosted registry.

### Auth

- Treat OAuth as deferred until the auth decision doc is written.
- Use feasible MVP auth paths:
  - App Store Connect: JWT API key.
  - GitHub: fine-grained token or PAT for early local testing.
  - Jira: API token.
  - Uptime/RSS/manual: no account auth.

### Validation

- Add build/test commands to `AGENTS.md` as soon as they exist.
- Prefer commands that can run locally and in CI.
- If a command fails because tooling is missing, document the missing prerequisite.
- CI runs `npm ci` and `npm run check`.
- Manual Cloudflare deploy workflow requires `CLOUDFLARE_API_TOKEN` in GitHub repository secrets.

## Current completed baseline

- [x] Swift package exists with `StatusCore` and `StatusUI`.
- [x] macOS app target builds and opens the shared dashboard/integration/rules/audit/settings surfaces.
- [x] iOS app target builds and opens the shared dashboard/integration/rules/audit/settings surfaces.
- [x] Bundled official plugins install locally on first database bootstrap.
- [x] Dashboard reads persisted items, events, metrics, accounts, installed-plugin setup states, and audit entries.
- [x] Plugin packages are declarative ZIPs with manifests, auth/setup/requests/mappings/triggers/events/actions/rule presets.
- [x] Plugin package validation and example plugin validation run through `npm run plugins:check`.
- [x] Registry Worker serves plugin metadata, details, versions, revocations, package artifacts, and compatibility filters.
- [x] Cloudflare Pages website has home, download/beta, plugins, plugin details, developers, docs, privacy/security, and changelog routes.
- [x] GitHub Actions CI covers Node checks, Swift tests, Xcode project generation, and macOS/iOS builds.
- [x] Cloudflare deploy workflow is present and manual.

## First-pass checklist

Run these checks before editing:

- [x] `git status --short --branch`
- [x] `git remote -v`
- [x] `rg --files`
- [x] Read `AGENTS.md`
- [x] Read `DOCTRINE.md`
- [x] Read `SPEC.md`
- [x] Read `docs/13-implementation-plan.md`
- [x] Read `docs/20-handoff-checklist.md`

Expected state before work:

- branch is `main`;
- remote is `git@github.com:statusfoundry/status.git`;
- no uncommitted changes unless they are from the current task.

If there are uncommitted changes, inspect them and preserve them. Do not revert user work.

## Work order

### Step 1: Close minimum documentation contracts

Do this first if the target is anything beyond a pure skeleton.

- [x] Create `docs/00-glossary.md`.
- [x] Define Event vs StatusItem vs Notification vs ActionRun vs AuditEntry.
- [x] Decide MVP integration wording: official App Store Connect, GitHub, and Website Uptime plugins first.
- [x] Mark Slack/calendar actions as future illustrative examples.
- [x] Clarify generic webhook local behavior before relay.
- [x] Link glossary from README.

Acceptance:

- terms are clear enough for code models;
- no contradictory MVP wording remains.

### Step 2: Create project skeleton

- [x] Create shared core module.
- [x] Create shared UI module.
- [x] Create macOS app target.
- [x] Create iOS app target.
- [x] Add placeholder app icon/assets only if required to build.
- [x] Add build command documentation to `AGENTS.md`.

Acceptance:

- macOS target builds;
- iOS target builds or has a documented blocker;
- both import shared code.

### Step 3: Define normalized mock models

Create simple Swift models in `StatusCore`:

- [x] `Severity`
- [x] `Account`
- [x] `Resource`
- [x] `Event`
- [x] `StatusItem`
- [x] `Metric`
- [x] `ActionLink`
- [x] `NotificationMode`
- [x] `AuditEntry`

Acceptance:

- models match `SPEC.md` names;
- mocked data can answer dashboard questions;
- no provider-specific types leak into shared UI.

### Step 4: Build native UI

Create StatusUI primitives:

- [x] overview card;
- [x] status/attention list;
- [x] resource list;
- [x] recent events timeline/list;
- [x] metric tile;
- [x] audit row;
- [x] severity badge;
- [x] integration row.

macOS shell:

- [x] sidebar;
- [x] overview screen;
- [x] integrations screen;
- [x] audit screen;
- [x] settings screen.

iOS shell:

- [x] overview tab;
- [x] alerts tab;
- [x] integrations tab;
- [x] rules tab;
- [x] audit tab;
- [x] settings tab.

Acceptance:

- app opens directly into the usable dashboard, not a landing page;
- dashboard answers:
  - Are all important products okay?
  - What changed?
  - What is stuck?
  - What needs attention?
  - Where do I click?
  - Did automation run, and why?

### Step 5: Add basic tests or compile checks

- [x] Add unit test target.
- [x] Test model/persistence behavior where Codable or SQLite-backed.
- [x] Test mocked dashboard data construction.
- [x] Document all commands in `AGENTS.md`.

Acceptance:

- at minimum, build command passes;
- test command exists if test target exists.

### Step 6: Commit and push

- [x] `git status --short`
- [x] run documented validation command;
- [x] `git add` only intended files;
- [x] `git commit -m "..."`;
- [x] `git push`.

Acceptance:

- remote `origin/main` has the latest work;
- final response includes commit hash and validation result.

## Spec-hardening checklist

These can run in parallel with skeleton work, but plugin runtime work should not start until they exist.

### Data model

- [x] Create `docs/15-data-model.md`.
- [x] Define tables and fields.
- [x] Define IDs and timestamps.
- [x] Define indexes.
- [x] Define migration strategy.
- [x] Define Keychain reference pattern.
- [x] Confirm no secret columns.

### Plugin schemas

- [x] Create `schemas/plugin/v1/`.
- [x] Add schemas for manifest, auth, setup, requests, mappings, triggers, events, actions, views, rule presets.
- [x] Decide single source of truth for event declarations.
- [x] Validate examples.
- [x] Document unknown-field policy.

### Mapping language

- [x] Create `docs/16-mapping-language.md`.
- [x] Define JSONPath subset.
- [x] Define comparison operators.
- [x] Define template syntax.
- [x] Define pagination.
- [x] Define conditional event emission.
- [x] Ban loops, arbitrary functions, and scripting.

### Event semantics

- [x] Create `docs/17-event-semantics.md`.
- [x] Define state-change detection.
- [x] Define fingerprint format.
- [x] Define dedup behavior.
- [x] Define StatusItem lifecycle.
- [x] Define recovery/resolution behavior.
- [x] Define snooze/dismiss behavior.

### Auth

- [x] Update `docs/07-security-privacy.md`.
- [x] Update `docs/04-plugin-system.md`.
- [x] Decide OAuth status for v1.
- [x] Reject OAuth for v1 plugin packages; revisit PKCE only when OAuth is brought back.
- [x] Map MVP integrations to auth paths.

### Signing

- [x] Define signing algorithm.
- [x] Define key custody.
- [x] Define package signature format.
- [x] Define app-pinned public key behavior.
- [x] Define revocation list format.
- [x] Define developer-mode warning flow.

### iOS data posture

- [x] Update `SPEC.md`.
- [x] Update `docs/02-requirements.md`.
- [x] Pick v1 posture:
  - independent account setup per device;
  - read-only iCloud sync;
  - or iOS dashboard shell first with no shared live data.

Current v1 posture:

```txt
iOS companion app with the same shared local models and independent local account setup per device.
Real cross-device data sync deferred.
```

### Testing

- [x] Create `docs/18-testing.md`.
- [x] Define unit test expectations.
- [x] Define plugin schema validation tests.
- [x] Define mapping golden tests.
- [x] Define provider fixture policy.
- [x] Define rules/action/audit scenario tests.
- [x] Define CI commands.

## Implementation checks

Before any code is considered done, check:

- [ ] Does it preserve native-first?
- [ ] Does shared code stay in shared packages?
- [ ] Does it avoid provider-specific UI?
- [ ] Does it avoid arbitrary plugin code?
- [ ] Does it keep secrets out of files and SQLite?
- [ ] Does it keep write actions permissioned?
- [ ] Does it produce or preserve auditability?
- [ ] Does it update docs if behavior changed?
- [ ] Does it build locally?
- [ ] Is the final state pushed?

## Things not to do yet

Do not start these until the foundations are stable:

- [ ] real OAuth integrations;
- [ ] App Store Connect live API calls;
- [ ] GitHub write actions;
- [ ] Jira write actions;
- [ ] Cloudflare relay;
- [ ] cloud runner;
- [ ] public plugin upload portal;
- [ ] plugin marketplace payments;
- [ ] destructive automations.

## Stop conditions

Do not stop for product preference questions. Use the defaults above.

Only stop if:

- repository cannot be written;
- required toolchain is missing and cannot be installed without approval;
- GitHub push/auth fails;
- local changes conflict in a way that would overwrite user work;
- platform tooling makes the agreed structure impossible.

When blocked, document:

- exact command;
- exact failure;
- attempted fix;
- next required action.

## Final handoff format

End every implementation run with:

```txt
Summary:
- what changed

Validation:
- command: result

Git:
- branch
- commit hash
- pushed/not pushed

Next:
- next 3 concrete tasks
```
