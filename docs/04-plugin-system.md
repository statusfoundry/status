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
write-actions
local-notification-suggestion
```

Permissions should be shown before install and again during account setup.

## Domains

Plugins must declare every domain they intend to call.

The request engine must reject undeclared domains.

Example:

```json
{
  "domains": [
    "api.github.com",
    "uploads.github.com"
  ]
}
```

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
      "notificationDefault": "immediate"
    }
  ]
}
```

Plugins do not send notifications directly. They suggest defaults. The core and user preferences decide.

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
