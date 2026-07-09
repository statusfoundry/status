# App Store Connect

Read-only App Store Connect status events for apps, review state, build processing, and release readiness.

## Why install this plugin

Install App Store Connect when you ship iOS or macOS apps and need review rejections and release readiness changes to reach you through Status — not buried in App Store Connect email or tabs. Status turns app version state into events you can route to inbox, digest, or immediate notifications.

## What you configure

Create one configured app per App Store Connect app:

- **App ID** — the App Store Connect app identifier to monitor

Auth uses App Store Connect API key material (`issuerId`, `keyId`, `.p8` private key) stored in Keychain.

## What it exposes

### Resources

- **app** — the configured App Store Connect app and its version/review context

### Events

| Event | Meaning | Default notification |
| --- | --- | --- |
| `app.review.rejected` | An App Store version moved into a rejected review state | Immediate |
| `app.version.ready_for_sale` | An App Store version is ready for sale | Digest |

### Views

- **Apps** — overview of configured apps and version state
- **App detail** — version and review fields for the selected app

### Checks

- **Check app review status** — cron schedule every 20 minutes
- **Refresh apps** — manual refresh of app list and version state

## Suggested automations

Suggested rules ship disabled. Enable presets if you want review rejection events in the inbox or as immediate notifications.

## Actions

Read-only in v1. Status does not submit builds, edit metadata, or reply to App Review automatically.

## Permissions and domains

- `network` — call App Store Connect HTTPS APIs
- `keychain` — store API key references and secrets
- `private-key` — use the App Store Connect `.p8` signing key
- `background-refresh` — run scheduled review checks
- **Domains:** `api.appstoreconnect.apple.com`

## What it does not do

- Does not submit builds or change App Store metadata
- Does not reply to App Review on your behalf
- Does not replace App Store Connect for deep release management

## Setup

1. Install **App Store Connect** from the Status plugin store.
2. Create a configured app and enter the App Store Connect app ID.
3. Add API key credentials with access to the app.
4. Grant network, keychain, private-key, and background refresh permissions.
5. Run **Refresh apps**, then enable **Check app review status** for scheduled polling.