import Foundation

public enum StatusDatabaseMigrator {
    public static let currentUserVersion = 7

    public static func migrate(_ database: SQLiteDatabase) throws {
        try database.executeBatch("""
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;
        PRAGMA synchronous = NORMAL;
        """)

        let userVersion = try database.query("PRAGMA user_version").first?["user_version"]
        let numericUserVersion = userVersion?.integerValue ?? 0
        guard numericUserVersion != currentUserVersion else {
            return
        }

        // Columns added after a table first shipped must exist before schemaV0
        // runs: CREATE TABLE IF NOT EXISTS skips pre-existing tables, so the
        // index definitions in schemaV0 would otherwise reference columns an
        // older table does not have. Each step checks live table state, not
        // the recorded version, so any historical database converges.
        try addColumnIfMissing(database, table: "plugin_versions", column: "signed_by", definition: "TEXT")
        try addColumnIfMissing(database, table: "plugins", column: "accent_color", definition: "TEXT")
        try addColumnIfMissing(database, table: "rules", column: "scope", definition: "TEXT NOT NULL DEFAULT 'plugin'")
        try addColumnIfMissing(database, table: "rules", column: "account_id", definition: "TEXT")
        try addColumnIfMissing(database, table: "notification_preferences", column: "account_id", definition: "TEXT")
        try database.executeBatch("DROP INDEX IF EXISTS idx_notification_preferences_event;")

        try database.executeBatch(schemaV0)
        try database.executeBatch("PRAGMA user_version = \(currentUserVersion);")
    }

