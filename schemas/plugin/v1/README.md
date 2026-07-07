# Plugin Package Schemas v1

Formal JSON Schemas (draft 2020-12) for the declarative Status plugin package format described in `docs/04-plugin-system.md`. The plugin loader must validate every package file against these schemas before install (see WP-3.1 in `docs/13-implementation-plan.md`).

## Files

Each schema validates one file in a `.statusplugin` package:

```txt
manifest.schema.json       → manifest.json
auth.schema.json           → auth.json
setup.schema.json          → setup.schema.json
requests.schema.json       → requests.json
mappings.schema.json       → mappings.json
triggers.schema.json       → triggers.json
events.schema.json         → events.json
actions.schema.json        → actions.json
views.schema.json          → views.json
rules.presets.schema.json  → rules.presets.json
```

Not every plugin needs every file. `manifest.json` is always required.

## Schema identifiers

Every schema carries a stable `$id`:

```txt
https://plugins.status.app/schemas/plugin/v1/<name>.schema.json
```

## Versioning

Schemas are versioned by directory. This directory is `v1`.

- Backwards-compatible changes (new optional fields, new enum values) are made in place within `v1`.
- Breaking changes (removed fields, changed requirements, changed meaning) require a new `v2` directory with new `$id` URIs. `v1` stays frozen so existing packages keep validating.
- A plugin package targets exactly one schema version; the loader picks the schema set from the package format version implied by `minCoreVersion`.

## Unknown-field policy

Unknown fields fail validation. Every object in these schemas sets `additionalProperties: false` (or an explicit value schema). A field the schema does not know is a validation error, not a warning.

This is deliberate: a typo'd permission or a smuggled extra field must fail loudly at install time, not be silently ignored.

Deliberate exceptions, where the keys themselves are data:

- `requests.json`: `headers` and `query` maps (values must be strings).
- `mappings.json`: resource `fields` map (values must be selector strings).
- `rules.presets.json`: action step objects allow extra keys beyond `action`, because those keys are the action's input parameters (values must be strings, numbers, or booleans).

## Single source of truth for events

`events.json` is the only place a plugin declares the events it can emit. The manifest carries no event list — the earlier `capabilities.sources` field was removed to avoid two lists drifting apart. Event types referenced in `mappings.json` and `rules.presets.json` must be declared in `events.json`; the loader enforces this cross-file check beyond what JSON Schema can express.

## Expression strings are opaque here

Selector expressions (`$.attributes.name`), condition expressions (`when`), and template strings (`{{event.title}}`) are validated only as non-empty strings by these schemas. Their grammar is defined in `docs/16-mapping-language.md` and enforced by the mapping engine, not by JSON Schema.

## Auth types

v1 auth types:

```txt
none
api-key
bearer-token
basic-auth
jwt-api-key
private-key-jwt
```

`oauth2` is present in the schema enum so the format is stable, but it is deferred pending the OAuth decision in `docs/07-security-privacy.md` (WP-0.5). The loader should reject `oauth2` plugins until that decision lands.

## Cross-file checks the schemas do not cover

JSON Schema validates each file in isolation. The loader must additionally verify:

- every request URL host appears in the manifest `domains` list;
- every `request` reference (triggers, actions, mappings) names a key in `requests.json`;
- every event type in mappings and presets is declared in `events.json`;
- every `resourceType` (events, views) matches a resource mapping type;
- actions with `requiresWritePermission: true` have `write-actions` in the manifest permissions.
