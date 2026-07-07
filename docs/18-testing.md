# Testing

This document defines the testing strategy for Status. It exists so that every work package in `docs/13-implementation-plan.md` has a named test approach before the code is written, and so that CI can be defined once and enforced everywhere.

The strategy follows one principle:

```txt
Logic lives in StatusCore, where it can be tested without UI.
The shells stay thin, so they only need to build and launch.
Provider behavior enters tests only through recorded fixtures.
```

## Test pyramid per package

### StatusCore

StatusCore holds the pipeline: plugin loading, validation, scheduling, jobs, events, rules, actions, notifications, persistence. It must be fully testable without any UI or network.

Expected test types:

- unit tests for every model, parser, and engine component;
- scenario tests that run a whole flow through the pipeline in memory (trigger → job → event → rule → action → audit);
- golden tests for the mapping engine (see below);
- round-trip persistence tests for every record type against an in-memory or temporary database.

No StatusCore test may hit a live network endpoint. Credential tests use `InMemoryCredentialStore` for deterministic unit coverage, while the app runtime uses `KeychainCredentialStore`. A separate opt-in integration suite may exercise the real Keychain on developer machines, but CI should not depend on an unlocked user keychain.

### StatusUI

StatusUI renders normalized data and view descriptors. It should contain little logic, but what logic exists (view models, formatting, severity-to-color mapping, descriptor-to-primitive resolution) gets unit tests.

Expected test types:

- view-model unit tests: given normalized data, the view model exposes the expected rows, badges, and ordering;
- snapshot or preview-based checks where practical: render each primitive (overview card, alert list, resource list, status pill, metric tile, audit row) with fixture data and compare against a recorded snapshot;
- a compile-time check that no macOS-only or iOS-only API leaks into StatusUI (both platform builds in CI cover this).

Snapshot tests should be treated as change detectors, not design verification. When a snapshot changes deliberately, regenerate it in the same commit and explain why.

### StatusMac and StatusiOS

The shells are deliberately thin. They get:

- build tests: both targets compile on every PR;
- smoke tests: the app launches, the dashboard scene constructs with mock data, and navigation destinations resolve;
- platform-specific tests only where a shell owns real behavior (menu bar item state on macOS, local notification scheduling wiring).

If a shell test needs to exercise business logic, the logic is in the wrong package. Move it to StatusCore and test it there.

## Plugin schema validation tests

The schemas in `schemas/plugin/v1/` (WP-0.2) are contracts. They get their own test suite:

- every schema is tested against at least one valid fixture package and a set of invalid fixtures (missing required field, unknown field, wrong type, undeclared domain referenced by a request, malformed version string);
- unknown fields fail validation by default, and there is a test proving it;
- every JSON example in `docs/04-plugin-system.md` is extracted and validated against the schemas in CI. A documentation example that does not validate is a CI failure — fix the doc or the schema, never ignore the mismatch.

Fixture layout:

```txt
tests/fixtures/plugins/
  valid/
    minimal/            (smallest valid package)
    full/               (every optional file present)
  invalid/
    missing-manifest-id/
    unknown-field/
    undeclared-domain/
    bad-version/
```

Each invalid fixture directory contains a note (or a sidecar `expected-error.txt`) naming the error the validator must produce. Validators are tested for useful error messages, not just pass/fail.

This suite is what WP-3.1 (manifest parser and validator) runs against.

## Mapping-engine golden tests

The mapping engine (WP-3.3, language from `docs/16-mapping-language.md`) is the highest-risk component. It gets golden tests: a fixture payload goes in, and the expected normalized output comes out, byte-comparable as JSON.

Convention:

```txt
tests/fixtures/mappings/
  {provider}/{case}/
    input.json          (recorded, sanitized provider payload)
    mapping.json        (the mapping definition under test)
    expected.json       (resources, events, metrics the engine must emit)
    state.json          (optional prior resource state, for state-change cases)
```

Rules:

- the test runner walks every case directory; adding a case is adding a directory, not writing code;
- `expected.json` is committed and reviewed like source code;
- a mapping-engine change that alters any golden output fails CI until the fixtures are deliberately regenerated with the provided regeneration command, and the fixture diff appears in the PR for review;
- every mapping example in `docs/04-plugin-system.md` and `docs/06-integrations.md` has a corresponding golden case, so the documented language and the implemented language cannot drift apart.

