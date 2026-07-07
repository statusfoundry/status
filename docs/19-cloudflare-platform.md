# Cloudflare Platform

Status will use Cloudflare for the public web surface, plugin distribution, registry API, and later relay services.

This does not change the local-first product doctrine. The native app should remain useful without a Status account for local plugins and bundled plugins. Cloudflare is the distribution and optional network layer, not the core runtime for v1 automations.

## Cloudflare responsibilities

```txt
Cloudflare Pages
→ marketing website
→ public documentation
→ plugin directory pages
→ static registry fallback files

Cloudflare R2
→ immutable plugin ZIP packages
→ package signatures/checksums
→ registry snapshots
→ plugin icons/assets if needed

Cloudflare Workers
→ registry API
→ compatibility filtering
→ revocation/blocklist API
→ plugin metadata API
→ download URL signing later, if needed
→ webhook relay later
```

## Marketing website

The marketing website can live in the same repository as the app documentation and platform code.

Suggested paths:

```txt
web/
→ Vue + TypeScript + Sass marketing site
→ uses @sil/ui and BEMM class generation
→ plugin directory pages
→ developer documentation pages

workers/registry/
→ registry API Worker

workers/relay/
→ later webhook relay Worker

plugins/
→ bundled plugins
→ example plugins
→ official plugin source packages
```

The marketing site should be static-first and deploy to Cloudflare Pages.

Current implementation requirements:

- Vue;
- TypeScript;
- Sass;
- `@sil/ui` for shared UI styles/components;
- `bemm` for BEM class generation;
- no scoped SCSS in Vue components.

Initial pages:

- home;
- download/beta;
- plugins;
- plugin detail;
- developer docs;
- privacy/security;
- changelog.

The website can read public plugin metadata from the same registry data used by the app, but it must not be required for the native app to run.

## Plugin package hosting

Plugin packages are signed ZIP archives stored in R2.

Canonical object layout:

```txt
r2://status-plugins/
  plugins/{pluginId}/{version}/{pluginId}-{version}.statusplugin.zip
  plugins/{pluginId}/{version}/{pluginId}-{version}.statusplugin.zip.sig
  plugins/{pluginId}/{version}/manifest.json
  registry/index.json
  registry/revocations.json
  registry/snapshots/{timestamp}.json
```

Public HTTPS URLs should be stable and CDN-backed:

```txt
https://plugins.status.app/plugins/{pluginId}/{version}/{pluginId}-{version}.statusplugin.zip
https://plugins.status.app/registry/index.json
https://plugins.status.app/registry/revocations.json
```

R2 should be treated as immutable package storage. A published `{pluginId}/{version}` package should not be overwritten. Fixes ship as a new version.

## Plugin source and ownership

Official plugins should be open source unless there is a specific provider or security reason not to publish implementation details. Because v1 plugins are declarative packages, open-sourcing them is low-risk and useful:

- users can inspect requested domains and permissions;
- plugin authors can copy working examples;
- agents can improve plugins through normal review;
- plugin behavior remains aligned with the app-owned UI doctrine.

Recommended repository model:

```txt
status-app/status
→ native app
→ product docs
→ shared schemas
→ bundled plugins
→ Cloudflare site/worker code during early development

status-app/plugins
→ official installable plugin source packages, later
→ third-party plugin submissions, later if review volume grows

status-app/plugin-schemas
→ optional extraction later if schemas need independent versioning
```

Early development can keep everything in one repository. Split official plugins into a separate repository only when package release cadence or external contribution volume makes the monorepo noisy.

## Third-party plugin submission

Do not provide direct public upload in v1.

The first third-party path should be review-based:

```txt
Developer forks official plugin repo
→ adds plugin source package
→ includes fixtures and schema validation output
→ opens pull request
→ CI validates schemas, declared domains, mappings, and package shape
→ maintainer/security review checks permissions and behavior
→ approved plugin is signed by Status
→ release workflow uploads immutable package to R2
→ registry snapshot is updated
```

This keeps the plugin ecosystem useful without turning the registry into an unreviewed package host.

Later, if the ecosystem needs it, Status can add a developer portal:

```txt
Developer signs in
→ creates plugin listing
→ uploads package candidate
→ automated validation runs
→ manual review required for public listing
→ approved package is signed or countersigned by Status
→ package is published to R2
```

The developer portal should still not allow arbitrary packages to become public without review. A public upload endpoint is an intake mechanism, not a publication mechanism.

## Signing authority

For public registry distribution, Status signs the package that the app trusts.

Possible trust levels:

```txt
official
→ built or maintained by Status
→ signed by Status

verified-third-party
→ submitted by an external maintainer
→ reviewed and countersigned by Status

local-dev
→ installed manually in Developer Mode
→ unsigned or self-signed
→ warning shown
```

