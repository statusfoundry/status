# Plugin System

The plugin system is the main extensibility layer of Status.

Plugins are declarative integration packages. They do not own UI. They do not run arbitrary native code. They describe how Status can connect to a service, fetch or receive data, normalize it into common objects, and optionally perform controlled actions.

Publication follows `docs/22-plugin-governance.md`: v1 uses source-first pull requests, CI validation, maintainer/security review, Status signatures, immutable R2 artifacts, and registry metadata updates. There is no direct public upload path into the installable registry.

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
  "icon": "sf:app.badge",
  "accentColor": "#2F80ED",
  "minCoreVersion": "1.0.0",
  "platforms": ["macOS", "iOS"],
  "permissions": ["network", "keychain", "background-refresh"],
  "domains": ["api.appstoreconnect.apple.com"]
}
```

The manifest does not list emitted events or actions. `events.json` is the single source of truth for event declarations and `actions.json` for actions, so the two lists cannot drift apart.

Each plugin must declare its own app-owned visual identity through `icon` and `accentColor`. `icon` is an SF Symbol name, optionally prefixed with `sf:`, and `accentColor` is a `#RRGGBB` hex color. These fields are metadata only: plugins still do not ship custom UI, and Status decides how the icon/color appear in the app sidebar, collapsed app strip, plugin catalog, app settings window, notifications, and future mobile surfaces. GitHub and App Store Connect must use recognizable, stable icons in the official packages.

Official plugins should also include `icon.svg` when the provider has a recognizable brand mark and the license allows redistribution. Status still owns rendering, sizing, tinting, and fallback behavior. The manifest `icon` remains the native fallback symbol; `icon.svg` is the preferred native asset for installed plugins. The package builder includes `icon.svg` in the signed archive, the loader projects it as package metadata, and the shared app-owned icon renderer uses it across the plugin catalog, app sidebar, collapsed app strip, dashboard tiles, and app settings.

`icon.svg` must be a small static SVG document: UTF-8, root `<svg>`, 32 KiB or smaller, no scripts, no event-handler attributes, and no `foreignObject`. Official GitHub and App Store Connect packages fail validation if the asset is missing. Local-dev and third-party packages may omit it and rely on the manifest SF Symbol fallback.

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

`setup.schema.json` describes account setup fields that the app renders with native, app-owned controls. Field identifiers use the canonical `key` property; the Swift package decoder also accepts the earlier `id` spelling for compatibility with local development packages. The installed plugin projection exposes this schema to the app settings surface, so labels, placeholders, defaults, select options, and required state come from the plugin package while validation, persistence, and execution stay in StatusCore.

Current implementation renders and stores plain setup fields (`text`, `url`, `hostname`, `number`, `toggle`, and `select`) as non-secret local app/account configuration. Bearer-token, api-key header, basic-auth, and JWT API-key auth fields render as native inputs and store secret material in Keychain; SQLite stores only the `kc_` credential reference on the configured app/account row. JWT API-key credentials are signed and injected by the core request engine for App Store Connect-style ES256 flows.

The native **Plugins** screen is a catalog of bundled, installed, local-dev, and registry plugins. Setting up a plugin creates a user-facing **App**. Detailed app setup opens separately, with macOS using an app settings window. Users can add, select, rename, edit, save, remove, and manually run multiple configured apps per plugin. Removing a configured app deletes that app's local setup, schedules, app-scoped rules, notification overrides, credential reference and stored credential material, active resources, metrics, and sync state while keeping the plugin installed and preserving historical events and audit entries. The runtime can execute unscoped due cron triggers across every configured app for the plugin.

## Auth

Supported auth types for v1:

```txt
none
api-key
bearer-token
basic-auth
oauth2
jwt-api-key
private-key-jwt
```

OAuth plugins declare public provider metadata only: `provider`, `applicationId`, and an `oauth2` block with `authorizationUrl`, `tokenUrl`, `redirectUri`, optional `scopes`, and optional extra authorization parameters. The manifest must request `oauth`, `keychain`, and `network`; `redirectUri` must use `status://oauth/{provider-slug}` where `{provider-slug}` exactly matches `auth.provider`, and the hosts used by `authorizationUrl` and `tokenUrl` must be listed in `domains` because Status performs those network calls on the plugin's behalf. The native setup flow must not start the OAuth connection until the user has granted those permissions. Status owns the native authorization-code + PKCE flow, validates callback `state` and the declared callback redirect scheme/host/path, token storage, refresh behavior, request header injection, and audit output. Plugins never receive access tokens or refresh tokens directly.

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
  "dashboardTile": {
    "primaryFields": ["state"],
    "secondaryFields": ["version", "actionUrl"]
  },
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

The app renders every view natively. Plugins do not ship view code. In v1 the
package decoder loads `views.json`, the package build script validates view
types and referenced resource types, and the app settings surface
renders these descriptor types against locally stored resources:

- `overview_cards`
- `resource_list`
- `resource_detail`
- `timeline`
- `metric_grid`
- `alert_list`