Golden tests also cover the metric baseline/delta computation from WP-2.4: given a committed metric point series, the expected delta events fire at the specced thresholds.

## Provider fixture policy

Provider behavior enters tests only through recorded fixtures. There are no live API calls in CI, ever. This applies to App Store Connect, GitHub, Jira, RSS, and every future provider.

Recording:

- fixtures are recorded manually or with a small capture script against a real account during integration research (WP-5.1 style work);
- record the full response body and the relevant headers (pagination links, rate-limit headers) — the request engine's pagination and backoff tests need them;
- record error responses too: 401 expired token, 403 missing scope, 429 rate limited, 500. Failure handling is tested from fixtures like everything else.

Sanitizing, before commit:

- no real tokens, cookies, session values, or signatures anywhere in a fixture;
- no real account identifiers: replace team IDs, issuer IDs, account emails, and organization names with obvious placeholders (`ISSUER_ID_REDACTED`, `example-org`);
- resource names may stay realistic but must not identify a real customer account;
- keep the JSON structure exactly as the provider sent it — sanitize values, never shapes.

Layout:

```txt
tests/fixtures/providers/
  appstoreconnect/
    list_apps.ok.json
    list_apps.page2.json
    auth.expired.json
  github/
    workflow_runs.ok.json
    webhook.workflow_run.json
  jira/
    search_issues.ok.json
  rss/
    feed.ok.xml
```

The fixture-backed request runner serves these files in place of URLSession. A test that needs provider behavior not yet captured records a new fixture; it does not call the API from the test.

## Event-semantics scenario tests

`docs/17-event-semantics.md` (WP-0.4) defines the worked traces for state-change detection, fingerprint dedup, and StatusItem lifecycle. Every worked trace in that document becomes an executable scenario test in StatusCore, in the same order the doc tells the story:

- **N-poll rejection**: poll the same rejected app state N times; assert exactly one `app.review.rejected` event exists, one status item exists, and the fingerprint blocked the duplicates;
- **down/recovered incident**: website goes down, stays down across polls, then recovers; assert one down event, one status item that resolves on `website.recovered`, and the expected recovery event;
- fingerprint edge cases from the spec: date-bucket rollover, relevant-state change re-emitting, collision behavior.

These tests are the acceptance gate for WP-2.3. If the spec and the tests disagree, fix the spec first, then the tests, per the docs-are-the-contract rule.

## Rules, actions, and audit scenario tests

The rules engine (WP-6.2), action runner (WP-6.3), and audit log (WP-2.5) are tested as one flow, because they only make sense together:

- event in → assert which rules matched, which conditions evaluated true, which actions were queued, and which audit entries were written with all fields from `docs/05-events-automation.md`;
- every v1 condition operator gets a matching and a non-matching case;
- template expansion (`{{event.title}}` and friends) is tested against the mapping-language spec;
- a disabled rule matches nothing; an enabled rule with failing conditions queues nothing but the evaluation is still explainable.

Action safety levels are enforced in tests, not just in review:

- a `safe` action runs without extra permission;
- a `review-required` action fails to queue unless the write permission was granted, and the denial is audited;
- a `dangerous` action must be untriggerable: the test asserts that no rule configuration, preset, or direct call can queue it in v1, and that the attempt produces a clear error and an audit entry.

Every scenario test ends by asserting on the audit log. If a flow ran and the audit log cannot explain it, the test fails.

## Keychain and security tests

Two standing guarantees get automated checks:

**Secrets never leak.** A grep-style leak test runs over every committed fixture, every test database produced during the suite, and captured log output:

- scan for known secret markers (test tokens are generated with a recognizable prefix such as `TESTSECRET_` so the scan is deterministic);
- scan fixtures for common real-credential shapes (bearer tokens, PEM blocks, `AuthKey_` filenames);
- assert that no `credential` value in any database dump is anything other than a Keychain reference.

**Undeclared domains fail closed.** The request engine tests (WP-3.2) include:

- a request to a domain not in the plugin's `domains` list is rejected before any network activity, and the rejection is audited;
- redirects to undeclared domains are also rejected;
- the credential wrapper (WP-1.3) is tested with `InMemoryCredentialStore`, and plugin-facing code paths are asserted to receive references, never raw secret values. Real-Keychain integration tests are opt-in only.

## Plugin compatibility test suite

