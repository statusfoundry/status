# Plugin System

The plugin system is the main extensibility layer of Status.

Plugins are declarative integration packages. They do not own UI. They do not run arbitrary native code. They describe how Status can connect to a service, fetch or receive data, normalize it into common objects, and optionally perform controlled actions.

## Core principle

```txt
The app is the operating system.
Plugins are adapters.
```

## Formal schemas

Every package file has a formal JSON Schema (draft 2020-12) under `schemas/plugin/v1/`. The loader validates each file against its schema before install; unknown fields fail validation. See `schemas/plugin/v1/README.md` for the unknown-field policy and versioning rules. The examples in this document validate against those schemas.

## Plugin package shape

A plugin package is a signed archive:

```txt
appstoreconnect.statusplugin/
├── manifest.json
├── icon.svg
├── auth.json
├── setup.schema.json
├── requests.json
├── mappings.json
├── triggers.json
├── events.json
├── actions.json
├── views.json
├── rules.presets.json
└── README.md
```

Not every plugin needs every file.

## Manifest

Example:

```json
{
  "id": "com.status.appstoreconnect",
  "name": "App Store Connect",
  "version": "1.0.0",
  "author": "Status",
  "category": "Developer",
  "description": "Shows app review states, versions, builds, ratings, and direct App Store Connect links.",
  "minCoreVersion": "1.0.0",
  "platforms": ["macOS", "iOS"],
  "permissions": ["network", "keychain", "background-refresh"],
  "domains": ["api.appstoreconnect.apple.com"]
}
```

The manifest does not list emitted events or actions. `events.json` is the single source of truth for event declarations and `actions.json` for actions, so the two lists cannot drift apart.

## Permissions

Plugins declare all requested capabilities.

Permission examples:

```txt
network
keychain
oauth
api-key
private-key
background-refresh
push-webhook
user-configured-domains
write-actions
local-notification-suggestion
```

Permissions should be shown before install and again during account setup.

## Domains

Plugins must declare every domain they intend to call.

The request engine must reject undeclared domains.
Plugins that call hosts entered by the user, such as Website Uptime, must request `user-configured-domains` in addition to `network`. The setup flow must show the chosen host before the first request, and the runtime request engine must only call hosts stored in that account/resource configuration.

Example:

```json
{
  "domains": [
    "api.github.com",
    "uploads.github.com"
  ]
}
```

## Setup Schema

`setup.schema.json` describes account setup fields that the app renders with native, app-owned controls. Field identifiers use the canonical `key` property; the Swift package decoder also accepts the earlier `id` spelling for compatibility with local development packages. The installed plugin projection exposes this schema to the Integrations UI, so labels, placeholders, defaults, select options, and required state come from the plugin package while validation, persistence, and execution stay in StatusCore.

Current implementation renders and stores plain setup fields (`text`, `url`, `hostname`, `number`, `toggle`, and `select`) as non-secret local account configuration. Bearer-token, api-key header, basic-auth, and JWT API-key auth fields render as native inputs and store secret material in Keychain; SQLite stores only the `kc_` credential reference on the account row. JWT API-key credentials are signed and injected by the core request engine for App Store Connect-style ES256 flows. The native integrations screen can add, select, edit, save, and manually run multiple configured accounts per plugin. The runtime can execute unscoped due cron triggers across every configured account for the plugin.

## Auth

Supported auth types for v1:

```txt
none
api-key
bearer-token
basic-auth
oauth2   ← defined but deferred past MVP — see docs/07-security-privacy.md
jwt-api-key
private-key-jwt
```

`oauth2` stays in the schema but no v1 plugin may use it; the auth decision and MVP auth paths live in `docs/07-security-privacy.md`.

The plugin defines the auth shape. The app renders the setup form and stores secrets in Keychain.

Example:

```json
{
  "type": "api-key",
  "placement": { "in": "header", "name": "X-API-Key" },
  "fields": [
    { "key": "apiKey", "label": "API key", "type": "secret", "required": true }
  ]
}
```

```json
{
  "type": "jwt-api-key",
  "fields": [
    { "key": "issuerId", "label": "Issuer ID", "type": "text", "required": true },
    { "key": "keyId", "label": "Key ID", "type": "text", "required": true },
    { "key": "privateKey", "label": "Private Key", "type": "secret-file", "required": true }
  ]
}
```

## Requests

Requests are declarative HTTP definitions.

Example:

```json
{
  "requests": {
    "list_apps": {
      "method": "GET",
      "url": "https://api.appstoreconnect.apple.com/v1/apps",
      "auth": "default",
      "pagination": {
        "type": "jsonapi-next-link",
        "path": "$.links.next"
      }
    }
  }
}
```

## Mappings

Mappings convert service-specific payloads into Status objects.

Example resource mapping:

```json
{
  "resources": [
    {
      "type": "app",
      "id": "$.id",
      "name": "$.attributes.name",
      "fields": {
        "bundleId": "$.attributes.bundleId",
        "sku": "$.attributes.sku"
      },
      "actionUrl": "https://appstoreconnect.apple.com/apps/{{id}}/appstore"
    }
  ]
}
```

Example event mapping:

```json
{
  "events": [
    {
      "type": "app.review.rejected",
      "when": "$.attributes.appStoreState == 'REJECTED'",
      "resourceId": "$.id",
      "title": "App rejected",
      "summary": "{{resource.name}} needs a reviewer reply.",
      "severity": "critical"
    }
  ]
}
```

## Events

Plugins declare events they can emit.

```json
{
  "events": [
    {
      "type": "app.review.rejected",
      "label": "App rejected",
      "resourceType": "app",
      "defaultSeverity": "critical",
      "notificationDefault": "immediate",
      "opensIncident": "review_blocker",
      "closedBy": "app.review.approved"
    }
  ]
}
```

Plugins do not send notifications directly. They suggest defaults. The core and user preferences decide.
`opensIncident` and `closedBy` are optional. Use them only for event pairs where a later recovery or clear event should resolve the user-facing StatusItem for the opening event. The plugin still emits normalized events; the core owns the resolution behavior.

## Triggers

Plugins can define trigger types:

```txt
cron
manual
push
event
```

Example:

```json
{
  "triggers": [
    {
      "id": "poll_apps",
      "type": "cron",
      "label": "Check app statuses",
      "defaultSchedule": "*/15 * * * *",
      "request": "list_apps"
    },
    {
      "id": "refresh_now",
      "type": "manual",
      "label": "Refresh now",
      "request": "list_apps"
    }
  ]
}
```

## Push triggers

Push triggers describe incoming webhook support.

Example:

```json
{
  "triggers": [
    {
      "id": "github_webhook",
      "type": "push",
      "label": "GitHub webhook",
      "path": "/webhooks/github",
      "signature": {
        "type": "hmac-sha256",
        "header": "X-Hub-Signature-256"
      },
      "events": ["pull_request", "issues", "workflow_run"]
    }
  ]
}
```

A push trigger may be routed through the optional Status Relay.

## Actions

Actions are controlled outputs.

Example:

```json
{
  "actions": [
    {
      "id": "jira.createIssue",
      "label": "Create Jira issue",
      "requiresWritePermission": true,
      "inputSchema": {
        "fields": [
          { "key": "project", "type": "select", "label": "Project", "required": true },
          { "key": "summary", "type": "template", "label": "Summary", "required": true },
          { "key": "description", "type": "template", "label": "Description" }
        ]
      },
      "request": "create_issue"
    }
  ]
}
```

Actions must be permissioned and audited.

## Views

Plugins may define which built-in view types to use.

Example:

```json
{
  "views": [
    {
      "id": "overview",
      "type": "overview_cards",
      "title": "App Store Connect"
    },
    {
      "id": "apps",
      "type": "resource_list",
      "resourceType": "app",
      "fields": ["name", "state", "version"]
    },
    {
      "id": "app_detail",
      "type": "resource_detail",
      "resourceType": "app"
    }
  ]
}
```

The app renders the view natively.

## Rule presets

Plugins can suggest automations.

Example:

```json
{
  "presets": [
    {
      "name": "Notify me when an app is rejected",
      "description": "Shows a critical notification when App Store review rejects an app.",
      "when": {
        "eventType": "app.review.rejected"
      },
      "then": [
        {
          "action": "notification.show",
          "title": "{{event.title}}",
          "body": "{{event.summary}}"
        }
      ]
    }
  ]
}
```

## Plugin registry

Status uses Cloudflare for hosted plugin distribution:

```txt
Cloudflare Pages
→ marketing site and public plugin directory

Cloudflare R2
→ immutable signed plugin ZIP packages

Cloudflare Workers
→ registry API, compatibility metadata, revocations
```

The registry API is the app-facing source of plugin metadata. R2 is the package source. The app must verify every downloaded package locally.

Current native implementation status:

- `PluginRegistryClient` can fetch plugin lists, plugin details, versions, registry snapshots, and revocations from the Worker API.
- Registry trust labels are metadata only. A version is locally installable only after the installer verifies package hash, signature material, and revocation state.
- `PluginPackageVerifier` now enforces package SHA-256 matches, Ed25519 signatures against the app-pinned development signing key, and registry revocation checks before a package can be treated as installable. macOS and iOS fetch revocations from the registry during their app-alive background loop; installed plugin ID, version, package-hash, and signing-key revocations are applied locally to mark versions revoked, disable affected plugins, and write audit rows. Production distribution must replace the repository development key with release key custody described in `docs/07-security-privacy.md`.
- Verified install records persist plugin metadata, version integrity data, and permission grant defaults to SQLite; install is rejected if verification metadata does not match the manifest id/version.
- `PluginInstaller` orchestrates registry metadata lookup, revocation fetch, package/manifest download, package verification, package definition decoding, local file writes, and SQLite install recording.
- Installed package definitions materialize into local runtime records: `triggers.json` becomes enabled trigger definitions and `rules.presets.json` becomes disabled suggested rules. Presets are never enabled automatically.
- The shared native integrations screen loads installed plugins from SQLite, fetches compatible registry entries from `status-registry.hakobs.com`, shows requested domains and permissions, installs through `PluginInstaller`, persists installed permission grants and trigger enablement through native toggles, and removes installed plugins through `StatusPersistenceStore.uninstallPlugin`. Permission grants are enforced by the runtime: network requests require a granted `network` permission, due cron enqueueing requires `background-refresh`, credential reads require `keychain`, and JWT/private-key credentials require `private-key`. Removal is confirmed in the app and deletes active plugin metadata, versions, permission grants, account setup, triggers, suggested rules, and local resources; historical events and audit entries remain for traceability.
- `PluginRuntimeService` now provides the first app-facing execution path for installed declarative plugins. The macOS and iOS integrations screens render setup, bearer-token, api-key, basic-auth, and JWT API-key auth fields from installed plugin package metadata and expose a Run action for any installed plugin with a configured account and enabled manual trigger; users can add multiple accounts, select an account, edit its setup values, and run a manual check for that account. The settings screens keep the Website registry check as a diagnostic shortcut. Installed plugin setup/auth metadata is projected from the local package into the app-owned setup row, so labels, placeholders, options, defaults, and required state come from `setup.schema.json` and `auth.json`. The setup path saves non-secret user configuration locally and stores bearer tokens, API-key bundles, basic auth bundles, or JWT credential bundles in Keychain; the run path enqueues manual or due cron trigger jobs, checks required permission grants, injects bearer/api-key/basic/JWT credentials at request time, executes `requests.json` and `mappings.json`, stores normalized resources/events/metric points locally, emits metric drop events from persisted points, evaluates inserted events against stored rules, dispatches allowed runtime action effects through the platform shell, records the job/action runs, and writes audit output. Unscoped due cron triggers run once per configured account; account-scoped triggers target only that account. Due cron triggers that cannot enqueue because of missing background permission, request metadata, or account configuration write stable skipped audit rows. This is intentionally a narrow proving path; configurable metric thresholds and OS-level background runners are still planned work.
- Bundled plugin source lives in `plugins/bundled/*`. Each bundled plugin ships declarative package files such as `requests.json`, `triggers.json`, `events.json`, `mappings.json`, and `rules.presets.json`. `npm run plugins:build` validates each manifest plus core cross-file references, builds deterministic `.statusplugin.zip` artifacts, computes registry SHA-256 values, and refreshes Worker metadata/artifacts; `npm run plugins:check` fails when generated registry data is stale. Native shells record a `sync_state` bootstrap marker after first bundled install so bundled plugins are available on fresh databases but are not silently reinstalled after a user removes them.
- Example plugin source lives in `plugins/examples/*`. Example packages are validated by `npm run plugins:check` but are not signed, published to the registry, or bundled into the native apps. `plugins/examples/mock-operations` is the starter template for third-party authors and demonstrates every v1 package file shape.