`resource_list` and `resource_detail` must declare `resourceType`. `fields`
must reference normalized resource fields produced by `mappings.json`; missing
fields are simply omitted from the rendered native view.

Each plugin should provide enough view descriptors for:

- a dashboard tile for every configured app;
- an app detail page opened from the dashboard tile, sidebar, or app strip;
- setup and settings sections for each configured app;
- notification/rule controls scoped to the app;
- direct source links back to the provider where the user can act.

The dashboard tile is app-configurable and app-owned. `dashboardTile` is an optional `views.json` object that declares recommended fields for newly configured apps:

- `primaryFields` lists the most important fields to show first. Keep this to one field unless two are clearly necessary.
- `secondaryFields` lists additional compact fields. Status currently stores and renders up to four fields per configured app.
- Fields may reference normalized `mappings.json` resource fields, plus the canonical `name` and `actionUrl` resource values.
- Users can override the selected fields per app in that app's settings. Existing app choices are preserved across setup edits.

For GitHub, tile fields can include repository name, source link, workflow state, review requests, assigned issues, or failing repositories when the plugin maps those fields. For App Store Connect, fields can include review state, build processing state, ratings movement, and direct App Store Connect links.

## What plugins can do

A v1 plugin can declare:

- manifest metadata, visual identity, category, documentation links, and compatibility;
- auth and setup fields rendered by Status;
- required permissions and domains;
- declarative HTTP requests and pagination;
- mappings into resources, events, metrics, and source links;
- controlled write actions that Status must permission and audit;
- dashboard tile and app detail view descriptors;
- app-scoped notification defaults;
- disabled suggested app-scoped rules;
- cross-app rule presets only when they explicitly name the source app event and target app action;
- fixture files and documentation for validation and website publishing.

## What plugins cannot do

A v1 plugin cannot:

- ship arbitrary executable code;
- ship custom native or web UI;
- read or write Keychain secrets directly;
- send notifications directly;
- bypass app-scoped rule and notification settings;
- call undeclared domains;
- access another app's credentials;
- perform destructive actions;
- enable suggested rules automatically;
- publish itself to the public registry without Status review and signing.

## App-scoped rules and notifications

Rules live with the configured app by default. A GitHub app's workflow rules belong in that GitHub app's settings. An App Store Connect app's review-state notifications belong in that App Store Connect app's settings. The global rule surface should only show explicit cross-app automations, such as:

- when App Store Connect emits `app.review.rejected`, create a GitHub issue in a selected GitHub app;
- when Website Uptime emits `website.down`, create a Jira issue in a selected Jira app;
- when GitHub emits `github.workflow.failed`, add a Status inbox item and open a provider URL.

Plugin rule presets install disabled. Enabling a preset requires the user to choose the configured app, inspect conditions, confirm permission requirements, and preview the audit output where possible.

Plugins can declare many event-level notification defaults. Status must expose them under the configured app's settings, not as duplicated global rule rows. App-level preferences override plugin defaults; event-level preferences override app-level preferences.