    private static func addColumnIfMissing(
        _ database: SQLiteDatabase,
        table: String,
        column: String,
        definition: String
    ) throws {
        let columns = try database.query("PRAGMA table_info('\(table)')")
            .compactMap { row in row["name"]?.textValue }
        // An empty result means the table does not exist yet; schemaV0 will
        // create it with the current shape, so there is nothing to alter.
        guard columns.isEmpty == false else { return }
        guard columns.contains(column) == false else { return }
        try database.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private static let schemaV0 = """
    BEGIN TRANSACTION;

    CREATE TABLE IF NOT EXISTS plugins (
      id                TEXT PRIMARY KEY,
      name              TEXT NOT NULL,
      author            TEXT NOT NULL,
      description       TEXT NOT NULL,
      category          TEXT NOT NULL,
      icon_path         TEXT,
      accent_color      TEXT,
      trust_level       TEXT NOT NULL,
      installed_version TEXT NOT NULL,
      install_path      TEXT NOT NULL,
      enabled           INTEGER NOT NULL DEFAULT 1,
      installed_at      TEXT NOT NULL,
      updated_at        TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS plugin_versions (
      id               TEXT PRIMARY KEY,
      plugin_id        TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
      version          TEXT NOT NULL,
      min_core_version TEXT NOT NULL,
      platforms_json   TEXT NOT NULL,
      domains_json     TEXT NOT NULL,
      sha256           TEXT NOT NULL,
      signed_by        TEXT,
      signature        TEXT,
      manifest_json    TEXT NOT NULL,
      package_path     TEXT,
      revoked          INTEGER NOT NULL DEFAULT 0,
      installed_at     TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_plugin_versions_plugin_version ON plugin_versions (plugin_id, version);

    CREATE TABLE IF NOT EXISTS plugin_permissions (
      id         TEXT PRIMARY KEY,
      plugin_id  TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
      permission TEXT NOT NULL,
      granted    INTEGER NOT NULL DEFAULT 0,
      granted_at TEXT
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_plugin_permissions_plugin_permission ON plugin_permissions (plugin_id, permission);

    CREATE TABLE IF NOT EXISTS accounts (
      id                TEXT PRIMARY KEY,
      plugin_id         TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
      provider          TEXT NOT NULL,
      display_name      TEXT NOT NULL,
      auth_type         TEXT NOT NULL,
      credential_ref    TEXT,
      status            TEXT NOT NULL DEFAULT 'connected',
      last_error        TEXT,
      last_refreshed_at TEXT,
      created_at        TEXT NOT NULL,
      updated_at        TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_accounts_plugin ON accounts (plugin_id);

    CREATE TABLE IF NOT EXISTS resources (
      id            TEXT PRIMARY KEY,
      account_id    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      plugin_id     TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
      type          TEXT NOT NULL,
      external_id   TEXT NOT NULL,
      name          TEXT NOT NULL,
      fields_json   TEXT,
      action_url    TEXT,
      archived      INTEGER NOT NULL DEFAULT 0,
      first_seen_at TEXT NOT NULL,
      last_seen_at  TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_resources_account_type_external ON resources (account_id, type, external_id);
    CREATE INDEX IF NOT EXISTS idx_resources_account ON resources (account_id);

    CREATE TABLE IF NOT EXISTS account_resources (
      id          TEXT PRIMARY KEY,
      account_id  TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      resource_id TEXT NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
      tracked     INTEGER NOT NULL DEFAULT 1,
      sort_order  INTEGER,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_account_resources_account_resource ON account_resources (account_id, resource_id);

    CREATE TABLE IF NOT EXISTS resource_state_snapshots (
      resource_id TEXT PRIMARY KEY REFERENCES resources(id) ON DELETE CASCADE,
      state_json  TEXT NOT NULL,
      state_hash  TEXT NOT NULL,
      job_id      TEXT REFERENCES jobs(id) ON DELETE SET NULL,
      captured_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS events (
      id              TEXT PRIMARY KEY,
      provider        TEXT NOT NULL,
      type            TEXT NOT NULL,
      resource_id     TEXT NOT NULL,
      resource_name   TEXT NOT NULL,
      severity        TEXT NOT NULL,
      title           TEXT NOT NULL,
      summary         TEXT NOT NULL,
      timestamp       TEXT NOT NULL,
      action_url      TEXT,
      payload_json    TEXT,
      raw_payload_ref TEXT,
      fingerprint     TEXT NOT NULL,
      dedup_count     INTEGER NOT NULL DEFAULT 0,
      first_seen_at   TEXT NOT NULL,
      last_seen_at    TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_events_fingerprint ON events (fingerprint);
    CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events (timestamp);

    CREATE TABLE IF NOT EXISTS status_items (
      id               TEXT PRIMARY KEY,
      resource_id      TEXT NOT NULL,
      kind             TEXT NOT NULL,
      source_event_ids TEXT NOT NULL,
      incident_id      TEXT,
      severity         TEXT NOT NULL,
      title            TEXT NOT NULL,
      summary          TEXT NOT NULL,
      action_url       TEXT,
      state            TEXT NOT NULL,
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL,
      resolved_at      TEXT,
      snooze_until     TEXT,
      dismissed_reason TEXT,
      stuck            INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_status_items_state ON status_items (state);
    CREATE INDEX IF NOT EXISTS idx_status_items_resource ON status_items (resource_id);

    CREATE TABLE IF NOT EXISTS metrics (
      id          TEXT PRIMARY KEY,
      resource_id TEXT NOT NULL,
      label       TEXT NOT NULL,
      value       TEXT NOT NULL,
      delta       TEXT,
      severity    TEXT NOT NULL,
      updated_at  TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_metrics_resource ON metrics (resource_id);

    CREATE TABLE IF NOT EXISTS metric_points (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      metric_id   TEXT NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
      timestamp   TEXT NOT NULL,
      value       REAL NOT NULL,
      metadata_json TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_metric_points_metric_timestamp ON metric_points (metric_id, timestamp);

    CREATE TABLE IF NOT EXISTS triggers (
      id          TEXT PRIMARY KEY,
      plugin_id   TEXT NOT NULL,
      account_id  TEXT,
      type        TEXT NOT NULL,
      label       TEXT NOT NULL,
      enabled     INTEGER NOT NULL DEFAULT 1,
      schedule    TEXT,
      secret_ref  TEXT,
      metadata_json TEXT,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS jobs (
      id                TEXT PRIMARY KEY,
      plugin_id         TEXT NOT NULL,
      trigger_id        TEXT NOT NULL,
      account_id        TEXT,
      status            TEXT NOT NULL,
      started_at        TEXT,
      finished_at       TEXT,
      error             TEXT,
      emitted_event_ids TEXT,
      metadata_json     TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs (status);

    CREATE TABLE IF NOT EXISTS rules (
      id              TEXT PRIMARY KEY,
      name            TEXT NOT NULL,
      enabled         INTEGER NOT NULL DEFAULT 1,
      scope           TEXT NOT NULL DEFAULT 'plugin',
      account_id      TEXT,
      provider        TEXT,
      event_type      TEXT NOT NULL,
      conditions_json TEXT NOT NULL,
      actions_json    TEXT NOT NULL,
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_rules_event_type ON rules (event_type);
    CREATE INDEX IF NOT EXISTS idx_rules_account ON rules (account_id, enabled);

    CREATE TABLE IF NOT EXISTS action_runs (
      id          TEXT PRIMARY KEY,
      rule_id     TEXT,
      event_id    TEXT,
      action      TEXT NOT NULL,
      status      TEXT NOT NULL,
      input_json  TEXT NOT NULL,
      result_json TEXT,
      error       TEXT,
      started_at  TEXT NOT NULL,
      finished_at TEXT
    );

    CREATE TABLE IF NOT EXISTS notifications (
      id           TEXT PRIMARY KEY,
      event_id     TEXT,
      status_item_id TEXT,
      mode         TEXT NOT NULL,
      title        TEXT NOT NULL,
      body         TEXT NOT NULL,
      delivered_at TEXT,
      created_at   TEXT NOT NULL
    );

    \(notificationPreferencesSchema)

    CREATE TABLE IF NOT EXISTS audit_entries (
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL,
      detail      TEXT NOT NULL,
      timestamp   TEXT NOT NULL,
      status      TEXT NOT NULL,
      job_id      TEXT,
      event_id    TEXT,
      action_run_id TEXT,
      metadata_json TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_audit_entries_timestamp ON audit_entries (timestamp);

    CREATE TABLE IF NOT EXISTS sync_state (
      id             TEXT PRIMARY KEY,
      owner_type     TEXT NOT NULL,
      owner_id       TEXT NOT NULL,
      cursor         TEXT,
      last_success_at TEXT,
      last_failure_at TEXT,
      error          TEXT,
      metadata_json  TEXT
    );

    COMMIT;
    """

    private static let notificationPreferencesSchema = """
    CREATE TABLE IF NOT EXISTS notification_preferences (
      id         TEXT PRIMARY KEY,
      scope      TEXT NOT NULL,
      plugin_id  TEXT NOT NULL,
      account_id TEXT,
      event_type TEXT,
      mode       TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_preferences_plugin
      ON notification_preferences (plugin_id)
      WHERE scope = 'plugin';
    CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_preferences_plugin_event
      ON notification_preferences (plugin_id, event_type)
      WHERE scope = 'event' AND account_id IS NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_preferences_app
      ON notification_preferences (account_id)
      WHERE scope = 'app';
    CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_preferences_account_event
      ON notification_preferences (account_id, event_type)
      WHERE scope = 'event' AND account_id IS NOT NULL;
    """
}
