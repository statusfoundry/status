# Status

Status is a native personal operations dashboard for macOS and iOS.

It connects to the tools, accounts, products, channels, projects, and services a person already uses, then turns scattered updates into one clear stream of status, events, notifications, and automations.

Status is not meant to replace App Store Connect, YouTube Studio, Jira, GitHub, Cloudflare, Stripe, or other source tools. It tells the user what changed, what is stuck, what needs attention, and where to click next.

## Product thesis

Most independent builders and small teams do not have one operational view. They switch between dashboards, emails, review portals, issue trackers, analytics tools, app stores, hosting platforms, and social channels. Each tool knows its own status, but no tool knows the whole situation.

Status is the missing native layer above those tools.

```txt
Status watches your tools.
Plugins bring in events.
Rules decide what matters.
Actions handle the follow-up.
```

## Core idea

Status has three layers:

1. A native app shell for macOS and iOS.
2. A shared event-based core that handles plugins, triggers, jobs, events, notifications, rules, actions, and audit logs.
3. Declarative plugins that describe data sources, authentication, requests, mappings, events, actions, and which built-in views to use.

The app owns the UI. Plugins do not ship custom screens. Plugins supply configuration, data mappings, and capabilities.

## Key principles

- Native first.
- Read-only by default.
- Events over dashboards.
- Plugins are adapters, not mini-apps.
- The app owns all views and interaction patterns.
- Everything should be explainable.
- Local-first where possible.
- Cloud relay only where needed.
- Notifications should be controlled by the user, not by plugins.
- Automations should have audit logs.
- Dangerous actions should require explicit permission.

## Documentation map

Start here:

- [Doctrine](DOCTRINE.md)
- [Canonical specification](SPEC.md)
- [Agent instructions](AGENTS.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

Detailed docs:

- [Glossary](docs/00-glossary.md)
- [Product soul](docs/01-product-soul.md)
- [Requirements](docs/02-requirements.md)
- [Architecture](docs/03-architecture.md)
- [Plugin system](docs/04-plugin-system.md)
- [Events and automation](docs/05-events-automation.md)
- [Official plugins and app ideas](docs/06-integrations.md)
- [Security and privacy](docs/07-security-privacy.md)
- [Agents](docs/08-agents.md)
- [Monetization](docs/09-monetization.md)
- [Domains and brand](docs/10-domains-brand.md)
- [Roadmap](docs/11-roadmap.md)
- [Ideas backlog](docs/12-ideas-backlog.md)
- [Implementation plan](docs/13-implementation-plan.md)
- [Documentation checkup](docs/14-documentation-checkup.md)
- [Data model](docs/15-data-model.md)
- [Mapping language](docs/16-mapping-language.md)
- [Event semantics](docs/17-event-semantics.md)
- [Testing](docs/18-testing.md)
- [Cloudflare platform](docs/19-cloudflare-platform.md)
- [Handoff checklist](docs/20-handoff-checklist.md)

Plugin package schemas live in [`schemas/plugin/v1/`](schemas/plugin/v1/).

## Repository layout

```txt
_apps/
  StatusMac/
  StatusiOS/
Sources/
  StatusCore/
  StatusUI/
Tests/
schemas/plugin/v1/
plugins/bundled/
web/
workers/registry/
docs/
```

`Status.xcodeproj` is generated from `project.yml` with XcodeGen and is intentionally ignored.

## Build and validation

Install dependencies:

```sh
npm ci
```

Validate the website, plugin packages, registry Worker, and Wrangler dry-run:

```sh
npm run check
```

Validate the Swift package:

```sh
swift test
```

Generate and build the native apps:

```sh
xcodegen generate
xcodebuild -project Status.xcodeproj -scheme StatusMac -destination 'platform=macOS' -derivedDataPath /tmp/status-mac-derived build
xcodebuild -project Status.xcodeproj -scheme StatusiOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/status-ios-derived CODE_SIGNING_ALLOWED=NO build
```

Rebuild bundled plugin packages and generated registry data:

```sh
npm run plugins:build
```

Rebuild generated website documentation data:

```sh
npm run docs:build
```

## Cloudflare surfaces

Current deployed surfaces:

- Website: `https://status-9d4.pages.dev`
- Registry API: `https://status-registry.hakobs.com`
- Registry health: `https://status-registry.hakobs.com/health`
- Plugin list: `https://status-registry.hakobs.com/v1/plugins`

The native apps default to `https://status-registry.hakobs.com`. For temporary
Cloudflare Worker previews or local registry testing, set `STATUS_REGISTRY_URL`
in the run scheme/environment, or set the same key in app defaults. The value
must be an `http` or `https` URL with a host.

Cloudflare deployment runs from the GitHub `CI` workflow after all checks pass
on a push to `main`. The `Deploy Cloudflare` workflow remains available as a
manual fallback from GitHub Actions. Local deployment commands:

```sh
npm run registry:deploy
npm run pages:deploy
```

`status.hakobs.com` is the intended website custom domain. It still needs the Cloudflare Pages custom-domain/DNS attachment; the current Wrangler version can deploy Pages but does not expose Pages custom-domain management.

## Suggested MVP

The first usable version should focus on one clean path:

```txt
macOS app
→ local database
→ plugin registry
→ App Store Connect plugin
→ GitHub plugin
→ website uptime plugin
→ overview dashboard
→ events
→ notifications
→ basic rules
```

iOS should initially be a companion dashboard, not the primary always-on automation runner.

## Current status

This repository now contains a working foundation:

- Swift shared core and shared SwiftUI package;
- macOS and iOS app shells generated with XcodeGen;
- native dashboard backed by local SQLite state;
- plugin manifest, event, rule, fingerprint, automation, and audit primitives;
- SQLite schema v0 migrator and persistence store;
- registry client, package verifier, and plugin installer;
- bundled official plugin packages that bootstrap locally before registry access;
- native plugin store UI that browses, installs, updates, and removes registry plugins;
- Vue/TypeScript/Sass website using `@sil/ui` and `bemm`;
- public docs, plugin, and developer website pages with local documentation detail routes;
- bundled App Store Connect, GitHub, GitLab, Google Play, Jira, Website Uptime, and YouTube plugin sources;
- deterministic plugin package builder and generated registry artifacts;
- Cloudflare registry Worker and deployment workflows;
- GitHub Actions CI for Node/web/registry checks and native app builds.

The product is not complete yet. Code must continue to follow the docs, not redefine the product.
