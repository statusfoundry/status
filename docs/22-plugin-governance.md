# Plugin Governance

Status plugins are open-source, review-based packages. The registry is not a public upload bucket in v1. It is a curated distribution channel for packages that have source, fixtures, validation output, security review, and Status signatures.

## Repository Model

The primary source of truth is the `statusfoundry/status` repository:

- app, core, website, registry Worker, schemas, and documentation live in the main repository;
- official bundled plugins live under `plugins/bundled/`;
- examples and templates live under `plugins/examples/` and `status-plugin-example/`;
- generated app resources live under `Sources/StatusCore/Resources/BundledPlugins/`;
- generated website and registry metadata live under `web/src/generated/` and `workers/registry/src/`.

Official plugins start in the main repository so schema changes, fixtures, docs, registry metadata, and app behavior can be reviewed together.

The standalone template at `status-plugin-example/` is generated from the monorepo example. It is the recommended starting point for external authors who do not need the full app source. It may be mirrored to a separate repository later, but the canonical template source remains in the main repository.

## Organization Model

Use the `statusfoundry` GitHub organization for public source.

Recommended repository layout:

- `statusfoundry/status` — canonical app, website, registry, docs, schemas, bundled official plugins, examples, and CI;
- `statusfoundry/status-plugin-example` — optional mirror of `status-plugin-example/` for authors who want a small template repository;
- `statusfoundry/status-plugin-{provider}` — optional future repositories for large official plugins only when their fixture volume, release cycle, or maintainer team justifies separation.

Do not split every plugin into a separate repository by default. The monorepo keeps plugin schemas, app-owned view descriptors, fixture tests, website docs, registry metadata, and release packaging aligned.

## Licenses

Status is open source under the repository license. Official plugins should use the same license unless a provider-specific SDK, trademark rule, or contribution agreement requires a narrower license.

Third-party plugin pull requests must include license-compatible source and fixtures. Do not submit provider payloads that contain personal data, private customer data, non-redistributable samples, or secrets.

## Trust Levels

`official`
: Built or maintained by Status Foundry. Source, fixtures, docs, and registry metadata live in the Status source tree. Packages are signed by Status and published through the release workflow.

`verified-third-party`
: Submitted by an external maintainer and accepted after review. Status reviews the package, signs the approved artifact, publishes immutable R2 artifacts, and lists it in the hosted registry.

`local-dev`
: Installed manually through Developer Mode. It can be unsigned for local testing, is never listed in the hosted registry, and is never silently upgraded from registry packages.

## Submission Path

v1 uses pull requests, not direct uploads.

```txt
Fork or branch from statusfoundry/status
-> add or update plugin source files
-> add sanitized fixtures
-> update README setup and boundary docs
-> run local validation
-> open a pull request
-> CI validates package shape, docs, schemas, mappings, fixtures, and checksums
-> maintainer and security review
-> Status signs accepted package bytes
-> release workflow uploads immutable artifacts to R2
-> registry metadata points at the signed package
```

A public upload endpoint may be added later as an intake tool, but it must not publish directly to the installable registry. Review, signing, and registry metadata changes stay maintainer-controlled.

## Required Package Files

Every reviewed plugin must include:

- `manifest.json`;
- `setup.schema.json`;
- `auth.json`, when credentials or OAuth are required;
- `requests.json`;
- `mappings.json`;
- `fixtures/` with sanitized provider responses for mapping evidence;
- `triggers.json`;
- `events.json`;
- `views.json`;
- `rules.presets.json`;
- `actions.json`, only when a controlled write action is justified;
- `icon.svg` for official packages;
- `README.md` using `plugins/README.template.md`.

The README is published on the website and is part of review evidence. It must explain setup, credentials, declared domains, permissions, emitted events, actions, dashboard/detail views, limitations, and troubleshooting.

## Review Checklist

Maintainers should approve a plugin only when the review evidence proves:

- the package is declarative data only;
- every requested permission is necessary for a declared request or action;
- every domain is necessary and matches `requests.json` or auth endpoints;
- credentials use the app-owned credential store and never appear in fixtures, docs, registry metadata, or package source;
- OAuth packages use PKCE and public client IDs only;
- mappings normalize provider payloads into the common Status object model;
- fixtures cover every new or changed mapping path;
- emitted events have clear severity and notification defaults;
- suggested rules install disabled and are genuinely useful;
- write actions are limited, explicit, previewable where practical, and auditable;
- views use app-owned descriptors and do not attempt custom UI;
- documentation explains provider setup without requiring external product knowledge;
- `npm run plugins:validate-local -- <plugin-dir>` passes;
- `npm run plugins:check` passes when generated bundled artifacts are required;
- generated registry metadata and website docs are up to date.

## Signing And Publication

Accepted packages are signed by Status. The registry advertises only package versions that have:

- immutable package bytes;
- a SHA-256 package hash;
- a signature;
- a signing key ID;
- compatibility metadata;
- declared permissions and domains;
- reviewable source and documentation.

R2 package paths are immutable. Do not overwrite an existing package version. Publish a new version when package bytes change.

The app still verifies hash, signature, trusted key, compatibility, and revocation state locally before installing or updating. Registry filtering is a distribution guard, not the trust boundary.

## Revocation

Status can revoke:

- an entire plugin ID;
- a specific plugin version;
- a package hash;
- a signing key ID.

Revocation must be documented in release notes or a security advisory when user action is needed. The app checks revocation before install, before update, and periodically for installed packages.

## Third-Party Maintenance

Verified third-party maintainers can propose updates through pull requests. Maintainers should compare:

- permission changes;
- domain changes;
- action changes;
- fixture changes;
- event and rule default changes;
- setup/auth changes;
- README changes.

A third-party maintainer cannot self-publish into the registry in v1. Status signs and publishes only reviewed versions.