The native app should treat `official` and `verified-third-party` as installable from the registry only after local hash/signature/revocation checks pass. `local-dev` plugins should never be silently upgraded from the public registry unless plugin IDs and signing policy explicitly allow it.

## Registry API

The registry API is a Cloudflare Worker.

Initial endpoints:

```txt
GET /v1/plugins
GET /v1/plugins/{pluginId}
GET /v1/plugins/{pluginId}/versions
GET /v1/plugins/{pluginId}/versions/{version}
GET /v1/registry
GET /v1/revocations
```

The Worker may read registry metadata from:

- checked-in JSON built during deploy;
- R2 registry snapshots;
- Cloudflare KV/D1 later if dynamic metadata is needed.

For v1, keep the registry simple. Static JSON plus a Worker wrapper is enough.

The Worker should support app queries such as:

```txt
platform=macOS
coreVersion=1.0.0
installedPluginIds=...
```

Current implementation status:

- The registry Worker implements `GET /v1/plugins`, `GET /v1/plugins/{pluginId}`, `GET /v1/plugins/{pluginId}/versions`, `GET /v1/plugins/{pluginId}/versions/{version}`, `GET /v1/registry`, `GET /v1/revocations`, and `/health`.
- The initial static registry metadata includes official App Store Connect, GitHub, and Website Uptime plugin listings.
- Platform and minimum core-version filtering are supported for list/detail version responses.
- Public direct upload is intentionally not implemented; third-party plugins remain review-based as described above.

The Worker can return only compatible plugins, but the native app must still verify compatibility locally.

## Download flow

```txt
Native app
→ GET https://plugins.status.app/v1/plugins
→ user selects plugin
→ app requests selected version metadata
→ metadata includes R2-backed download URL, SHA-256, signature, permissions, domains
→ app downloads ZIP from Cloudflare
→ app verifies hash
→ app verifies signature
→ app checks revocation list
→ app shows permissions
→ user approves
→ app installs plugin locally
```

Cloudflare never makes the local trust decision. The native app must verify every downloaded package.

## Revocation

The registry Worker exposes a revocation list and may also serve a static fallback:

```txt
https://plugins.status.app/v1/revocations
https://plugins.status.app/registry/revocations.json
```

Revocations may target:

- plugin ID;
- plugin ID + version;
- package hash;
- signing key ID.

The app should check revocations before install, before update, and periodically for installed plugins.

## Domains

Current target domains:

```txt
status.hakobs.com
status-registry.hakobs.com
```

Current deployment state as of 2026-07-07:

```txt
Cloudflare Pages project
→ name: status
→ production hostname: status-9d4.pages.dev
→ latest deployed preview: c8b4d202.status-9d4.pages.dev
→ custom domain: status.hakobs.com
→ custom domain status: pending
→ pending reason: CNAME record not set

Cloudflare Worker
→ name: status-registry
→ custom domain: status-registry.hakobs.com
→ current version id: 773f4f92-2ac8-4e77-a301-130b1706e91e

Cloudflare R2
→ bucket: status-plugins
```

Required DNS record for the marketing website:

```txt
type: CNAME
name: status
target: status-9d4.pages.dev
proxied: true
```

The existing Wrangler OAuth token can create Pages domains and deploy Workers/Pages, but Cloudflare returned `403` for DNS record API access when checking `status.hakobs.com`. If DNS write access is added to the token, create the CNAME above and the Pages custom domain should move from pending to active after certificate validation.

If the final brand changes, keep the same structure:

```txt
{brand}.app
plugins.{brand}.app
docs.{brand}.app
hooks.{brand}.app
api.{brand}.app
```

Current Cloudflare account:

```txt
email: me@sil.mt
account: Me@sil.mt's Account
account_id: 8cef251b5fdcf6c6f63db98b7aa49f9a
```

## Later relay

The webhook relay should also use Cloudflare Workers, but it is separate from the registry Worker.

Relay responsibilities later:

- receive provider webhooks;
- validate signatures/tokens;
- store payloads briefly in R2/KV/Durable Objects as appropriate;
- notify/push to devices later;
- let devices pull pending payloads;
- avoid executing automations in v1.

Do not combine registry and relay behavior in one Worker. They have different security and retention concerns.

## Non-goals

For v1, Cloudflare should not:

- execute user automations;
- store user provider tokens;
- become required for bundled/local plugins;
- make trust decisions on behalf of the native app;
- host arbitrary plugin code execution;
- replace local audit logs.

## Agent guidance

When implementing platform work:

- use Cloudflare Pages for the marketing/developer site;
- use R2 for immutable plugin ZIPs and registry snapshots;
- use Workers for the registry API;
- keep the native app's local verification mandatory;
- keep relay/cloud-runner work separate and later;
- document every public endpoint before implementation.