The current native settings UI groups notification defaults, event overrides, plugin-suggested rule presets, and custom app rules by configured app/account when apps exist, while keeping plugin-level defaults as the fallback for plugins that have no configured app yet. Enabling a suggested rule creates an app-scoped rule copy for the selected configured app/account; the disabled plugin-scoped preset remains available as the reusable template. Users can also create, edit, enable/disable, and delete custom app-scoped rules from the selected app's settings. Custom app rules can define multiple event-field conditions, safe local actions (`status.inbox.add`, `notification.show`, `status.open_url`, and `audit.note`), the review-required `webhook.post` action, and plugin-backed write actions declared in the installed plugin's `actions.json` such as `jira.createIssue`. The native form renders those plugin action inputs from `inputSchema`, including default template values, select options, required fields, and help text. Suggested rules and custom rules that include review-required actions show a write-action permission and audit-output preview, and cannot be enabled or saved until the plugin has the `write-actions` grant. Custom app rules with provider-backed write actions also require a current redacted request preview before save. Stored automation evaluation is account-aware: app-scoped rules only load for events from the matching configured app, and plugin-scoped rules remain available as broad defaults. The global automation screen is reserved for explicit `cross_app` rules.

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
- Installed package definitions materialize into local runtime records: `triggers.json` becomes enabled trigger definitions and `rules.presets.json` becomes disabled suggested rules. `actions.json` is decoded into the installed package definition so the app can inspect declared write actions and their request bindings; install-time package decoding rejects action declarations that reference missing requests. Presets are never enabled automatically.
- The shared native plugin catalog loads installed plugins from SQLite, fetches compatible registry entries from `status-registry.hakobs.com`, shows requested domains and permissions, installs through `PluginInstaller`, opens app/account settings separately from the catalog row, persists installed permission grants and trigger enablement through native toggles, and removes installed plugins through `StatusPersistenceStore.uninstallPlugin`. Permission grants are enforced by the runtime: network requests require a granted `network` permission, due cron enqueueing requires `background-refresh`, credential reads require `keychain`, and JWT/private-key credentials require `private-key`. Removal is confirmed in the app and deletes active plugin metadata, versions, permission grants, configured app/account setup, triggers, suggested rules, and local resources; historical events and audit entries remain for traceability.
- `PluginRuntimeService` now provides the first app-facing execution path for installed declarative plugins. The macOS app settings window and iOS settings presentation render setup, bearer-token, api-key, basic-auth, JWT API-key, and OAuth auth setup from installed plugin package metadata and expose a Run action for any installed plugin with a configured app/account and enabled manual trigger; users can add multiple apps/accounts, select one, edit its local display name and setup values, remove only that configured app, and run a manual check for that configured app. App rows show the plugin icon/color, configured-app count or name, and most recent persisted job status while keeping detailed settings out of the catalog page. The settings screens keep the Website registry check as a diagnostic shortcut. Installed plugin setup/auth metadata is projected from the local package into the app-owned setup row, so labels, placeholders, options, defaults, and required state come from `setup.schema.json` and `auth.json`. The setup path saves non-secret user configuration locally and stores bearer tokens, API-key bundles, basic auth bundles, JWT credential bundles, or OAuth token sets in Keychain; the run path enqueues manual or due cron trigger jobs, checks required permission grants, injects bearer/api-key/basic/JWT/OAuth credentials at request time, executes `requests.json` and `mappings.json`, stores normalized resources/events/metric points locally, emits metric drop events from persisted points, evaluates inserted events against stored app-scoped rules, dispatches allowed runtime action effects through the platform shell, records the job/action runs, and writes audit output. Provider-backed rule actions use the same package request renderer and credential injection: the runtime finds the installed plugin that declares the action, selects the configured app/account, renders the bound request with account/action/event scopes, requires `write-actions`, and records the response on the action run. Unscoped due cron triggers run once per configured app/account; account-scoped triggers target only that account. Due cron triggers that cannot enqueue because of missing background permission, request metadata, or account configuration write stable skipped audit rows. This is intentionally a narrow proving path; configurable metric thresholds and OS-level background runners are still planned work.
- macOS now treats the sidebar and collapsed top app strip as configured-app navigation. If a plugin has multiple configured apps/accounts, each appears as its own row using the plugin icon/color and the app display name. Selecting an app opens a read-only app detail page backed by the plugin's `views.json` descriptors and resources filtered to that app/account. Settings still open separately in the app settings window.
- The dashboard app section renders configured apps as tiles. Selecting a dashboard app tile opens the same app detail page as the sidebar. App settings expose dashboard tile field toggles from plugin view fields and collected resource fields; selections are stored per configured app and rendered as compact rows on the tile.
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
Open Plugins
→ Browse bundled, installed, local-dev, and registry plugins
→ Select plugin
→ Check compatibility
→ Fetch version metadata from registry Worker
→ Download package from R2-backed URL
→ Verify hash and signature
→ Check revocation list
→ Show permissions
→ Install package
→ Create or choose an app from that plugin
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

Developer mode should show warnings for unsigned plugins. The current core
implementation has a `LocalPluginInstaller` that packages a local folder into
the same deterministic ZIP format used by the registry, installs it as
`local-dev`, records `signedBy: local-dev`, and returns an explicit unsigned
warning with the plugin ID, permissions, and domains. The macOS plugin
catalog exposes this path as an **Install Local** developer-mode action that
opens a folder picker and refreshes installed plugins after success.
App settings also expose a **Preview Fixture** developer action on
macOS: the user chooses a JSON fixture payload, Status runs the installed
plugin's mappings against it, and the app shows mapped resource/event/metric
counts without committing any output to SQLite.
Local-dev install skips signature verification only; manifest validation,
declared-domain checks, OAuth permission/config checks, write-action permission checks, setup
rendering, trigger/rule installation, and runtime permission enforcement still
apply. Developers can run:

```sh
npm run plugins:validate-local -- plugins/examples/mock-operations
```

to validate a folder and print the package checksum without publishing it.
`plugins/examples/mock-operations/fixtures/` contains request fixtures used by
the native mapping tests for mapped-output preview coverage.

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

## Plugin documentation

Every official or verified third-party plugin must include documentation that can be rendered on the Status website from the plugin source repository.

Required documentation:

- plugin purpose and boundaries;
- setup prerequisites;
- exact credential steps;
- requested permissions and domains;
- supported auth modes, including OAuth availability when implemented;
- resources, events, metrics, actions, and view descriptors;
- dashboard tile options;
- app detail views;
- app-scoped rule and notification presets;
- direct provider links exposed by Status;
- troubleshooting and revocation notes;
- fixture data used by validation tests.

For App Store Connect, documentation must explain how to find or create the issuer ID, key ID, `.p8` private key, app ID, required API access, and the least-privilege setup path. The doc must also state that Status shows review/build state and links back to App Store Connect; it does not submit builds, edit metadata, or reply to review automatically.

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
