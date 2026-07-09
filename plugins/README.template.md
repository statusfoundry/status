# Plugin name

One-sentence summary of what this plugin helps you watch and why it exists in Status.

Publisher metadata lives in `manifest.json`:

```json
"author": {
  "name": "Your Publisher Name",
  "publisherId": "your-publisher-slug"
}
```

Register the publisher in `plugins/publishers.json` so the website can link to `/publishers/your-publisher-slug/`.

Provider application IDs for OAuth belong in `auth.json` as `provider` and `applicationId` (public client IDs only). OAuth `redirectUri` must use `status://oauth/{provider-slug}`. Declare the OAuth authorization and token endpoint hosts in `manifest.json` `domains`.

## Why install this plugin

Explain the operational problem it solves. Who should install it, and what attention signal they get that they cannot get easily from the provider dashboard alone.

## What you configure

Describe the native setup fields from `setup.schema.json`: accounts, hosts, project IDs, repositories, and any credentials the app stores in Keychain.

## What it exposes

### Resources

List normalized resource types the plugin stores (for example repositories, apps, websites).

### Events

List emitted event types with plain-language meaning. Match `events.json` exactly.

### Views

Describe dashboard and detail surfaces from `views.json`.

### Checks

List manual and scheduled triggers from `triggers.json`.

## Suggested automations

Summarize `rules.presets.json`. Note that presets install disabled and require explicit user enablement.

## Actions

List controlled write actions from `actions.json`, or state that the plugin is read-only in v1.

## Permissions and domains

List `manifest.json` permissions and declared domains. Explain why each permission is needed.

## What it does not do

State v1 boundaries: no hidden writes, no provider UI replacement, no undeclared network access.

## Setup

1. Install the plugin from the Status plugin store or Developer Mode.
2. Create a configured app and complete setup.
3. Grant required permissions.
4. Run a manual check, then enable schedules if needed.

This README is published on the Status website at `/plugins/{plugin-id}/`. Keep it accurate when package files change.
