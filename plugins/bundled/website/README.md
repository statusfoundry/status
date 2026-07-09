# Website Uptime

Declarative uptime checks for sites and endpoints the user chooses to track.

## Why install this plugin

Install Website Uptime when you want simple, local-first availability monitoring for hosts you care about — status pages, APIs, marketing sites, or internal endpoints — without standing up a separate uptime SaaS. Status emits clear down/recovered events and can notify you immediately when a site stops responding.

## What you configure

Create one configured app per host:

- **Host** — hostname only, without `https://` or a path (for example `status-registry.hakobs.com`)

No third-party API token is required. Checks run from your Mac or iOS device through declared HTTPS requests.

## What it exposes

### Resources

- **website** — the tracked host and its latest health check result

### Events

| Event | Meaning | Default notification |
| --- | --- | --- |
| `website.down` | The tracked site did not return a healthy response | Immediate |
| `website.recovered` | The tracked site returned to a healthy response | Digest |

Down events can open a downtime incident closed by recovery events.

### Views

- **Websites** — list of tracked hosts with latest status fields
- **Website detail** — latest check result and response context

### Checks

- **Check website uptime** — cron schedule every 5 minutes
- **Refresh website status** — manual check on demand

## Suggested automations

Suggested rules ship disabled. Enable presets if you want downtime routed to inbox or immediate notifications.

## Actions

Read-only in v1. The plugin checks endpoints; it does not modify DNS, hosting, or site content.

## Permissions and domains

- `network` — perform HTTPS health checks
- `background-refresh` — run scheduled uptime polling
- `user-configured-domains` — check hosts you enter during setup (no fixed provider domain list)

## What it does not do

- Does not replace full synthetic monitoring with multi-region probes
- Does not edit hosting, DNS, or TLS configuration
- Does not run from Status cloud infrastructure in v1 (checks originate on your device)

## Setup

1. Install **Website Uptime** from the Status plugin store.
2. Create a configured app and enter the host to monitor.
3. Grant network and background refresh permissions.
4. Run **Refresh website status**, then enable **Check website uptime** for scheduled polling.