# Mock Operations

Example declarative plugin package for operational status data.

## Why install this plugin

Install Mock Operations only for **development and authoring** — not for production monitoring. It demonstrates every v1 package file so plugin authors can validate schemas, preview fixture mappings in Developer Mode, and copy the structure for a real provider integration.

## What you configure

Example setup fields for a fictional service:

- Native setup schema with provider configuration placeholders
- Recorded fixtures instead of live API dependencies during tests

## What it exposes

### Resources

- **service** — example operational service records from fixture data

### Events

| Event | Meaning | Default notification |
| --- | --- | --- |
| `mock.service.degraded` | Example service entered a degraded state | Dashboard only |
| `mock.service.recovered` | Example service recovered | Digest |
| `mock.error_rate.high` | Example error rate crossed a threshold | Dashboard only |

### Views

- Overview cards, resource lists, timelines, and alert list descriptors declared in `views.json`

### Checks

- Manual and cron triggers declared in `triggers.json` for fixture-driven refresh flows

## Suggested automations

- Example presets in `rules.presets.json` install disabled
- Demonstrates inbox and notification actions without enabling them by default

## Actions

Includes example write-action declarations for author education. Actions require explicit `write-actions` permission and user approval in Status.

## Permissions and domains

- `network` — example HTTPS requests to `example.com`
- `background-refresh` — example scheduled triggers
- `local-notification-suggestion` — example notification presets
- `write-actions` — example controlled write declarations
- **Domains:** `example.com`

## What it does not do

- Does not connect to a real production API in the template form
- Is not published to the registry as a trusted integration
- Must be adapted before use with a real provider

## Setup

### Validate in the monorepo

```sh
npm run plugins:validate-local -- plugins/examples/mock-operations
```

### Test in the app

1. Build and open StatusMac.
2. Enable Developer Mode.
3. Use **Install Local** and select this folder.
4. Configure the plugin and run a manual trigger.
5. Use **Preview Fixture** to inspect mapped output.

### Fork-friendly template

A standalone copy lives at `status-plugin-example/` in the Status repository. Regenerate it with `npm run plugin-example:sync`.

## Submit for review

v1 has no public upload form. Open a pull request with fixtures and validation evidence when adapting this template for a real provider.