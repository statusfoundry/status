# Data Model

This document defines SQLite schema v0 for Status. It covers every table named in `docs/03-architecture.md`, the field lists in `docs/05-events-automation.md`, and the storage side of state-change detection. Event semantics (dedup, state transitions, StatusItem lifecycle) are defined in `docs/17-event-semantics.md`; this document defines where that data lives.

Schema v0 is the contract for WP-1.2 (persistence layer). Changes to it go through this document first.

## Database configuration

```txt
journal_mode = WAL
foreign_keys = ON
synchronous  = NORMAL
```

One database file per device, stored in the app support directory. The database contains no secrets (see Keychain references below).

## Conventions

### ID strategy

All primary keys are prefixed string IDs stored as TEXT:

```txt
<prefix>_<26-char lowercase ULID>
```

Example: `evt_01j9x4k2m3n5p7q9r1s3t5v7w9`.

Rationale:

- self-describing in logs, audit entries, and rule payloads — `evt_...` versus `job_...` is unambiguous at a glance, which matters for an app whose core promise is explainability;
- ULIDs sort by creation time, so ID ordering is stable and index-friendly;
- string IDs survive export, sync, and relay payloads without translation;
- the existing docs already use this shape (`evt_123` in `docs/05-events-automation.md`).

Prefixes:

```txt
plv_  plugin_versions
plp_  plugin_permissions
acc_  accounts
are_  account_resources
res_  resources
evt_  events
sti_  status_items
met_  metrics
trg_  triggers
job_  jobs
rul_  rules
arn_  action_runs
ntf_  notifications
aud_  audit_entries
syn_  sync_state
```

Two deliberate exceptions:

- `plugins.id` is the plugin's reverse-DNS manifest ID (`com.status.github`). It is already globally unique and human-readable; a surrogate would only add a lookup.
- `metric_points.id` is an INTEGER rowid. Metric points are the highest-volume table by far and carry no meaning individually; string IDs would roughly double row size for nothing.

### Timestamps

All timestamps are TEXT in ISO 8601 UTC with a trailing `Z`:

```txt
2026-07-07T12:00:00Z
```

Rationale: matches every example in the existing docs, sorts correctly as text, and is readable in the audit log and during debugging. Sub-second precision is allowed (`2026-07-07T12:00:00.123Z`) but not required. Local time never enters the database; conversion happens in the UI layer.

Column naming: `*_at` for moments (`created_at`, `delivered_at`). The one exception is `events.timestamp` and `audit_entries.timestamp`, which keep their names from `docs/05-events-automation.md`.

### JSON columns

Structured data that the schema does not need to query is stored as JSON text in columns suffixed `_json`. Rules:

- content must be valid JSON or the column is NULL — never an empty string;
- JSON columns are opaque to the schema; nothing joins on their contents;
- if a field inside a JSON column needs an index or a foreign key, it must be promoted to a real column in a migration.

One exception to the suffix: `jobs.emitted_event_ids` holds a JSON array of event IDs but keeps its exact name from `docs/05-events-automation.md`.

### Booleans

INTEGER, `0` or `1`, named as predicates (`enabled`, `granted`, `tracked`, `revoked`).

## Keychain references

Secrets are never stored in SQLite. This is a hard rule from `SPEC.md` and `docs/07-security-privacy.md`.

Any column that relates to a credential stores only an opaque Keychain reference string:

```txt
kc_<26-char lowercase ULID>
```

The reference is the lookup key for a Keychain item managed by the StatusCore credential wrapper (WP-1.3). The reference alone is useless without local Keychain access. Columns using this pattern:

```txt
accounts.credential_ref      the account's auth material (token, key, JWT inputs)
triggers.secret_ref          push trigger signing secret, when one exists
```

**No secret column exists anywhere in this schema.** No token, API key, password, private key, refresh token, or webhook signing secret is ever written to the database — only `kc_` references. Deleting an account must delete both the row and the referenced Keychain items.

## Migrations

