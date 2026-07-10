# Security and Privacy

Status handles accounts, tokens, API keys, events, operational data, and possible automation actions. Security is part of the product, not a later feature.

## Security posture

Default posture:

```txt
Local-first.
Read-only-first.
Explicit permissions.
No hidden code execution.
No plugin-owned UI.
Audit every action.
```

## Secret storage

Secrets must be stored in Keychain.

Examples of secrets:

- OAuth access token;
- OAuth refresh token;
- API key;
- private key;
- webhook secret;
- bearer token;
- basic auth password.

Never store these in:

- plugin files;
- SQLite plaintext;
- logs;
- crash reports;
- analytics payloads;
- exported config.

SQLite may store references to Keychain entries.

Current StatusCore implementation:

```txt
CredentialStore
→ protocol used by core code paths

KeychainCredentialStore
→ stores secret bytes as generic-password Keychain items
→ returns only kc_ references to callers

InMemoryCredentialStore
→ deterministic test double for unit tests and non-Keychain environments
```

Credential references use this shape:

```txt
kc_<26 lowercase base32 characters>
```

Plugin-facing code should receive only the `kc_` reference. Request/auth code is responsible for resolving the reference at execution time and must not log or persist the raw secret.

## Plugin package verification

Before installing a plugin, Status should verify:

- package hash;
- package signature;
- plugin ID;
- version;
- minimum core version;
- supported platforms;
- revocation/blocklist status;
- requested permissions;
- declared domains.

Unsigned local plugins should require Developer Mode and clear warnings.

## Plugin signing

This section is the implementable specification for package signing. It aligns with the hosting and trust model in `docs/19-cloudflare-platform.md`.

### Algorithm

Plugin packages are signed with Ed25519.

- Signature: Ed25519 over the raw bytes of the package ZIP.
- Checksum: SHA-256 of the same ZIP bytes, published alongside the signature.
- The signature is detached. The ZIP itself is never modified after signing.

Package artifacts per version:

```txt
{pluginId}-{version}.statusplugin.zip
{pluginId}-{version}.statusplugin.zip.sig   ← detached Ed25519 signature over ZIP bytes
sha256 checksum                             ← in registry metadata and version manifest
```

Registry metadata for a version must include `sha256` and `signature` (base64), plus the `keyId` of the signing key that produced the signature.

### Signing authority and key custody

Status holds the signing key. Plugin authors do not sign for the public registry; approved third-party packages are countersigned by Status after review, per `docs/19-cloudflare-platform.md`.

Custody model:

- The Ed25519 private key is generated offline and never lives in the repository or on developer laptops.
- The active signing key is stored as a CI release secret (or a hardware token for manual releases). Only the release workflow that publishes to R2 can read it.
- An offline backup of the key material lives outside CI (encrypted, offline storage).
- Each key has a stable `keyId` (short identifier derived from the public key) so signatures, registry metadata, and revocations can name it.

### Pinned public key and rotation

The app ships with the registry public key compiled into the binary, keyed by `keyId`:

```json
{
  "trustedKeys": [
    { "keyId": "status-signing-1", "algorithm": "ed25519", "publicKey": "base64..." }
  ]
}
```

Rules:

- The app never fetches trust roots from the network. A key becomes trusted only through an app update.
- The pinned set is a list, so rotation works by shipping an app version that trusts both the old and new key, re-signing new packages with the new key, and later removing the old key from the pinned set.
- A compromised key is handled by revoking its `keyId` (see revocation) and shipping an app update with the key removed.

Current implementation status: `PluginPackageVerifier` verifies registry and bundled package signatures with CryptoKit Ed25519 against a pinned `status-foundry-dev` development public key. `scripts/build-plugin-packages.mjs` signs bundled/demo artifacts with the matching repository development private key so local builds and temporary registry deployments are verifiable. Production release signing must replace this development key with offline/CI custody before public distribution.

### Verification order

Before installing or updating any registry package, the app verifies locally, in this order, failing closed at the first failure:

```txt
1. Hash        → SHA-256 of downloaded ZIP bytes equals the registry-declared sha256
2. Signature   → detached .sig verifies over the same ZIP bytes with a pinned trusted key
3. Revocation  → plugin ID, plugin ID + version, package hash, and signing keyId
                 are all absent from the current revocation list
4. Compatibility → plugin ID matches metadata, version matches, minCoreVersion
                 and platforms are satisfied
5. Permissions → requested permissions and declared domains are shown to the user;
                 install proceeds only after approval
```

The registry Worker may pre-filter, but Cloudflare never makes the trust decision. Verification always runs on device.

### Trust levels

Per `docs/19-cloudflare-platform.md`:

```txt
official                → built or maintained by Status, signed by Status
verified-third-party    → externally maintained, reviewed and countersigned by Status
local-dev               → Developer Mode only, unsigned or self-signed
```

Only `official` and `verified-third-party` packages appear in the hosted registry, and both must pass the full verification order above. `local-dev` plugins are never silently upgraded from the public registry.

### Revocation list

The revocation list is JSON, served by the registry Worker with a static fallback:

```txt
https://plugins.status.app/v1/revocations
https://plugins.status.app/registry/revocations.json
```

Format:

```json
{
  "updatedAt": "2026-07-07T00:00:00Z",
  "revocations": [
    { "pluginId": "com.example.bad" },
    { "pluginId": "com.example.buggy", "version": "1.2.0" },
    { "sha256": "..." },
    { "keyId": "status-signing-0" }
  ]
}
```

Each entry targets exactly one of: plugin ID (all versions), plugin ID + version, package hash, or signing key ID. Entries may carry an optional `reason` string for user-facing messaging.

Check timing:

- before every install;
- before every update;
- periodically for installed plugins: on app launch and at least every 24 hours.

If a periodic check matches an installed plugin, the app disables the plugin, keeps its Keychain secrets untouched, and tells the user why. Current macOS and iOS shells fetch revocations during their app-alive background loop and apply installed plugin ID, plugin ID + version, package-hash, and signing-key revocations locally by marking installed versions revoked, disabling affected plugins, and writing audit rows. If the revocation list is unreachable, installs of new packages should warn or fail closed; already-installed plugins keep running against the last successfully fetched list.

### Unsigned and local-dev plugins

Unsigned plugins install only through Developer Mode:

- Developer Mode is off by default and enabled in settings with an explanation of the risk.
- Installing an unsigned plugin shows a blocking warning naming the plugin ID, requested permissions, and declared domains.
- Local-dev plugins are visibly badged in the plugin list.
- Local-dev plugins skip signature verification but not schema validation, domain enforcement, or the permission model.

## Network boundary

Plugins must declare allowed domains.

The request engine must reject any URL outside declared domains.

Example:

```json
{
  "domains": ["api.github.com"]
}
```

If a mapping or request tries to send data to another host, it should fail closed.

## Permission model

Permissions should be granular.

Suggested permission groups:

```txt
Network access
Account authentication
Keychain secret storage
Background refresh
Incoming webhook
Read resources
Read metrics
Create external item
Send external message
Modify external resource
```

Write permissions should not be granted simply because a plugin is installed. They should be requested when a rule/action requires them.

## Authentication flows

This section is the auth decision for v1. It resolves the open question from `docs/04-plugin-system.md`.

### v1 auth types

Plugins may declare these auth types in `auth.json`:

```txt
none
api-key
bearer-token
basic-auth
oauth2
jwt-api-key
private-key-jwt
```

`oauth2` is available for plugins that declare the `oauth` and `keychain` permissions and provide provider/client metadata. OAuth support is native and app-owned: plugins declare endpoints and scopes, while Status generates PKCE authorization requests, stores token sets in Keychain by reference, refreshes expired tokens through the declared token endpoint, and injects bearer headers at request time.

Bundled and registry plugin icons follow the same fail-closed model. `icon.svg` is treated as signed package content and is validated before the app renders it or the website/registry expose it. Status rejects scripts, event handlers, embedded HTML, remote references, external image loads, inline styles, and unsafe `href` values. Static gradients, masks, clip paths, symbols, and `use` references are allowed only when they resolve to internal fragment IDs inside the same SVG document. The validator also caps SVG size and structural complexity so provider marks stay safe to render inside native WebKit-backed views.

All auth types share the same model: the plugin declares the fields, the app renders the setup form natively, secrets go to Keychain, and the request engine injects credentials at request time. Plugins never read secrets directly.

Current implementation status: bearer-token, api-key header, basic-auth, JWT API-key, and OAuth authorization/token injection/refresh are implemented for installed declarative plugins. The native setup form masks secret input, `PluginSetupConfiguration` writes bearer token bytes, credential bundles, or OAuth token sets to `CredentialStore`, SQLite stores only the `credential_ref`, and `PluginRuntimeService` resolves that reference into the appropriate request header at request time. Basic auth supports the Jira-style email/API-token credential bundle. JWT signing currently covers the App Store Connect ES256 API-key flow. OAuth setup uses app-owned PKCE authorization URLs, validates callback `state` and the declared redirect scheme/host/path, exchanges authorization codes for token sets through the plugin-declared token endpoint, and stores the resulting token set in Keychain.

### MVP auth paths per integration

Every roadmapped integration through Phase 7 has a feasible non-OAuth path:

