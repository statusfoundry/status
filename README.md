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

Detailed docs:

- [Product soul](docs/01-product-soul.md)
- [Requirements](docs/02-requirements.md)
- [Architecture](docs/03-architecture.md)
- [Plugin system](docs/04-plugin-system.md)
- [Events and automation](docs/05-events-automation.md)
- [Integrations](docs/06-integrations.md)
- [Security and privacy](docs/07-security-privacy.md)
- [Agents](docs/08-agents.md)
- [Monetization](docs/09-monetization.md)
- [Domains and brand](docs/10-domains-brand.md)
- [Roadmap](docs/11-roadmap.md)
- [Ideas backlog](docs/12-ideas-backlog.md)
- [Implementation plan](docs/13-implementation-plan.md)
- [Documentation checkup](docs/14-documentation-checkup.md)
- [Cloudflare platform](docs/19-cloudflare-platform.md)
- [Handoff checklist](docs/20-handoff-checklist.md)

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

This repository currently contains product, architecture, and implementation documentation only. Code should follow the docs, not redefine the product.
