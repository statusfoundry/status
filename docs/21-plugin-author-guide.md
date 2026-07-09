# Plugin Author Guide

This guide explains how to build, validate, and test a declarative Status plugin in v1.

Plugins are data packages, not mini-apps. They declare auth, requests, mappings, events, views, triggers, actions, and suggested rules. Status owns the UI, credentials, notifications, automation decisions, and audit output.

## Start from the example template

The canonical starter package is **Mock Operations**:

```txt
plugins/examples/mock-operations/
```

It demonstrates every v1 package file:

```txt
mock-operations/
├── manifest.json
├── setup.schema.json
├── requests.json
├── mappings.json
├── triggers.json
├── events.json
├── actions.json
├── views.json
├── rules.presets.json
├── fixtures/
│   └── fetch_status.json
└── README.md
```

Copy that folder, rename it, and replace the example provider with your real HTTPS API and recorded fixtures.

### Standalone template repository

Fork the minimal template without cloning the full Status monorepo:

[status-plugin-example](https://github.com/statusfoundry/status/tree/main/status-plugin-example)

That directory is generated from `plugins/examples/mock-operations` and includes bundled schemas plus `npm run validate`. Maintainers regenerate it with `npm run plugin-example:sync` from the monorepo root.

You can also copy the example directly from the main repository:

[github.com/statusfoundry/status/tree/main/plugins/examples/mock-operations](https://github.com/statusfoundry/status/tree/main/plugins/examples/mock-operations)

## Local prerequisites

Clone Status and install Node dependencies:

```sh
git clone git@github.com:statusfoundry/status.git
cd status
npm ci
```

You do not need to build the native apps to validate a plugin package, but you need a macOS Status build to install and run a local plugin through Developer Mode.

## Validate a plugin folder

From the repository root, validate your plugin directory:

```sh
npm run plugins:validate-local -- path/to/your-plugin
```

Example:

```sh
npm run plugins:validate-local -- plugins/examples/mock-operations
```

This command:

- validates `manifest.json` and every package file against `schemas/plugin/v1/`;
- checks cross-file references such as trigger request IDs and action request bindings;
- builds the deterministic `.statusplugin.zip` bytes in memory;
- prints the package filename and SHA-256 checksum;
- keeps the package in `local-dev` trust territory (unsigned, Developer Mode only).

Fix every validation error before trying to install the plugin in the app.

## Pull request validation

When a pull request changes files under `plugins/`, `schemas/plugin/`, or `status-plugin-example/`, GitHub Actions runs the **Plugin validation** job automatically. It:

- validates every bundled and example plugin package (`npm run plugins:check`);
- validates the standalone template when relevant (`npm run plugin-example:check`);
- re-validates only the plugin directories touched in the PR (`npm run plugins:validate-pr`) and prints each package SHA-256 in the job log.

If you change a bundled plugin, also run `npm run plugins:build` and commit the generated registry artifacts. CI fails when those artifacts are out of date.

## Adapt the template

Work through the package in this order:

1. **manifest.json** — set a unique plugin ID, name, version, permissions, and declared domains.
2. **setup.schema.json** — define the native setup fields Status renders for account/app configuration.
3. **auth.json** — only if the provider needs credentials; secrets are stored in Keychain by the app.
4. **requests.json** — declare read-only HTTP requests first.
5. **fixtures/** — record sanitized provider responses used by mapping tests and fixture preview.
6. **mappings.json** — normalize provider payloads into resources, events, and metrics.
7. **events.json** — declare emitted event types, severities, and notification defaults.
8. **triggers.json** — add manual refresh first, then cron schedules if needed.
9. **views.json** — choose app-owned view descriptors for dashboard and detail surfaces.
10. **rules.presets.json** — optional suggested rules; they install disabled.
11. **actions.json** — only when a controlled write action is genuinely needed in v1.

Read `docs/04-plugin-system.md` for field-level reference and `docs/16-mapping-language.md` for mapping syntax.

## Test in the app

Local plugins install only through **Developer Mode** on macOS.

1. Build and open StatusMac.
2. Enable Developer Mode in Settings.
3. Open the plugin catalog and choose **Install Local**.
4. Select your plugin source folder.
5. Review the unsigned-plugin warning, permissions, and declared domains.
6. Configure the plugin account/app through the native setup form.
7. Run a manual trigger from app settings.
8. Use **Preview Fixture** to run mappings against a JSON fixture without writing to SQLite.

Unsigned local plugins skip signature verification only. Schema validation, domain enforcement, permission grants, and audit logging still apply.

## Required evidence before submission

A plugin pull request should include:

- a complete declarative package with no arbitrary code;
- fixtures for every mapping you expect CI to exercise;
- `npm run plugins:validate-local -- <your-plugin-folder>` output or evidence that `npm run plugins:check` passes;
- declared domains and permissions that match real requests;
- provider-specific setup notes when credentials are non-obvious;
- read-only behavior first; write actions only when explicitly justified.

See `docs/18-testing.md` for fixture layout and golden-test expectations.

## Submit for registry review

v1 has no public upload form and no self-service publishing.

Submission path:

```txt
Fork or branch in the Status repository
→ add or update your plugin source package
→ include fixtures and validation evidence
→ open a pull request
→ CI validates schemas, domains, mappings, and package shape
→ maintainer and security review
→ Status signs approved packages
→ release workflow uploads immutable artifacts to R2
→ registry metadata is updated
```

Only `official` and `verified-third-party` packages appear in the hosted registry. Status signs packages that users install from the registry.

## What not to do in v1

- do not add arbitrary native or JavaScript code;
- do not build custom plugin UI;
- do not call undeclared domains;
- do not request write permissions unless actions need them;
- do not expect OAuth-based registry plugins until OAuth is explicitly supported;
- do not publish unsigned packages to the public registry yourself.

## Related docs

- `docs/04-plugin-system.md` — package reference
- `docs/16-mapping-language.md` — mapping language
- `docs/18-testing.md` — fixtures and CI expectations
- `docs/19-cloudflare-platform.md` — registry hosting and review flow
- `CONTRIBUTING.md` — repository contribution rules