```txt
Website uptime     → none
Generic webhook    → none, or shared secret (HMAC/token) for incoming payloads
RSS/feed           → none
Manual status      → none
Network check      → none
Weather            → none, or provider api-key
App Store Connect  → jwt-api-key (issuer ID + key ID + .p8 private key;
                     app builds short-lived ES256 JWTs per request window)
GitHub             → bearer-token (fine-grained personal access token;
                     classic PAT acceptable for early local testing)
Jira               → basic-auth (Atlassian account email + API token)
```

Later phases, for reference: Cloudflare uses an API token (bearer), Stripe uses a restricted API key. Neither needs OAuth.

### OAuth design

- Client ID ownership: does Status register one client per provider and embed it in the app, or does the user supply their own client? Embedded client IDs are public by nature on native apps; the design must not rely on a confidential client secret.
- PKCE: native flows must use authorization code + PKCE (S256), no implicit flow.
- Redirect URI scheme: a custom URL scheme or universal link owned by the app, registered with each provider, and how the app validates state on callback.
- Refresh responsibility: the core request engine owns token refresh, transparently, per account. Plugins never see refresh tokens.
- Keychain storage: access token, refresh token, expiry, and scopes stored per account in Keychain, same rules as all other secrets.

Implementation boundary: core and the native shells now support OAuth package metadata, PKCE authorization URL creation, `status://oauth/...` callback delivery, callback `state` and redirect validation, authorization-code exchange, Keychain-backed token-set storage, expired-token refresh, and request header injection. GitHub/GitLab/Jira can still keep PAT/API-token setup paths as practical low-friction options, but OAuth-only plugins no longer need a plugin-owned executable flow.

### Token refresh and failure behavior

- Credentials that expire (JWT API keys and OAuth tokens) are refreshed by the core request engine, never by plugin logic.
- On auth failure (401/403, expired key, revoked token) the request fails closed: no retry storm, no credential guessing, no fallback host.
- The affected account enters a `needs-reconnect` state. The app surfaces this as a status item on the dashboard and in the account settings, with a direct path to re-enter credentials.
- Sync for that account pauses until the user reconnects. Other accounts and plugins are unaffected.
- Auth failures are logged without the credential material.

## Action safety

Action safety levels:

```txt
safe
review-required
dangerous
unsupported
```

### Safe actions

Examples:

- local notification;
- add to inbox;
- open URL;
- local audit note.

### Review-required actions

Examples:

- create Jira issue;
- create GitHub issue;
- send webhook;
- create email draft.

### Dangerous actions

Avoid in v1.

Examples:

- delete remote data;
- modify App Store metadata;
- submit app builds;
- send email automatically;
- change billing settings;
- transition production state.

## Audit log

Every external action should create an audit entry.

Audit should include:

- rule name;
- event that triggered it;
- action type;
- target account/resource;
- input summary;
- result;
- timestamp;
- source link;
- error if failed.

The audit log is part of user trust.

## Push/webhook security

Incoming pushes should use one of:

- provider signature verification;
- HMAC shared secret;
- bearer token;
- signed payload;
- secret URL token, only for low-risk generic webhooks.

The relay should validate signatures before forwarding payloads where possible.

## Cloud relay privacy

If Status Relay is introduced, it should start minimal.

Relay should:

- receive webhook payloads;
- verify signatures;
- store events briefly;
- forward to devices;
- avoid long-term storage by default;
- avoid executing rules in v1;
- make retention clear.

Relay should not become a hidden backend dependency for local-first users.

## Telemetry

Telemetry should be minimal and opt-in if possible.

Useful product telemetry, if added:

- app version;
- plugin install count;
- plugin sync success/failure counts;
- crash/error categories.

Avoid collecting:

- event payloads;
- resource names;
- API responses;
- user account identifiers;
- secrets;
- rule contents;
- operational data from connected services.

## Export/import

Config export should exclude secrets by default.

Export may include:

- installed plugin IDs;
- rule definitions;
- dashboard layout;
- non-secret account display names;
- local preferences.

Export must not include:

- tokens;
- private keys;
- API keys;
- webhook secrets.

## Threat model

Important risks:

- malicious plugin package;
- tampered plugin registry;
- token exfiltration;
- noisy or harmful automations;
- accidental external write action;
- webhook spoofing;
- overbroad plugin permissions;
- logs leaking operational data.

Mitigations:

- Ed25519 plugin signatures verified against an app-pinned registry key;
- declared domains;
- Keychain-only secrets;
- user-visible permissions;
- read-only-first integrations;
- action safety levels;
- audit log;
- revocation checks before install, before update, and periodically;
- OAuth uses public native client IDs and PKCE; no plugin or app bundle may contain a confidential OAuth client secret;
- fail-closed auth with a visible reconnect state;
- limited relay storage;
- no arbitrary plugin code in v1.

## Guiding principle

```txt
Trust is the product moat.
```
