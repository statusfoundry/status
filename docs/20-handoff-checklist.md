# Handoff Checklist

This checklist is the operational runbook for turning the documentation-only repository into a working project without stopping for product questions.

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
1. Repository has real project structure.
2. macOS app target builds.
3. iOS app target builds or is scaffolded with clear build command.
4. Shared core package exists.
5. Shared UI package exists.
6. App renders a native mocked dashboard.
7. Documentation gaps are either closed or tracked in concrete files.
8. Validation commands are documented in AGENTS.md.
9. Changes are committed and pushed to origin/main.
```

If there is time after the skeleton builds, continue into schema/data-model work. Do not start real provider integrations before the contracts are documented.

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

- Build a mocked dashboard before real integrations.
- Use mocked normalized data, not provider APIs.
- Include overview, needs-attention list, integration list, recent events, and audit preview.
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

- Use SQLite through GRDB unless there is a clear local build blocker.
- Secrets are Keychain references only.
- If persistence is not implemented on day one, create the protocol boundaries and mocked/in-memory stores.

### Plugin contracts

- Formal schemas come before real plugin runtime.
- Use `schemas/plugin/v1/`.
- Unknown plugin fields should fail validation by default unless explicitly allowed.
- Package downloads will be Cloudflare-hosted later, but local sample plugins are enough for the first working app.

### Cloudflare

- Cloudflare Pages hosts the marketing/developer site.
- Cloudflare R2 stores immutable signed plugin ZIPs.
- Cloudflare Workers serve the registry API.
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

## First-pass checklist

Run these checks before editing:

- [ ] `git status --short --branch`
- [ ] `git remote -v`
- [ ] `rg --files`
- [ ] Read `AGENTS.md`
- [ ] Read `DOCTRINE.md`
- [ ] Read `SPEC.md`
- [ ] Read `docs/13-implementation-plan.md`
- [ ] Read `docs/20-handoff-checklist.md`

Expected state before work:

- branch is `main`;
- remote is `git@github.com:statusfoundry/status.git`;
- no uncommitted changes unless they are from the current task.

If there are uncommitted changes, inspect them and preserve them. Do not revert user work.

## Work order

### Step 1: Close minimum documentation contracts

Do this first if the target is anything beyond a pure skeleton.

- [ ] Create `docs/00-glossary.md`.
- [ ] Define Event vs StatusItem vs Notification vs ActionRun vs AuditEntry.
- [ ] Decide MVP integration wording: GitHub first, Jira next.
- [ ] Mark Slack/calendar actions as future illustrative examples.
- [ ] Clarify generic webhook local behavior before relay.
- [ ] Link glossary from README.

Acceptance:

- terms are clear enough for code models;
- no contradictory MVP wording remains.

### Step 2: Create project skeleton

- [ ] Create shared core module.
- [ ] Create shared UI module.
- [ ] Create macOS app target.
- [ ] Create iOS app target or documented scaffold.
- [ ] Add placeholder app icon/assets only if required to build.
- [ ] Add build command documentation to `AGENTS.md`.

Acceptance:

- macOS target builds;
- iOS target builds or has a documented blocker;
- both import shared code.

### Step 3: Define normalized mock models

Create simple Swift models in `StatusCore`:

- [ ] `Severity`
- [ ] `Account`
- [ ] `Resource`
- [ ] `Event`
- [ ] `StatusItem`
- [ ] `Metric`
- [ ] `ActionLink`
- [ ] `NotificationMode`
- [ ] `AuditEntry`

Acceptance:

- models match `SPEC.md` names;
- mocked data can answer dashboard questions;
- no provider-specific types leak into shared UI.

### Step 4: Build mocked UI

Create StatusUI primitives:

- [ ] overview card;
- [ ] status/attention list;
- [ ] resource list;
- [ ] recent events timeline/list;
- [ ] metric tile;
- [ ] audit row;
- [ ] severity badge;
- [ ] integration row.

macOS shell:

- [ ] sidebar;
- [ ] overview screen;
- [ ] integrations screen placeholder;
- [ ] audit screen placeholder;
- [ ] settings screen placeholder.

iOS shell:

- [ ] overview tab;
- [ ] alerts tab;
- [ ] integrations tab;
- [ ] settings tab.

Acceptance:

- app opens directly into the usable dashboard, not a landing page;
- mocked dashboard answers:
  - Are all important products okay?
  - What changed?
  - What is stuck?
  - What needs attention?
  - Where do I click?
  - Did automation run, and why?

### Step 5: Add basic tests or compile checks

- [ ] Add unit test target if package setup supports it.
- [ ] Test model decoding/encoding if models are Codable.
- [ ] Test mocked dashboard data construction.
- [ ] Document all commands in `AGENTS.md`.

Acceptance:

- at minimum, build command passes;
- test command exists if test target exists.

### Step 6: Commit and push

- [ ] `git status --short`
- [ ] run documented validation command;
- [ ] `git add` only intended files;
- [ ] `git commit -m "..."`;
- [ ] `git push`.

Acceptance:

- remote `origin/main` has the latest work;
- final response includes commit hash and validation result.

## Spec-hardening checklist

These can run in parallel with skeleton work, but plugin runtime work should not start until they exist.

### Data model

- [ ] Create `docs/15-data-model.md`.
- [ ] Define tables and fields.
- [ ] Define IDs and timestamps.
- [ ] Define indexes.
- [ ] Define migration strategy.
- [ ] Define Keychain reference pattern.
- [ ] Confirm no secret columns.

### Plugin schemas

- [ ] Create `schemas/plugin/v1/`.
- [ ] Add schemas for manifest, auth, setup, requests, mappings, triggers, events, actions, views, rule presets.
- [ ] Decide single source of truth for event declarations.
- [ ] Validate examples.
- [ ] Document unknown-field policy.

### Mapping language

- [ ] Create `docs/16-mapping-language.md`.
- [ ] Define JSONPath subset.
- [ ] Define comparison operators.
- [ ] Define template syntax.
- [ ] Define pagination.
- [ ] Define conditional event emission.
- [ ] Ban loops, arbitrary functions, and scripting.

### Event semantics

- [ ] Create `docs/17-event-semantics.md`.
- [ ] Define state-change detection.
- [ ] Define fingerprint format.
- [ ] Define dedup behavior.
- [ ] Define StatusItem lifecycle.
- [ ] Define recovery/resolution behavior.
- [ ] Define snooze/dismiss behavior.

### Auth

- [ ] Update `docs/07-security-privacy.md`.
- [ ] Update `docs/04-plugin-system.md`.
- [ ] Decide OAuth status for v1.
- [ ] Document PKCE if OAuth is kept.
- [ ] Map MVP integrations to auth paths.

### Signing

- [ ] Define signing algorithm.
- [ ] Define key custody.
- [ ] Define package signature format.
- [ ] Define app-pinned public key behavior.
- [ ] Define revocation list format.
- [ ] Define developer-mode warning flow.

### iOS data posture

- [ ] Update `SPEC.md`.
- [ ] Update `docs/02-requirements.md`.
- [ ] Pick v1 posture:
  - independent account setup per device;
  - read-only iCloud sync;
  - or iOS dashboard shell first with no shared live data.

Default if no decision is made:

```txt
iOS dashboard shell with mocked/shared models first.
Real cross-device data sync deferred.
```

### Testing

- [ ] Create `docs/18-testing.md`.
- [ ] Define unit test expectations.
- [ ] Define plugin schema validation tests.
- [ ] Define mapping golden tests.
- [ ] Define provider fixture policy.
- [ ] Define rules/action/audit scenario tests.
- [ ] Define CI commands.

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