Public plugin publishing is review-based. v1 should not allow arbitrary public upload directly into the registry. Third-party plugins should start as pull requests against the official plugin source repository, pass validation, receive maintainer/security review, then be signed and published by Status.

Plugin trust levels:

```txt
official
verified-third-party
local-dev
```

Only signed `official` and `verified-third-party` packages should appear in the hosted registry. `local-dev` packages are installed through Developer Mode with clear warnings.

Registry entry example:

```json
{
  "id": "com.status.youtube",
  "name": "YouTube",
  "latestVersion": "1.0.0",
  "platforms": ["macOS", "iOS"],
  "minCoreVersion": "1.0.0",
  "trustLevel": "official",
  "downloadUrl": "https://plugins.status.app/plugins/com.status.youtube/1.0.0/com.status.youtube-1.0.0.statusplugin.zip",
  "sha256": "...",
  "signature": "...",
  "verified": true,
  "revoked": false
}
```

## Install flow

```txt
Open Integrations
→ Browse plugin store
→ Select plugin
→ Check compatibility
→ Fetch version metadata from registry Worker
→ Download package from R2-backed URL
→ Verify hash and signature
→ Check revocation list
→ Show permissions
→ Install package
→ Register triggers
→ Store suggested rules disabled
→ Render setup form
→ Store secrets in Keychain
→ Run first sync
→ Show status
```

See `docs/19-cloudflare-platform.md` for endpoint and hosting details.

## Developer mode

Developer mode should support:

- install local plugin folder;
- validate plugin schema;
- run test request;
- preview mapped resources/events;
- inspect permissions;
- export signed package later.

Developer mode should show warnings for unsigned plugins.

## Third-party plugins

Third-party plugin support should be staged.

### v1

- no public upload form;
- no self-service registry publishing;
- local Developer Mode only;
- official examples are open source;
- accepted third-party plugins go through pull request review.

### Later

- developer accounts;
- package upload intake;
- automated validation;
- manual review before public listing;
- verified-third-party badge;
- optional marketplace features.

Third-party plugins must follow the same v1 restrictions as official plugins: declarative files only, declared domains, explicit permissions, no custom UI, no arbitrary code, and no direct Keychain access.

## v1 restrictions

Do not support:

- custom plugin UI;
- arbitrary code;
- unbounded network access;
- direct Keychain access by plugin;
- native dynamic libraries;
- hidden background execution;
- plugin-to-plugin communication.

This keeps Status safe, consistent, and easier to ship across macOS and iOS.