Schema changes are ordered, named, forward-only migrations run by a migration runner in StatusCore (GRDB's `DatabaseMigrator` if GRDB is chosen; the contract below holds regardless of wrapper).

- Migrations have stable string identifiers (`v0-initial`, `v1-add-snooze`, ...). Applied migrations are recorded by the runner; a migration never runs twice.
- After each successful migration, the runner sets `PRAGMA user_version` to the count of applied migrations. This gives external tools a cheap version check without knowing the runner's bookkeeping.
- Migrations run at app launch before any other database access. A failed migration is fatal for that launch: report, do not limp along on a half-migrated schema.
- No down migrations in v1. Recovering from a bad migration means restoring the previous database file, which the runner backs up before applying migrations that follow an app update.
- Destructive migrations (dropping columns or tables that hold user data) require an explicit note in this document first.

Schema v0 is a single initial migration creating everything below.

## Implementation status

StatusCore currently includes a dependency-light SQLite foundation using the Apple SDK `SQLite3` module:

```txt
SQLiteDatabase
→ small statement/binding/query wrapper

StatusDatabaseMigrator
→ applies schema v0
→ sets PRAGMA user_version = 1

StatusPersistenceStore
→ first round-trip store for events, status items, and audit entries
```

This is an implementation starting point, not a rejection of GRDB. GRDB can still replace or wrap this layer later if it materially reduces persistence complexity. The schema contract in this document remains authoritative either way.

## Tables

Types shown are SQLite storage types. `NOT NULL` is stated explicitly; everything else is nullable.

### plugins

One row per installed plugin.

```sql
CREATE TABLE plugins (
  id                TEXT PRIMARY KEY,           -- reverse-DNS manifest id
  name              TEXT NOT NULL,
  author            TEXT NOT NULL,
  description       TEXT NOT NULL,
  category          TEXT NOT NULL,
  icon_path         TEXT,                       -- relative path inside install dir
  trust_level       TEXT NOT NULL,              -- official | verified-third-party | local-dev
  installed_version TEXT NOT NULL,              -- matches a plugin_versions.version
  install_path      TEXT NOT NULL,              -- app support directory location
  enabled           INTEGER NOT NULL DEFAULT 1,
  installed_at      TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
```

### plugin_versions

Every version of a plugin the app has installed or verified, including the package integrity data required by the install flow in `docs/04-plugin-system.md`.

```sql
CREATE TABLE plugin_versions (
  id               TEXT PRIMARY KEY,            -- plv_
  plugin_id        TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  version          TEXT NOT NULL,               -- semver string
  min_core_version TEXT NOT NULL,
  platforms_json   TEXT NOT NULL,               -- ["macOS","iOS"]
  domains_json     TEXT NOT NULL,               -- declared domains, enforced by request engine
  sha256           TEXT NOT NULL,
  signature        TEXT,                        -- NULL only for local-dev
  manifest_json    TEXT NOT NULL,               -- full manifest as installed
  package_path     TEXT,                        -- archived package location, if kept
  revoked          INTEGER NOT NULL DEFAULT 0,
  installed_at     TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_plugin_versions_plugin_version
  ON plugin_versions (plugin_id, version);
```

### plugin_permissions

Declared permissions and their grant state. Shown before install and during account setup.

```sql
CREATE TABLE plugin_permissions (
  id         TEXT PRIMARY KEY,                  -- plp_
  plugin_id  TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  permission TEXT NOT NULL,                     -- network | keychain | oauth | write-actions | ...
  granted    INTEGER NOT NULL DEFAULT 0,
  granted_at TEXT
);

CREATE UNIQUE INDEX idx_plugin_permissions_plugin_permission
  ON plugin_permissions (plugin_id, permission);
```

### accounts

A connected provider account. The credential lives in the Keychain; only the reference is stored.

```sql
CREATE TABLE accounts (
  id                TEXT PRIMARY KEY,           -- acc_
  plugin_id         TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  provider          TEXT NOT NULL,              -- e.g. appstoreconnect, github
  display_name      TEXT NOT NULL,
  auth_type         TEXT NOT NULL,              -- none | api-key | bearer-token | basic-auth | oauth2 | jwt-api-key | private-key-jwt
  credential_ref    TEXT,                       -- kc_ Keychain reference; NULL only when auth_type = none
  status            TEXT NOT NULL DEFAULT 'connected',  -- connected | error | expired | disconnected
  last_error        TEXT,                       -- user-facing summary of last auth/refresh failure
  last_refreshed_at TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

CREATE INDEX idx_accounts_plugin ON accounts (plugin_id);
```

### resources

A normalized thing inside an account: an app, a repository, a channel, a site.

```sql
CREATE TABLE resources (
  id            TEXT PRIMARY KEY,               -- res_
  account_id    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  plugin_id     TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  type          TEXT NOT NULL,                  -- plugin-declared resource type, e.g. app, repo
  external_id   TEXT NOT NULL,                  -- provider-side identifier
  name          TEXT NOT NULL,
  fields_json   TEXT,                           -- mapped extra fields (bundleId, sku, ...)
  action_url    TEXT,
  archived      INTEGER NOT NULL DEFAULT 0,     -- no longer returned by provider
  first_seen_at TEXT NOT NULL,
  last_seen_at  TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_resources_account_type_external
  ON resources (account_id, type, external_id);
CREATE INDEX idx_resources_account ON resources (account_id);
```

### account_resources

Per-account tracking configuration: which resources the user follows and how. Discovery writes `resources`; user choice lives here. A resource without a row here is known but untracked.

```sql
CREATE TABLE account_resources (
  id            TEXT PRIMARY KEY,               -- are_
  account_id    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  resource_id   TEXT NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
  tracked       INTEGER NOT NULL DEFAULT 1,
  sort_order    INTEGER,
  settings_json TEXT,                           -- per-resource overrides (thresholds, mute)
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_account_resources_pair
  ON account_resources (account_id, resource_id);
```

### resource_state_snapshots

The current provider-side state of each resource, as last mapped. This is the storage that state-change detection compares against: a poll maps the fresh payload, compares it to the stored snapshot, emits events for transitions, then overwrites the snapshot. Exactly one row per resource — this table holds current state, not history. What counts as relevant state per event type, and when snapshot comparison applies versus fingerprint dedup, is defined in `docs/17-event-semantics.md`.

```sql
CREATE TABLE resource_state_snapshots (
  resource_id TEXT PRIMARY KEY REFERENCES resources(id) ON DELETE CASCADE,
  state_json  TEXT NOT NULL,                    -- mapped state fields, plugin-defined shape
  state_hash  TEXT NOT NULL,                    -- hash of canonicalized state_json, for cheap comparison
  job_id      TEXT REFERENCES jobs(id) ON DELETE SET NULL,  -- the job that captured it
  captured_at TEXT NOT NULL
);
```

### events

A normalized thing that happened. Column names follow the event field list in `docs/05-events-automation.md` exactly; `account_id`, `job_id`, and `created_at` are additions for provenance.

```sql
CREATE TABLE events (
  id              TEXT PRIMARY KEY,             -- evt_
  provider        TEXT NOT NULL,
  type            TEXT NOT NULL,                -- e.g. app.review.rejected
  resource_id     TEXT REFERENCES resources(id) ON DELETE SET NULL,
  resource_name   TEXT,                         -- denormalized; survives resource deletion
  severity        TEXT NOT NULL,                -- ok | notice | warning | critical
  title           TEXT NOT NULL,
  summary         TEXT,
  timestamp       TEXT NOT NULL,                -- when it happened (ISO 8601 UTC)
  action_url      TEXT,
  payload_json    TEXT,                         -- mapped payload available to rules
  raw_payload_ref TEXT,                         -- reference to raw payload on disk, if retained
  fingerprint     TEXT NOT NULL,                -- dedup key, spec in docs/17-event-semantics.md
  initial_observation INTEGER NOT NULL DEFAULT 0, -- first sighting of a pre-existing state
  dedup_count     INTEGER NOT NULL DEFAULT 0,   -- suppressed duplicates attached to this event
  last_seen_at    TEXT,                         -- last time a duplicate was suppressed
  account_id      TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  job_id          TEXT REFERENCES jobs(id) ON DELETE SET NULL,
  created_at      TEXT NOT NULL                 -- when Status ingested it
);

CREATE UNIQUE INDEX idx_events_fingerprint ON events (fingerprint);
CREATE INDEX idx_events_resource_time ON events (resource_id, timestamp);
CREATE INDEX idx_events_type_time ON events (type, timestamp);
CREATE INDEX idx_events_timestamp ON events (timestamp);
```

The fingerprint index is unique; insertion of a duplicate fingerprint is the dedup mechanism. A suppressed duplicate increments `dedup_count` and updates `last_seen_at` on the original event. Collision handling is defined in `docs/17-event-semantics.md`.

### incidents

Open/close pairs of events (`website.down` / `website.recovered`) form incidents. The core owns all incident logic; semantics are in `docs/17-event-semantics.md`.

```sql
CREATE TABLE incidents (
  id                TEXT PRIMARY KEY,           -- inc_
  resource_id       TEXT REFERENCES resources(id) ON DELETE CASCADE,
  kind              TEXT NOT NULL,              -- pair identity, e.g. downtime
  state             TEXT NOT NULL DEFAULT 'open', -- open | closed
  opening_event_id  TEXT REFERENCES events(id) ON DELETE SET NULL,
  closing_event_id  TEXT REFERENCES events(id) ON DELETE SET NULL,
  observation_count INTEGER NOT NULL DEFAULT 1, -- observations attached while open
  opened_at         TEXT NOT NULL,
  last_observed_at  TEXT NOT NULL,
  closed_at         TEXT
);

CREATE INDEX idx_incidents_open ON incidents (resource_id, kind, state);
```

At most one open incident exists per (resource_id, kind); the application enforces this when opening.

### status_items

User-facing attention items derived from events or current state. Lifecycle semantics (auto-resolve, dismiss, snooze) are defined in `docs/17-event-semantics.md`; this is the storage.

```sql
CREATE TABLE status_items (
  id               TEXT PRIMARY KEY,            -- sti_
  plugin_id        TEXT REFERENCES plugins(id) ON DELETE SET NULL,
  account_id       TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  resource_id      TEXT REFERENCES resources(id) ON DELETE SET NULL,
  event_id         TEXT REFERENCES events(id) ON DELETE SET NULL,  -- originating event, if any
  incident_id      TEXT REFERENCES incidents(id) ON DELETE SET NULL, -- when backed by an incident
  kind             TEXT NOT NULL,               -- event | current-state
  event_type       TEXT,                        -- for kind = event; part of the one-open-item invariant
  severity         TEXT NOT NULL,               -- ok | notice | warning | critical
  state            TEXT NOT NULL DEFAULT 'open', -- open | snoozed | resolved | dismissed
  title            TEXT NOT NULL,
  summary          TEXT,
  action_url       TEXT,
  snoozed_until    TEXT,
  dismissed_reason TEXT,
  resolved_at      TEXT,
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
);

CREATE INDEX idx_status_items_state ON status_items (state, severity);
CREATE INDEX idx_status_items_resource ON status_items (resource_id);
CREATE UNIQUE INDEX idx_status_items_one_open
  ON status_items (resource_id, event_type)
  WHERE state = 'open' AND kind = 'event';
```

The partial unique index enforces the invariant from `docs/17-event-semantics.md`: at most one open item per (resource, event type). The `stuck` flag is derived from `updated_at` at read time, not stored.

### metrics

Metric definitions: one row per tracked series.

```sql
CREATE TABLE metrics (
  id          TEXT PRIMARY KEY,                 -- met_
  plugin_id   TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  account_id  TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  resource_id TEXT REFERENCES resources(id) ON DELETE CASCADE,
  key         TEXT NOT NULL,                    -- e.g. views_28d, open_issues
  label       TEXT NOT NULL,
  unit        TEXT,                             -- e.g. count, ms, percent
  kind        TEXT NOT NULL DEFAULT 'gauge',    -- gauge | counter | delta
  created_at  TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_metrics_resource_key ON metrics (resource_id, key);
```

### metric_points

Time-series values. Integer rowid primary key by design (see ID strategy).

```sql
CREATE TABLE metric_points (
  id        INTEGER PRIMARY KEY,                -- rowid
  metric_id TEXT NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
  timestamp TEXT NOT NULL,                      -- measurement moment (ISO 8601 UTC)
  value     REAL NOT NULL
);

CREATE UNIQUE INDEX idx_metric_points_metric_time
  ON metric_points (metric_id, timestamp);
```

### triggers

Configured trigger instances: a plugin-declared trigger bound to an account with a user-adjustable schedule and scheduler state.

```sql
CREATE TABLE triggers (
  id                TEXT PRIMARY KEY,           -- trg_
  plugin_id         TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  account_id        TEXT REFERENCES accounts(id) ON DELETE CASCADE,  -- NULL for account-less plugins
  plugin_trigger_id TEXT NOT NULL,              -- id from the plugin's triggers.json, e.g. poll_apps
  type              TEXT NOT NULL,              -- cron | manual | push | event | app-lifecycle
  schedule          TEXT,                       -- cron expression or interval; NULL for non-cron types
  enabled           INTEGER NOT NULL DEFAULT 1,
  config_json       TEXT,                       -- type-specific config (push path, event filter)
  secret_ref        TEXT,                       -- kc_ Keychain reference for push signing secret
  last_run_at       TEXT,
  next_run_at       TEXT,                       -- scheduler's computed next fire time
  backoff_until     TEXT,                       -- set after repeated failures
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_triggers_binding
  ON triggers (plugin_id, account_id, plugin_trigger_id);
CREATE INDEX idx_triggers_next_run ON triggers (enabled, next_run_at);
```

### jobs

One execution attempt. Column names follow the job field list in `docs/05-events-automation.md` exactly; `attempt` and `created_at` are additions for retries and queue ordering.

```sql
CREATE TABLE jobs (
  id                TEXT PRIMARY KEY,           -- job_
  plugin_id         TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  trigger_id        TEXT REFERENCES triggers(id) ON DELETE SET NULL,
  account_id        TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  status            TEXT NOT NULL DEFAULT 'queued',  -- queued | running | success | failed | cancelled | skipped
  started_at        TEXT,
  finished_at       TEXT,
  error             TEXT,                       -- user-facing error summary
  emitted_event_ids TEXT,                       -- JSON array of evt_ ids (name kept from docs/05)
  metadata_json     TEXT,                       -- error code, retry eligibility, request stats
  attempt           INTEGER NOT NULL DEFAULT 1,
  created_at        TEXT NOT NULL               -- when queued
);

CREATE INDEX idx_jobs_status ON jobs (status, created_at);
CREATE INDEX idx_jobs_trigger ON jobs (trigger_id, created_at);
```

### rules

Automation definitions. The when/if/then structure from `docs/05-events-automation.md` is stored as JSON because it is evaluated, not queried.

```sql
CREATE TABLE rules (
  id                TEXT PRIMARY KEY,           -- rul_
  name              TEXT NOT NULL,
  enabled           INTEGER NOT NULL DEFAULT 1,
  when_json         TEXT NOT NULL,              -- { "eventType": ..., "provider": ... }
  if_json           TEXT,                       -- conditions array; NULL = no conditions
  then_json         TEXT NOT NULL,              -- actions array
  source            TEXT NOT NULL DEFAULT 'user',  -- user | preset
  plugin_id         TEXT REFERENCES plugins(id) ON DELETE SET NULL,  -- preset origin
  last_triggered_at TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);

CREATE INDEX idx_rules_enabled ON rules (enabled);
```

### action_runs

One execution of one action, whether triggered by a rule or run manually.

```sql
CREATE TABLE action_runs (
  id          TEXT PRIMARY KEY,                 -- arn_
  rule_id     TEXT REFERENCES rules(id) ON DELETE SET NULL,      -- NULL for manual actions
  event_id    TEXT REFERENCES events(id) ON DELETE SET NULL,
  job_id      TEXT REFERENCES jobs(id) ON DELETE SET NULL,       -- job that performed the action, if any
  action_type TEXT NOT NULL,                    -- e.g. notification.show, jira.createIssue
  status      TEXT NOT NULL DEFAULT 'queued',   -- queued | running | success | failed | cancelled
  input_json  TEXT,                             -- resolved templated inputs
  result_json TEXT,                             -- e.g. created issue key and URL
  error       TEXT,
  started_at  TEXT,
  finished_at TEXT,
  created_at  TEXT NOT NULL
);

CREATE INDEX idx_action_runs_rule ON action_runs (rule_id, created_at);
CREATE INDEX idx_action_runs_event ON action_runs (event_id);
```

### notifications

Column names follow the notification field list in `docs/05-events-automation.md` exactly; `created_at` is an addition for ordering and retention.

```sql
CREATE TABLE notifications (
  id           TEXT PRIMARY KEY,                -- ntf_
  event_id     TEXT REFERENCES events(id) ON DELETE SET NULL,
  rule_id      TEXT REFERENCES rules(id) ON DELETE SET NULL,
  title        TEXT NOT NULL,
  body         TEXT,
  mode         TEXT NOT NULL,                   -- immediate | digest | dashboard-only | silent-automation | disabled
  delivered_at TEXT,                            -- NULL until delivered (digest queue)
  dismissed_at TEXT,
  action_url   TEXT,
  created_at   TEXT NOT NULL
);

CREATE INDEX idx_notifications_undelivered ON notifications (mode, delivered_at);
CREATE INDEX idx_notifications_event ON notifications (event_id);
```

### audit_entries

Column names follow the audit field list in `docs/05-events-automation.md` exactly. `action_id` is interpreted as the reference to the action run it records; `action_type` is the action identifier string.

```sql
CREATE TABLE audit_entries (
  id          TEXT PRIMARY KEY,                 -- aud_
  rule_id     TEXT REFERENCES rules(id) ON DELETE SET NULL,
  event_id    TEXT REFERENCES events(id) ON DELETE SET NULL,
  action_id   TEXT REFERENCES action_runs(id) ON DELETE SET NULL,  -- the action run this entry records
  action_type TEXT NOT NULL,                    -- e.g. jira.createIssue
  status      TEXT NOT NULL,                    -- success | failed | cancelled
  input_json  TEXT,
  result_json TEXT,
  error       TEXT,
  timestamp   TEXT NOT NULL
);

CREATE INDEX idx_audit_entries_time ON audit_entries (timestamp);
CREATE INDEX idx_audit_entries_rule ON audit_entries (rule_id, timestamp);
```

Foreign keys use `ON DELETE SET NULL` deliberately: audit entries must survive deletion of the rule, event, or action run they describe. The denormalized `action_type`, `input_json`, and `result_json` keep the entry readable on its own.

### sync_state

Non-secret incremental sync bookkeeping: cursors, etags, last-seen markers, pagination tokens. Never credentials — a sync token that grants access is a secret and belongs in the Keychain via a reference.

```sql
CREATE TABLE sync_state (
  id         TEXT PRIMARY KEY,                  -- syn_
  plugin_id  TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
  account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
  key        TEXT NOT NULL,                     -- e.g. list_apps.cursor, feed.etag
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_sync_state_scope_key
  ON sync_state (plugin_id, account_id, key);
```

## Field coverage against docs/05

Every field list in `docs/05-events-automation.md` is covered by name:

```txt
jobs          id, plugin_id, trigger_id, account_id, status, started_at,
              finished_at, error, emitted_event_ids, metadata_json
events        id, provider, type, resource_id, resource_name, severity, title,
              summary, timestamp, action_url, payload_json, raw_payload_ref,
              fingerprint
notifications id, event_id, rule_id, title, body, mode, delivered_at,
              dismissed_at, action_url
audit_entries id, rule_id, event_id, action_id, action_type, status,
              input_json, result_json, error, timestamp
```

No field was renamed or dropped. Added columns (`created_at`, `attempt`, `account_id`/`job_id` on events) are provenance and bookkeeping only.

## Retention

Retention is enforced by a periodic maintenance job (itself a job in the pipeline, so pruning is auditable). Defaults, user-adjustable later:

```txt
events          keep 90 days; always keep events referenced by an open
                status item or an undelivered notification
metric_points   keep raw points 90 days per metric; downsampling is a later
                concern, not v0
jobs            keep 14 days; always keep the most recent job per trigger so
                "last run" is always answerable
audit_entries   keep 365 days; the audit log is a product promise, prune last
                and most conservatively
notifications   keep 90 days after delivery or dismissal
incidents       keep closed incidents 90 days; open incidents are never pruned
```

`resources`, `accounts`, `rules`, `plugins`, and `sync_state` are configuration and current state; they are not pruned, only deleted by user action. `resource_state_snapshots` holds one row per resource and needs no retention.

Pruning respects foreign keys: an event is only deleted once nothing active references it; `ON DELETE SET NULL` on audit and notification references means history never blocks pruning.

## Mapping to SPEC.md objects

```txt
Plugin       plugins + plugin_versions + plugin_permissions
Account      accounts
Resource     resources + account_resources + resource_state_snapshots
Event        events
StatusItem   status_items
Metric       metrics + metric_points
ActionLink   action_url columns on resources, events, status_items,
             notifications (a value, not a table)
Rule         rules
ActionRun    action_runs
Notification notifications
AuditEntry   audit_entries
```

Triggers, jobs, and sync_state are execution machinery from `docs/03-architecture.md` rather than user-facing objects, and are modeled as their own tables above.