This is the "could have" from `docs/02-requirements.md`, given a concrete shape so it can be picked up when needed:

```txt
tests/compatibility/
  matrix.json           (core schema versions × plugin packages)
  run: for each (coreSchemaVersion, package) pair:
    validate package against that schema version
    assert install-allowed / install-blocked matches matrix.json
```

The matrix answers: does this plugin package validate against schema v1? Does a package with `minCoreVersion` above the current core get blocked with the right message? When `schemas/plugin/v2/` ever exists, the matrix grows a column instead of the suite growing a design. Bundled and example plugins are always in the matrix; store plugins join as they are built.

## Plugin submission CI

Aligned with WP-8.8. When a third-party plugin arrives as a pull request, CI runs, in order:

```txt
1. Schema validation      — every package file against schemas/plugin/v1/
2. Declared-domain check  — every URL in requests.json resolves to a declared domain
3. Mapping tests          — the fixtures shipped with the plugin run through the
                            mapping engine; expected outputs must match
4. Package build          — the package zips into the canonical
                            {pluginId}-{version}.statusplugin.zip shape
5. Checksum output        — SHA-256 of the built package, printed for the release flow
6. Permission diff        — for updates: a human-readable diff of permissions and
                            domains against the previously published version,
                            posted on the PR for reviewer attention
```

A submission without fixtures for its mappings is rejected by CI. Validation never publishes anything; signing and R2 upload remain a separate maintainer-triggered release flow per `docs/19-cloudflare-platform.md`.

## CI definition

On every pull request:

```txt
- build StatusMac (macOS)
- build StatusiOS (iOS)
- StatusCore unit and scenario tests
- StatusUI view-model and snapshot tests
- schema validation suite (fixtures + docs/04 examples)
- mapping golden tests
- provider-fixture-driven request engine tests
- secret leak scan
```

On plugin PRs, additionally the plugin submission CI steps above.

Nothing in CI touches a live provider API, a real Keychain item, or the production registry.

Concrete commands (xcodebuild invocations, test runner, fixture regeneration, leak scan) land in `AGENTS.md` as soon as the tooling exists, per `docs/20-handoff-checklist.md`. Until then, this document defines what the commands must do, and WP-1.1 defines the first of them.

## Test approach per work package

Every Milestone 1–3 WP maps to a named approach from this document:

```txt
WP-1.1  Workspace/packages       CI build for both platforms; shared-type smoke test
WP-1.2  Persistence layer        round-trip unit tests per record type; empty-DB migration test
WP-1.3  Keychain wrapper         unit tests against a test keychain; reference-only API assertions
WP-1.4  Mocked dashboard UI      StatusUI snapshot checks; view-model unit tests on mock data
WP-1.5  iOS shell                iOS build + smoke test; shared-primitive rendering with mock data

WP-2.1  Trigger registry         unit tests: schedule → enqueued jobs; backoff after simulated failures
WP-2.2  Job queue                scenario tests: lifecycle states, retry, timeout, structured failures
WP-2.3  Event bus/dedup/StatusItem   event-semantics scenario tests (worked traces from docs/17)
WP-2.4  Metric store             golden tests: point series in, delta events out at specced thresholds
WP-2.5  Audit log                scenario tests: every job/action produces complete audit entries

WP-3.1  Manifest parser          schema validation suite: valid/invalid fixture packages, error quality
WP-3.2  Request engine           fixture-backed tests: auth injection, fail-closed domains, pagination
WP-3.3  Mapping engine           golden test suite; docs/04 and docs/06 examples execute
WP-3.4  Setup form renderer      view-model unit tests; secret-to-Keychain assertion; snapshot checks
WP-3.5  View descriptor renderer snapshot checks per descriptor on both platforms
WP-3.6  Developer mode + sample  end-to-end scenario: sample plugin exercises every suite above
```

Later milestones reuse the same approaches: bundled plugins (Milestone 4) and App Store Connect (Milestone 5) are golden tests plus provider fixtures; notifications and rules (Milestone 6) are scenario tests with audit assertions; cross-plugin actions (Milestone 7) are scenario tests with safety-level enforcement; the registry (Milestone 8) adds the plugin submission CI.

## Guiding sentence

```txt
If a behavior matters, there is a fixture that proves it,
and CI fails when the behavior changes without the fixture changing with it.
```
