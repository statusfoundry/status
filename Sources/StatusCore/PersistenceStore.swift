import Foundation

public final class StatusPersistenceStore {
    private let database: SQLiteDatabase
    private let stateEncoder = JSONEncoder()
    private let stateDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(database: SQLiteDatabase) {
        self.database = database
        self.stateEncoder.outputFormatting = [.sortedKeys]
    }

    public func insertEvent(_ event: Event) throws {
        let timestamp = ISO8601.string(from: event.timestamp)
        try database.execute(
            """
            INSERT OR REPLACE INTO events
            (id, provider, type, resource_id, resource_name, severity, title, summary, timestamp, action_url, fingerprint, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.id),
                .text(event.provider),
                .text(event.type),
                .text(event.resourceID),
                .text(event.resourceName),
                .text(event.severity.rawValue),
                .text(event.title),
                .text(event.summary),
                .text(timestamp),
                event.actionURL.map { .text($0.absoluteString) } ?? .null,
                .text(event.fingerprint),
                .text(timestamp),
                .text(timestamp)
            ]
        )
    }

    public func event(id: String) throws -> Event? {
        guard let row = try database.query("SELECT * FROM events WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try event(from: row)
    }

    public func event(fingerprint: String) throws -> Event? {
        guard let row = try database.query("SELECT * FROM events WHERE fingerprint = ?", bindings: [.text(fingerprint)]).first else {
            return nil
        }
        return try event(from: row)
    }

    public func incrementDedupCount(fingerprint: String, seenAt: Date) throws {
        try database.execute(
            """
            UPDATE events
            SET dedup_count = dedup_count + 1,
                last_seen_at = ?
            WHERE fingerprint = ?
            """,
            bindings: [
                .text(ISO8601.string(from: seenAt)),
                .text(fingerprint)
            ]
        )
    }

    public func dedupCount(fingerprint: String) throws -> Int {
        guard let row = try database.query("SELECT dedup_count FROM events WHERE fingerprint = ?", bindings: [.text(fingerprint)]).first else {
            return 0
        }
        guard case .integer(let count)? = row["dedup_count"] else {
            return 0
        }
        return Int(count)
    }

    private func event(from row: [String: SQLiteValue]) throws -> Event {
        return try Event(
            id: row.requiredText("id"),
            provider: row.requiredText("provider"),
            type: row.requiredText("type"),
            resourceID: row.requiredText("resource_id"),
            resourceName: row.requiredText("resource_name"),
            severity: Severity(rawValue: row.requiredText("severity")) ?? .notice,
            title: row.requiredText("title"),
            summary: row.requiredText("summary"),
            timestamp: ISO8601.date(from: row.requiredText("timestamp")),
            actionURL: row.optionalURL("action_url"),
            fingerprint: row.requiredText("fingerprint")
        )
    }

    public func insertStatusItem(_ item: StatusItem) throws {
        let updatedAt = ISO8601.string(from: item.updatedAt)
        try database.execute(
            """
            INSERT OR REPLACE INTO status_items
            (id, resource_id, kind, source_event_ids, severity, title, summary, action_url, state, created_at, updated_at, resolved_at, snooze_until, dismissed_reason, stuck)
            VALUES (?, ?, 'event', '[]', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(item.id),
                .text(item.resourceID),
                .text(item.severity.rawValue),
                .text(item.title),
                .text(item.summary),
                item.actionLink.map { .text($0.url.absoluteString) } ?? .null,
                .text(item.state.rawValue),
                .text(updatedAt),
                .text(updatedAt),
                item.resolvedAt.map { .text(ISO8601.string(from: $0)) } ?? .null,
                item.snoozeUntil.map { .text(ISO8601.string(from: $0)) } ?? .null,
                item.dismissedReason.map { .text($0) } ?? .null,
                .integer(item.stuck ? 1 : 0)
            ]
        )
    }

    public func upsertEventBackedStatusItem(for event: Event) throws -> StatusItem {
        if let existing = try openEventBackedStatusItem(resourceID: event.resourceID, eventType: event.type) {
            let sourceEventIDs = existing.sourceEventIDs + [event.id]
            let updatedAt = ISO8601.string(from: event.timestamp)
            try database.execute(
                """
                UPDATE status_items
                SET source_event_ids = ?,
                    severity = ?,
                    title = ?,
                    summary = ?,
                    action_url = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                bindings: [
                    .text(try jsonString(sourceEventIDs)),
                    .text(event.severity.rawValue),
                    .text(event.title),
                    .text(event.summary),
                    event.actionURL.map { .text($0.absoluteString) } ?? .null,
                    .text(updatedAt),
                    .text(existing.item.id)
                ]
            )
            return try statusItem(id: existing.item.id) ?? existing.item
        }

        let item = StatusItem(
            id: statusItemID(for: event),
            resourceID: event.resourceID,
            severity: event.severity,
            title: event.title,
            summary: event.summary,
            state: .open,
            updatedAt: event.timestamp,
            actionLink: event.actionURL.map { ActionLink(id: "act_\(event.id)", label: "Open", url: $0) }
        )
        let updatedAt = ISO8601.string(from: item.updatedAt)
        try database.execute(
            """
            INSERT OR REPLACE INTO status_items
            (id, resource_id, kind, source_event_ids, severity, title, summary, action_url, state, created_at, updated_at, resolved_at, snooze_until, dismissed_reason, stuck)
            VALUES (?, ?, 'event', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(item.id),
                .text(item.resourceID),
                .text(try jsonString([event.id])),
                .text(item.severity.rawValue),
                .text(item.title),
                .text(item.summary),
                item.actionLink.map { .text($0.url.absoluteString) } ?? .null,
                .text(item.state.rawValue),
                .text(updatedAt),
                .text(updatedAt),
                .null,
                .null,
                .null,
                .integer(0)
            ]
        )
        return item
    }

    public func statusItem(id: String) throws -> StatusItem? {
        guard let row = try database.query("SELECT * FROM status_items WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try statusItem(from: row)
    }

    public func statusItems(limit: Int = 20) throws -> [StatusItem] {
        try database.query(
            """
            SELECT * FROM status_items
            WHERE state IN ('open', 'snoozed')
            ORDER BY updated_at DESC, id ASC
            LIMIT ?
            """,
            bindings: [.integer(Int64(limit))]
        ).map(statusItem(from:))
    }

    public func resolveStatusItem(id: String, at date: Date) throws {
        try updateStatusItemLifecycle(
            id: id,
            state: .resolved,
            updatedAt: date,
            resolvedAt: date,
            snoozeUntil: nil,
            dismissedReason: nil
        )
    }

    public func snoozeStatusItem(id: String, until date: Date, at updatedAt: Date) throws {
        try updateStatusItemLifecycle(
            id: id,
            state: .snoozed,
            updatedAt: updatedAt,
            resolvedAt: nil,
            snoozeUntil: date,
            dismissedReason: nil
        )
    }

    public func dismissStatusItem(id: String, reason: String? = nil, at date: Date) throws {
        try updateStatusItemLifecycle(
            id: id,
            state: .dismissed,
            updatedAt: date,
            resolvedAt: date,
            snoozeUntil: nil,
            dismissedReason: reason
        )
    }

    @discardableResult
    public func resolveOpenEventBackedStatusItems(
        resourceID: String,
        eventType: String,
        at date: Date
    ) throws -> [StatusItem] {
        let rows = try database.query(
            """
            SELECT * FROM status_items
            WHERE resource_id = ?
              AND kind = 'event'
              AND state IN ('open', 'snoozed')
            ORDER BY updated_at ASC, id ASC
            """,
            bindings: [.text(resourceID)]
        )
        var resolved: [StatusItem] = []
        for row in rows {
            let sourceEventIDs = try optionalJSON([String].self, from: row.optionalText("source_event_ids")) ?? []
            guard let sourceEventID = sourceEventIDs.first,
                  let sourceEvent = try event(id: sourceEventID),
                  sourceEvent.type == eventType else {
                continue
            }
            let item = try statusItem(from: row)
            try resolveStatusItem(id: item.id, at: date)
            if let resolvedItem = try statusItem(id: item.id) {
                resolved.append(resolvedItem)
            }
        }
        return resolved
    }

    @discardableResult
    public func reopenExpiredSnoozedItems(at date: Date) throws -> [StatusItem] {
        let expired = try database.query(
            """
            SELECT * FROM status_items
            WHERE state = 'snoozed'
              AND snooze_until IS NOT NULL
              AND snooze_until <= ?
            ORDER BY updated_at ASC, id ASC
            """,
            bindings: [.text(ISO8601.string(from: date))]
        )
        .map(statusItem(from:))

        for item in expired {
            try updateStatusItemLifecycle(
                id: item.id,
                state: .open,
                updatedAt: date,
                resolvedAt: nil,
                snoozeUntil: nil,
                dismissedReason: nil
            )
        }
        return try expired.compactMap { try statusItem(id: $0.id) }
    }

    private func updateStatusItemLifecycle(
        id: String,
        state: StatusItemState,
        updatedAt: Date,
        resolvedAt: Date?,
        snoozeUntil: Date?,
        dismissedReason: String?
    ) throws {
        try database.execute(
            """
            UPDATE status_items
            SET state = ?,
                updated_at = ?,
                resolved_at = ?,
                snooze_until = ?,
                dismissed_reason = ?
            WHERE id = ?
            """,
            bindings: [
                .text(state.rawValue),
                .text(ISO8601.string(from: updatedAt)),
                resolvedAt.map { .text(ISO8601.string(from: $0)) } ?? .null,
                snoozeUntil.map { .text(ISO8601.string(from: $0)) } ?? .null,
                dismissedReason.map { .text($0) } ?? .null,
                .text(id)
            ]
        )
    }

    private func openEventBackedStatusItem(resourceID: String, eventType: String) throws -> (item: StatusItem, sourceEventIDs: [String])? {
        let rows = try database.query(
            """
            SELECT * FROM status_items
            WHERE resource_id = ?
              AND kind = 'event'
              AND state IN ('open', 'snoozed')
            ORDER BY updated_at DESC, id ASC
            """,
            bindings: [.text(resourceID)]
        )
        for row in rows {
            let sourceEventIDs = try optionalJSON([String].self, from: row.optionalText("source_event_ids")) ?? []
            guard let sourceEventID = sourceEventIDs.first,
                  let sourceEvent = try event(id: sourceEventID),
                  sourceEvent.type == eventType else {
                continue
            }
            return try (statusItem(from: row), sourceEventIDs)
        }
        return nil
    }

    private func statusItemID(for event: Event) -> String {
        if event.id.hasPrefix("evt_") {
            return "sti_" + event.id.dropFirst(4)
        }
        return "sti_" + event.id
    }

    public func insertAuditEntry(_ entry: AuditEntry) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO audit_entries
            (id, title, detail, timestamp, status, job_id, event_id, action_run_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(entry.id),
                .text(entry.title),
                .text(entry.detail),
                .text(ISO8601.string(from: entry.timestamp)),
                .text(entry.status),
                entry.jobID.map { .text($0) } ?? .null,
                entry.eventID.map { .text($0) } ?? .null,
                entry.actionRunID.map { .text($0) } ?? .null
            ]
        )
    }

    public func insertJobAuditEntry(for job: JobRecord, timestamp: Date) throws {
        try insertAuditEntry(
            AuditEntry(
                id: "aud_\(job.id)_\(job.status.rawValue)",
                title: jobAuditTitle(for: job.status),
                detail: jobAuditDetail(for: job),
                timestamp: timestamp,
                status: auditStatus(for: job.status),
                jobID: job.id,
                eventID: job.emittedEventIDs.count == 1 ? job.emittedEventIDs.first : nil
            )
        )
    }

    public func upsertActionRun(_ actionRun: ActionRunRecord) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO action_runs
            (id, rule_id, event_id, action, status, input_json, result_json, error, started_at, finished_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(actionRun.id),
                .text(actionRun.ruleID),
                .text(actionRun.eventID),
                .text(actionRun.action),
                .text(actionRun.status.rawValue),
                .text(try jsonString(actionRun.input)),
                .text(try jsonString(actionRun.result)),
                actionRun.error.map { .text($0) } ?? .null,
                .text(ISO8601.string(from: actionRun.startedAt)),
                actionRun.finishedAt.map { .text(ISO8601.string(from: $0)) } ?? .null
            ]
        )
    }

    public func actionRun(id: String) throws -> ActionRunRecord? {
        guard let row = try database.query("SELECT * FROM action_runs WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try actionRun(from: row)
    }

    public func upsertRule(_ rule: Rule, updatedAt: Date) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO rules
            (id, name, enabled, provider, event_type, conditions_json, actions_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, COALESCE((SELECT created_at FROM rules WHERE id = ?), ?), ?)
            """,
            bindings: [
                .text(rule.id),
                .text(rule.name),
                .integer(rule.enabled ? 1 : 0),
                rule.provider.map { .text($0) } ?? .null,
                .text(rule.eventType),
                .text(try jsonString(rule.conditions)),
                .text(try jsonString(rule.actions)),
                .text(rule.id),
                .text(ISO8601.string(from: updatedAt)),
                .text(ISO8601.string(from: updatedAt))
            ]
        )
    }

    public func rule(id: String) throws -> Rule? {
        guard let row = try database.query("SELECT * FROM rules WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try rule(from: row)
    }

    public func rules() throws -> [Rule] {
        try database.query("SELECT * FROM rules ORDER BY id").map(rule(from:))
    }

    public func rules(eventType: String) throws -> [Rule] {
        try database.query(
            "SELECT * FROM rules WHERE event_type = ? ORDER BY id",
            bindings: [.text(eventType)]
        ).map(rule(from:))
    }

    public func auditEntry(id: String) throws -> AuditEntry? {
        guard let row = try database.query("SELECT * FROM audit_entries WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try auditEntry(from: row)
    }

    public func auditEntries(limit: Int = 20) throws -> [AuditEntry] {
        try database.query(
            """
            SELECT * FROM audit_entries
            ORDER BY timestamp DESC, id ASC
            LIMIT ?
            """,
            bindings: [.integer(Int64(limit))]
        ).map(auditEntry(from:))
    }

    public func upsertAccount(_ account: Account, authType: String = "none", credentialRef: String? = nil, status: String = "connected", updatedAt: Date) throws {
        try database.execute(
            """
            INSERT INTO accounts
            (id, plugin_id, provider, display_name, auth_type, credential_ref, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              provider = excluded.provider,
              display_name = excluded.display_name,
              auth_type = excluded.auth_type,
              credential_ref = excluded.credential_ref,
              status = excluded.status,
              last_error = NULL,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(account.id),
                .text(account.pluginID),
                .text(account.provider),
                .text(account.displayName),
                .text(authType),
                credentialRef.map { .text($0) } ?? .null,
                .text(status),
                .text(ISO8601.string(from: updatedAt)),
                .text(ISO8601.string(from: updatedAt))
            ]
        )
    }

    public func account(id: String) throws -> Account? {
        guard let row = try database.query("SELECT * FROM accounts WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try account(from: row)
    }

    public func upsertAccountConfiguration(_ configuration: PluginAccountConfiguration, updatedAt: Date) throws {
        try upsertAccount(
            Account(
                id: configuration.id,
                pluginID: configuration.pluginID,
                provider: configuration.pluginID,
                displayName: configuration.accountName,
                authType: configuration.authType,
                credentialRef: configuration.credentialRef
            ),
            authType: configuration.authType,
            credentialRef: configuration.credentialRef,
            updatedAt: updatedAt
        )
        let metadata = try jsonString(AccountConfigurationMetadata(
            pluginID: configuration.pluginID,
            accountName: configuration.accountName,
            variables: configuration.variables
        ))
        try database.execute(
            """
            INSERT INTO sync_state
            (id, owner_type, owner_id, cursor, last_success_at, metadata_json)
            VALUES (?, 'account-configuration', ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              cursor = excluded.cursor,
              last_success_at = excluded.last_success_at,
              metadata_json = excluded.metadata_json,
              error = NULL
            """,
            bindings: [
                .text(accountConfigurationSyncID(configuration.id)),
                .text(configuration.id),
                .text(configuration.pluginID),
                .text(ISO8601.string(from: updatedAt)),
                .text(metadata)
            ]
        )
    }

    public func syncState(ownerType: String, ownerID: String) throws -> String? {
        try database.query(
            "SELECT cursor FROM sync_state WHERE id = ?",
            bindings: [.text(syncStateID(ownerType: ownerType, ownerID: ownerID))]
        ).first?.optionalText("cursor")
    }

    public func upsertSyncState(ownerType: String, ownerID: String, cursor: String?, updatedAt: Date, metadata: [String: String] = [:]) throws {
        try database.execute(
            """
            INSERT INTO sync_state
            (id, owner_type, owner_id, cursor, last_success_at, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              cursor = excluded.cursor,
              last_success_at = excluded.last_success_at,
              metadata_json = excluded.metadata_json,
              error = NULL
            """,
            bindings: [
                .text(syncStateID(ownerType: ownerType, ownerID: ownerID)),
                .text(ownerType),
                .text(ownerID),
                cursor.map { .text($0) } ?? .null,
                .text(ISO8601.string(from: updatedAt)),
                .text(try jsonString(metadata))
            ]
        )
    }

    public func accountConfiguration(accountID: String) throws -> PluginAccountConfiguration? {
        guard let row = try database.query(
            """
            SELECT a.plugin_id, a.display_name, a.auth_type, a.credential_ref, s.metadata_json
            FROM sync_state s
            JOIN accounts a ON a.id = s.owner_id
            WHERE s.id = ? AND s.owner_type = 'account-configuration'
            """,
            bindings: [.text(accountConfigurationSyncID(accountID))]
        ).first else {
            return nil
        }
        return try accountConfiguration(from: row, accountID: accountID)
    }

    public func accountConfigurations(pluginID: String) throws -> [PluginAccountConfiguration] {
        try database.query(
            """
            SELECT s.owner_id AS account_id, a.plugin_id, a.display_name, a.auth_type, a.credential_ref, s.metadata_json
            FROM sync_state s
            JOIN accounts a ON a.id = s.owner_id
            WHERE s.owner_type = 'account-configuration' AND a.plugin_id = ?
            ORDER BY a.display_name COLLATE NOCASE ASC
            """,
            bindings: [.text(pluginID)]
        ).map { row in
            try accountConfiguration(from: row, accountID: row.requiredText("account_id"))
        }
    }

    public func upsertResource(_ resource: Resource, externalID: String, fields: [String: String] = [:], seenAt: Date) throws {
        try database.execute(
            """
            INSERT INTO resources
            (id, account_id, plugin_id, type, external_id, name, fields_json, action_url, first_seen_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              fields_json = excluded.fields_json,
              action_url = excluded.action_url,
              archived = 0,
              last_seen_at = excluded.last_seen_at
            """,
            bindings: [
                .text(resource.id),
                .text(resource.accountID),
                .text(resource.pluginID),
                .text(resource.type),
                .text(externalID),
                .text(resource.name),
                .text(try jsonString(fields)),
                resource.actionURL.map { .text($0.absoluteString) } ?? .null,
                .text(ISO8601.string(from: seenAt)),
                .text(ISO8601.string(from: seenAt))
            ]
        )
        try database.execute(
            """
            INSERT INTO account_resources
            (id, account_id, resource_id, tracked, created_at, updated_at)
            VALUES (?, ?, ?, 1, ?, ?)
            ON CONFLICT(account_id, resource_id) DO UPDATE SET
              tracked = 1,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text("acr_\(resource.id.replacingOccurrences(of: ":", with: "_"))"),
                .text(resource.accountID),
                .text(resource.id),
                .text(ISO8601.string(from: seenAt)),
                .text(ISO8601.string(from: seenAt))
            ]
        )
    }

    public func resource(id: String) throws -> Resource? {
        guard let row = try database.query("SELECT * FROM resources WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try resource(from: row)
    }

    public func upsertResourceStateSnapshot(_ snapshot: ResourceStateSnapshot) throws {
        let stateJSON = try String(decoding: stateEncoder.encode(snapshot.state), as: UTF8.self)
        try database.execute(
            """
            INSERT OR REPLACE INTO resource_state_snapshots
            (resource_id, state_json, state_hash, job_id, captured_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(snapshot.resourceID),
                .text(stateJSON),
                .text(snapshot.stateHash),
                snapshot.jobID.map { .text($0) } ?? .null,
                .text(ISO8601.string(from: snapshot.capturedAt))
            ]
        )
    }

    public func resourceStateSnapshot(resourceID: String) throws -> ResourceStateSnapshot? {
        guard let row = try database.query(
            "SELECT * FROM resource_state_snapshots WHERE resource_id = ?",
            bindings: [.text(resourceID)]
        ).first else {
            return nil
        }

        let stateData = Data(try row.requiredText("state_json").utf8)
        let state = try stateDecoder.decode([String: String].self, from: stateData)
        return try ResourceStateSnapshot(
            resourceID: row.requiredText("resource_id"),
            state: state,
            stateHash: row.requiredText("state_hash"),
            jobID: row.optionalText("job_id"),
            capturedAt: ISO8601.date(from: row.requiredText("captured_at"))
        )
    }

    public func upsertTrigger(_ trigger: TriggerDefinition, updatedAt: Date) throws {
        let metadata = TriggerMetadata(
            requestID: trigger.requestID,
            failureCount: trigger.failureCount,
            lastRunAt: trigger.lastRunAt.map(ISO8601.string(from:)),
            nextRunAt: trigger.nextRunAt.map(ISO8601.string(from:))
        )
        try database.execute(
            """
            INSERT OR REPLACE INTO triggers
            (id, plugin_id, account_id, type, label, enabled, schedule, metadata_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE((SELECT created_at FROM triggers WHERE id = ?), ?), ?)
            """,
            bindings: [
                .text(trigger.id),
                .text(trigger.pluginID),
                trigger.accountID.map { .text($0) } ?? .null,
                .text(trigger.kind.rawValue),
                .text(trigger.label),
                .integer(trigger.enabled ? 1 : 0),
                trigger.intervalSeconds.map { .text(String($0)) } ?? .null,
                .text(try jsonString(metadata)),
                .text(trigger.id),
                .text(ISO8601.string(from: updatedAt)),
                .text(ISO8601.string(from: updatedAt))
            ]
        )
    }

    public func trigger(id: String) throws -> TriggerDefinition? {
        guard let row = try database.query("SELECT * FROM triggers WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try trigger(from: row)
    }

    public func triggers() throws -> [TriggerDefinition] {
        try database.query("SELECT * FROM triggers ORDER BY id").map(trigger(from:))
    }

    public func setTriggerEnabled(id: String, enabled: Bool, updatedAt: Date) throws {
        try database.execute(
            """
            UPDATE triggers
            SET enabled = ?, updated_at = ?
            WHERE id = ?
            """,
            bindings: [
                .integer(enabled ? 1 : 0),
                .text(ISO8601.string(from: updatedAt)),
                .text(id)
            ]
        )
    }

    public func upsertJob(_ job: JobRecord) throws {
        let metadata = JobMetadata(queuedAt: ISO8601.string(from: job.queuedAt))
        try database.execute(
            """
            INSERT OR REPLACE INTO jobs
            (id, plugin_id, trigger_id, account_id, status, started_at, finished_at, error, emitted_event_ids, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(job.id),
                .text(job.pluginID),
                .text(job.triggerID),
                job.accountID.map { .text($0) } ?? .null,
                .text(job.status.rawValue),
                job.startedAt.map { .text(ISO8601.string(from: $0)) } ?? .null,
                job.finishedAt.map { .text(ISO8601.string(from: $0)) } ?? .null,
                job.error.map { .text($0) } ?? .null,
                .text(try jsonString(job.emittedEventIDs)),
                .text(try jsonString(metadata))
            ]
        )
    }

    public func job(id: String) throws -> JobRecord? {
        guard let row = try database.query("SELECT * FROM jobs WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try job(from: row)
    }

    public func nextQueuedJob() throws -> JobRecord? {
        try database.query(
            """
            SELECT * FROM jobs
            WHERE status = ?
            """,
            bindings: [.text(JobStatus.queued.rawValue)]
        )
        .map(job(from:))
        .sorted { lhs, rhs in
            if lhs.queuedAt == rhs.queuedAt {
                return lhs.id < rhs.id
            }
            return lhs.queuedAt < rhs.queuedAt
        }
        .first
    }

    public func recentEvents(limit: Int = 20) throws -> [Event] {
        try database.query(
            """
            SELECT * FROM events
            ORDER BY timestamp DESC, id ASC
            LIMIT ?
            """,
            bindings: [.integer(Int64(limit))]
        ).map(event(from:))
    }

    public func metrics() throws -> [Metric] {
        try database.query("SELECT * FROM metrics ORDER BY label ASC").map(metric(from:))
    }

    public func upsertMetric(_ metric: Metric, updatedAt: Date) throws {
        try database.execute(
            """
            INSERT INTO metrics
            (id, resource_id, label, value, delta, severity, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              resource_id = excluded.resource_id,
              label = excluded.label,
              value = excluded.value,
              delta = excluded.delta,
              severity = excluded.severity,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(metric.id),
                .text(metric.resourceID),
                .text(metric.label),
                .text(metric.value),
                metric.delta.map { .text($0) } ?? .null,
                .text(metric.severity.rawValue),
                .text(ISO8601.string(from: updatedAt))
            ]
        )
    }

    public func insertMetricPoint(metricID: String, value: Double, timestamp: Date, metadata: [String: String] = [:]) throws {
        try database.execute(
            """
            INSERT INTO metric_points
            (metric_id, timestamp, value, metadata_json)
            VALUES (?, ?, ?, ?)
            """,
            bindings: [
                .text(metricID),
                .text(ISO8601.string(from: timestamp)),
                .double(value),
                .text(try jsonString(metadata))
            ]
        )
    }

    public func metricPoints(metricID: String) throws -> [(timestamp: Date, value: Double)] {
        try database.query(
            """
            SELECT timestamp, value FROM metric_points
            WHERE metric_id = ?
            ORDER BY timestamp ASC, id ASC
            """,
            bindings: [.text(metricID)]
        ).map { row in
            try (
                timestamp: ISO8601.date(from: row.requiredText("timestamp")),
                value: row.requiredDouble("value")
            )
        }
    }

    public func integrationSummaries() throws -> [IntegrationSummary] {
        try database.query(
            """
            SELECT id, provider, display_name, status, last_error, last_refreshed_at
            FROM accounts
            ORDER BY display_name ASC, id ASC
            """
        ).map(integrationSummary(from:))
    }

    public func dashboardSnapshot(now: Date = Date()) throws -> DashboardSnapshot {
        let items = try statusItems()
        let events = try recentEvents(limit: 10)
        let metrics = try metrics()
        let integrations = try integrationSummaries()
        let audit = try auditEntries(limit: 10)

        return DashboardSnapshot(
            headline: dashboardHeadline(statusItems: items, integrations: integrations),
            summary: dashboardSummary(
                statusItems: items,
                recentEvents: events,
                integrations: integrations,
                auditEntries: audit,
                now: now
            ),
            statusItems: items,
            recentEvents: events,
            metrics: metrics,
            integrations: integrations,
            auditEntries: audit
        )
    }

    public func installPlugin(_ record: PluginInstallRecord) throws {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: record.manifest))
        guard record.verification.pluginID == record.manifest.id else {
            throw PluginInstallationError.verificationPluginMismatch(
                expected: record.manifest.id,
                actual: record.verification.pluginID
            )
        }
        guard record.verification.version == record.manifest.version else {
            throw PluginInstallationError.verificationVersionMismatch(
                expected: record.manifest.version,
                actual: record.verification.version
            )
        }
        try database.execute(
            """
            INSERT OR REPLACE INTO plugins
            (id, name, author, description, category, icon_path, trust_level, installed_version, install_path, enabled, installed_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, COALESCE((SELECT installed_at FROM plugins WHERE id = ?), ?), ?)
            """,
            bindings: [
                .text(record.manifest.id),
                .text(record.manifest.name),
                .text(record.manifest.author),
                .text(record.manifest.description),
                .text(record.manifest.category),
                record.manifest.icon.map { .text($0) } ?? .null,
                .text(record.trustLevel.rawValue),
                .text(record.manifest.version),
                .text(record.installPath),
                .text(record.manifest.id),
                .text(ISO8601.string(from: record.installedAt)),
                .text(ISO8601.string(from: record.installedAt))
            ]
        )

        try database.execute(
            """
            INSERT OR REPLACE INTO plugin_versions
            (id, plugin_id, version, min_core_version, platforms_json, domains_json, sha256, signature, manifest_json, package_path, revoked, installed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """,
            bindings: [
                .text(pluginVersionID(pluginID: record.manifest.id, version: record.manifest.version)),
                .text(record.manifest.id),
                .text(record.manifest.version),
                .text(record.manifest.minCoreVersion),
                .text(try jsonString(record.manifest.platforms.map(\.rawValue))),
                .text(try jsonString(record.manifest.domains)),
                .text(record.verification.sha256),
                record.signature.map { .text($0) } ?? .null,
                .text(try jsonString(record.manifest)),
                record.packagePath.map { .text($0) } ?? .null,
                .text(ISO8601.string(from: record.installedAt))
            ]
        )

        for permission in record.manifest.permissions {
            try upsertPluginPermission(
                pluginID: record.manifest.id,
                permission: permission,
                granted: false,
                grantedAt: nil
            )
        }

        try installPluginPackageDefinition(
            record.packageDefinition,
            pluginID: record.manifest.id,
            installedAt: record.installedAt
        )
    }

    public func uninstallPlugin(id pluginID: String) throws {
        let rulePrefix = "rule_\(pluginID.replacingOccurrences(of: ".", with: "_"))_%"
        try database.execute(
            """
            DELETE FROM sync_state
            WHERE owner_type = 'account-configuration'
              AND owner_id IN (SELECT id FROM accounts WHERE plugin_id = ?)
            """,
            bindings: [.text(pluginID)]
        )
        try database.execute("DELETE FROM triggers WHERE plugin_id = ?", bindings: [.text(pluginID)])
        try database.execute(
            "DELETE FROM rules WHERE provider = ? OR id LIKE ?",
            bindings: [.text(pluginID), .text(rulePrefix)]
        )
        try database.execute("DELETE FROM plugins WHERE id = ?", bindings: [.text(pluginID)])
    }

    public func installedPlugin(id: String) throws -> InstalledPlugin? {
        guard let row = try database.query("SELECT * FROM plugins WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try installedPlugin(from: row)
    }

    public func installedPlugins() throws -> [InstalledPlugin] {
        try database.query("SELECT * FROM plugins ORDER BY name ASC, id ASC").map(installedPlugin(from:))
    }

    public func installedPluginVersions(pluginID: String) throws -> [InstalledPluginVersion] {
        try database.query(
            "SELECT * FROM plugin_versions WHERE plugin_id = ? ORDER BY installed_at DESC, version DESC",
            bindings: [.text(pluginID)]
        ).map(installedPluginVersion(from:))
    }

    public func pluginPermissions(pluginID: String) throws -> [InstalledPluginPermission] {
        try database.query(
            "SELECT * FROM plugin_permissions WHERE plugin_id = ? ORDER BY permission ASC",
            bindings: [.text(pluginID)]
        ).map(installedPluginPermission(from:))
    }

    public func setPluginPermission(pluginID: String, permission: PluginPermission, granted: Bool, grantedAt: Date?) throws {
        try database.execute(
            """
            INSERT INTO plugin_permissions
            (id, plugin_id, permission, granted, granted_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(plugin_id, permission) DO UPDATE SET
              granted = excluded.granted,
              granted_at = excluded.granted_at
            """,
            bindings: [
                .text(pluginPermissionID(pluginID: pluginID, permission: permission)),
                .text(pluginID),
                .text(permission.rawValue),
                .integer(granted ? 1 : 0),
                grantedAt.map { .text(ISO8601.string(from: $0)) } ?? .null
            ]
        )
    }

    public func statusItemCount() throws -> Int {
        try count("status_items")
    }

    public func auditEntryCount() throws -> Int {
        try count("audit_entries")
    }

    private func count(_ table: String) throws -> Int {
        guard let row = try database.query("SELECT COUNT(*) AS count FROM \(table)").first,
              case .integer(let count)? = row["count"] else {
            return 0
        }
        return Int(count)
    }

    private func upsertPluginPermission(pluginID: String, permission: PluginPermission, granted: Bool, grantedAt: Date?) throws {
        try database.execute(
            """
            INSERT OR IGNORE INTO plugin_permissions
            (id, plugin_id, permission, granted, granted_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(pluginPermissionID(pluginID: pluginID, permission: permission)),
                .text(pluginID),
                .text(permission.rawValue),
                .integer(granted ? 1 : 0),
                grantedAt.map { .text(ISO8601.string(from: $0)) } ?? .null
            ]
        )
    }

    private func pluginVersionID(pluginID: String, version: String) -> String {
        "plv_\(pluginID.replacingOccurrences(of: ".", with: "_"))_\(version.replacingOccurrences(of: ".", with: "_"))"
    }

    private func pluginPermissionID(pluginID: String, permission: PluginPermission) -> String {
        "plp_\(pluginID.replacingOccurrences(of: ".", with: "_"))_\(permission.rawValue.replacingOccurrences(of: "-", with: "_"))"
    }

    private func syncStateID(ownerType: String, ownerID: String) -> String {
        "sync_\(ownerType.replacingOccurrences(of: #"[^a-zA-Z0-9_]+"#, with: "_", options: .regularExpression))_\(ownerID.replacingOccurrences(of: #"[^a-zA-Z0-9_]+"#, with: "_", options: .regularExpression))"
    }

    private func installPluginPackageDefinition(_ definition: PluginPackageDefinition, pluginID: String, installedAt: Date) throws {
        for trigger in definition.triggers {
            try upsertTrigger(
                TriggerDefinition(
                    id: pluginScopedID(prefix: "trg", pluginID: pluginID, localID: trigger.id),
                    pluginID: pluginID,
                    kind: trigger.type,
                    label: trigger.label,
                    enabled: true,
                    intervalSeconds: trigger.defaultSchedule.flatMap(cronIntervalSeconds),
                    requestID: trigger.request
                ),
                updatedAt: installedAt
            )
        }

        for preset in definition.rulePresets {
            try upsertRule(
                Rule(
                    id: pluginScopedID(prefix: "rule", pluginID: pluginID, localID: preset.name),
                    name: preset.name,
                    enabled: false,
                    provider: preset.when.provider ?? pluginID,
                    eventType: preset.when.eventType,
                    conditions: preset.conditions.map {
                        RuleCondition(field: $0.field, operation: $0.operation, value: $0.value)
                    },
                    actions: preset.actions.map {
                        RuleActionDefinition(action: $0.action, parameters: $0.parameters)
                    }
                ),
                updatedAt: installedAt
            )
        }
    }

    private func pluginScopedID(prefix: String, pluginID: String, localID: String) -> String {
        let pluginPart = pluginID.replacingOccurrences(of: ".", with: "_")
        let localPart = localID
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "\(prefix)_\(pluginPart)_\(localPart.isEmpty ? "default" : localPart)"
    }

    private func cronIntervalSeconds(_ expression: String) -> TimeInterval? {
        let fields = expression.split(separator: " ")
        guard fields.count == 5 else { return nil }

        let minute = String(fields[0])
        if minute == "*" {
            return 60
        }
        if minute.hasPrefix("*/"), let minutes = Int(minute.dropFirst(2)), minutes > 0 {
            return TimeInterval(minutes * 60)
        }
        return nil
    }

    private func installedPlugin(from row: [String: SQLiteValue]) throws -> InstalledPlugin {
        let pluginID = try row.requiredText("id")
        let installedVersion = try row.requiredText("installed_version")
        return try InstalledPlugin(
            id: pluginID,
            name: row.requiredText("name"),
            author: row.requiredText("author"),
            description: row.requiredText("description"),
            category: row.requiredText("category"),
            iconPath: row.optionalText("icon_path"),
            trustLevel: PluginTrustLevel(rawValue: row.requiredText("trust_level")) ?? .localDev,
            installedVersion: installedVersion,
            installPath: row.requiredText("install_path"),
            enabled: row.optionalInteger("enabled") != 0,
            auth: installedPluginAuth(pluginID: pluginID, version: installedVersion),
            setup: installedPluginSetup(pluginID: pluginID, version: installedVersion),
            installedAt: ISO8601.date(from: row.requiredText("installed_at")),
            updatedAt: ISO8601.date(from: row.requiredText("updated_at"))
        )
    }

    private func installedPluginSetup(pluginID: String, version: String) -> PackagedPluginSetup? {
        installedPluginDefinition(pluginID: pluginID, version: version)?.setup
    }

    private func installedPluginAuth(pluginID: String, version: String) -> PackagedPluginAuth? {
        installedPluginDefinition(pluginID: pluginID, version: version)?.auth
    }

    private func installedPluginDefinition(pluginID: String, version: String) -> PluginPackageDefinition? {
        guard let row = try? database.query(
            """
            SELECT package_path FROM plugin_versions
            WHERE plugin_id = ? AND version = ?
            ORDER BY installed_at DESC
            LIMIT 1
            """,
            bindings: [.text(pluginID), .text(version)]
        ).first,
              let packagePath = row.optionalText("package_path"),
              let packageData = try? Data(contentsOf: URL(fileURLWithPath: packagePath)),
              let definition = try? PluginPackageDefinition.decode(from: packageData) else {
            return nil
        }
        return definition
    }

    private func installedPluginVersion(from row: [String: SQLiteValue]) throws -> InstalledPluginVersion {
        let platformStrings = try optionalJSON([String].self, from: row.optionalText("platforms_json")) ?? []
        let platforms = platformStrings.compactMap(PluginPlatform.init(rawValue:))
        let domains = try optionalJSON([String].self, from: row.optionalText("domains_json")) ?? []
        let manifest = try optionalJSON(PluginManifest.self, from: row.optionalText("manifest_json")) ?? PluginManifest(
            id: row.requiredText("plugin_id"),
            name: row.requiredText("plugin_id"),
            version: row.requiredText("version"),
            author: "Unknown",
            category: "unknown",
            description: "Missing manifest",
            minCoreVersion: row.requiredText("min_core_version"),
            platforms: platforms,
            permissions: [],
            domains: domains
        )
        return try InstalledPluginVersion(
            id: row.requiredText("id"),
            pluginID: row.requiredText("plugin_id"),
            version: row.requiredText("version"),
            minCoreVersion: row.requiredText("min_core_version"),
            platforms: platforms,
            domains: domains,
            sha256: row.requiredText("sha256"),
            signature: row.optionalText("signature"),
            manifest: manifest,
            packagePath: row.optionalText("package_path"),
            revoked: row.optionalInteger("revoked") != 0,
            installedAt: ISO8601.date(from: row.requiredText("installed_at"))
        )
    }

    private func installedPluginPermission(from row: [String: SQLiteValue]) throws -> InstalledPluginPermission {
        try InstalledPluginPermission(
            id: row.requiredText("id"),
            pluginID: row.requiredText("plugin_id"),
            permission: PluginPermission(rawValue: row.requiredText("permission")) ?? .network,
            granted: row.optionalInteger("granted") != 0,
            grantedAt: try row.optionalText("granted_at").map(ISO8601.date(from:))
        )
    }

    private func account(from row: [String: SQLiteValue]) throws -> Account {
        try Account(
            id: row.requiredText("id"),
            pluginID: row.requiredText("plugin_id"),
            provider: row.requiredText("provider"),
            displayName: row.requiredText("display_name"),
            authType: row.optionalText("auth_type") ?? "none",
            credentialRef: row.optionalText("credential_ref")
        )
    }

    private func accountConfiguration(from row: [String: SQLiteValue], accountID: String) throws -> PluginAccountConfiguration {
        let metadata = try optionalJSON(AccountConfigurationMetadata.self, from: row.optionalText("metadata_json"))
        return try PluginAccountConfiguration(
            id: accountID,
            pluginID: metadata?.pluginID ?? row.requiredText("plugin_id"),
            accountName: metadata?.accountName ?? row.requiredText("display_name"),
            variables: metadata?.variables ?? [:],
            authType: row.optionalText("auth_type") ?? "none",
            credentialRef: row.optionalText("credential_ref")
        )
    }

    private func statusItem(from row: [String: SQLiteValue]) throws -> StatusItem {
        let actionURL = row.optionalURL("action_url")
        return try StatusItem(
            id: row.requiredText("id"),
            resourceID: row.requiredText("resource_id"),
            severity: Severity(rawValue: row.requiredText("severity")) ?? .notice,
            title: row.requiredText("title"),
            summary: row.requiredText("summary"),
            state: StatusItemState(rawValue: row.requiredText("state")) ?? .open,
            updatedAt: ISO8601.date(from: row.requiredText("updated_at")),
            resolvedAt: try row.optionalText("resolved_at").map(ISO8601.date(from:)),
            snoozeUntil: try row.optionalText("snooze_until").map(ISO8601.date(from:)),
            dismissedReason: row.optionalText("dismissed_reason"),
            stuck: row.optionalInteger("stuck") == 1,
            actionLink: actionURL.map { ActionLink(id: "open", label: "Open", url: $0) }
        )
    }

    private func auditEntry(from row: [String: SQLiteValue]) throws -> AuditEntry {
        return try AuditEntry(
            id: row.requiredText("id"),
            title: row.requiredText("title"),
            detail: row.requiredText("detail"),
            timestamp: ISO8601.date(from: row.requiredText("timestamp")),
            status: row.requiredText("status"),
            jobID: row.optionalText("job_id"),
            eventID: row.optionalText("event_id"),
            actionRunID: row.optionalText("action_run_id")
        )
    }

    private func metric(from row: [String: SQLiteValue]) throws -> Metric {
        try Metric(
            id: row.requiredText("id"),
            resourceID: row.requiredText("resource_id"),
            label: row.requiredText("label"),
            value: row.requiredText("value"),
            delta: row.optionalText("delta"),
            severity: Severity(rawValue: row.requiredText("severity")) ?? .notice
        )
    }

    private func resource(from row: [String: SQLiteValue]) throws -> Resource {
        try Resource(
            id: row.requiredText("id"),
            accountID: row.requiredText("account_id"),
            pluginID: row.requiredText("plugin_id"),
            type: row.requiredText("type"),
            name: row.requiredText("name"),
            actionURL: row.optionalURL("action_url")
        )
    }

    private func integrationSummary(from row: [String: SQLiteValue]) throws -> IntegrationSummary {
        let lastError = row.optionalText("last_error")
        let status = try row.requiredText("status")
        let severity: Severity = if lastError?.isEmpty == false {
            .warning
        } else if status == "connected" {
            .ok
        } else {
            .notice
        }
        return try IntegrationSummary(
            id: row.requiredText("id"),
            name: row.requiredText("display_name"),
            provider: row.requiredText("provider"),
            state: lastError?.isEmpty == false ? "Needs attention" : status.capitalized,
            severity: severity,
            lastSyncDescription: lastRefreshDescription(row.optionalText("last_refreshed_at"))
        )
    }

    private func dashboardHeadline(statusItems: [StatusItem], integrations: [IntegrationSummary]) -> String {
        let criticalCount = statusItems.filter { $0.severity == .critical }.count
        if criticalCount == 1 {
            return "1 critical item"
        }
        if criticalCount > 1 {
            return "\(criticalCount) critical items"
        }

        let attentionCount = statusItems.filter { $0.severity >= .warning }.count
        if attentionCount == 1 {
            return "1 item needs attention"
        }
        if attentionCount > 1 {
            return "\(attentionCount) items need attention"
        }
        if integrations.isEmpty {
            return "All clear"
        }
        return "Everything tracked is okay"
    }

    private func dashboardSummary(
        statusItems: [StatusItem],
        recentEvents: [Event],
        integrations: [IntegrationSummary],
        auditEntries: [AuditEntry],
        now: Date
    ) -> String {
        if statusItems.isEmpty, recentEvents.isEmpty, integrations.isEmpty, auditEntries.isEmpty {
            return "No tracked events or integrations are stored on this device yet."
        }

        let openCount = statusItems.count
        let integrationCount = integrations.count
        let eventCount = recentEvents.count
        if openCount == 0 {
            return "\(integrationCount) integrations tracked, \(eventCount) recent events, no open attention items."
        }

        let newest = statusItems.map(\.updatedAt).max() ?? now
        return "\(openCount) open attention items across \(integrationCount) integrations. Newest update: \(lastRefreshDescription(ISO8601.string(from: newest)))."
    }

    private func lastRefreshDescription(_ isoDate: String?) -> String {
        guard let isoDate, let date = try? ISO8601.date(from: isoDate) else {
            return "Never synced"
        }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "Just now"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hr ago"
        }
        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    private func trigger(from row: [String: SQLiteValue]) throws -> TriggerDefinition {
        let metadata = try optionalJSON(TriggerMetadata.self, from: row.optionalText("metadata_json")) ?? TriggerMetadata()
        return try TriggerDefinition(
            id: row.requiredText("id"),
            pluginID: row.requiredText("plugin_id"),
            accountID: row.optionalText("account_id"),
            kind: TriggerKind(rawValue: row.requiredText("type")) ?? .manual,
            label: row.requiredText("label"),
            enabled: row.optionalInteger("enabled") != 0,
            intervalSeconds: row.optionalText("schedule").flatMap(TimeInterval.init),
            requestID: metadata.requestID,
            failureCount: metadata.failureCount,
            lastRunAt: try metadata.lastRunAt.map(ISO8601.date(from:)),
            nextRunAt: try metadata.nextRunAt.map(ISO8601.date(from:))
        )
    }

    private func job(from row: [String: SQLiteValue]) throws -> JobRecord {
        let metadata = try optionalJSON(JobMetadata.self, from: row.optionalText("metadata_json")) ?? JobMetadata()
        let emittedEventIDs = try optionalJSON([String].self, from: row.optionalText("emitted_event_ids")) ?? []
        return try JobRecord(
            id: row.requiredText("id"),
            pluginID: row.requiredText("plugin_id"),
            triggerID: row.requiredText("trigger_id"),
            accountID: row.optionalText("account_id"),
            status: JobStatus(rawValue: row.requiredText("status")) ?? .queued,
            queuedAt: ISO8601.date(from: metadata.queuedAt ?? row.optionalText("started_at") ?? "1970-01-01T00:00:00Z"),
            startedAt: try row.optionalText("started_at").map(ISO8601.date(from:)),
            finishedAt: try row.optionalText("finished_at").map(ISO8601.date(from:)),
            error: row.optionalText("error"),
            emittedEventIDs: emittedEventIDs
        )
    }

    private func actionRun(from row: [String: SQLiteValue]) throws -> ActionRunRecord {
        let input = try optionalJSON([String: String].self, from: row.optionalText("input_json")) ?? [:]
        let result = try optionalJSON([String: String].self, from: row.optionalText("result_json")) ?? [:]
        return try ActionRunRecord(
            id: row.requiredText("id"),
            ruleID: row.requiredText("rule_id"),
            eventID: row.requiredText("event_id"),
            action: row.requiredText("action"),
            status: ActionRunStatus(rawValue: row.requiredText("status")) ?? .failed,
            input: input,
            result: result,
            error: row.optionalText("error"),
            startedAt: ISO8601.date(from: row.requiredText("started_at")),
            finishedAt: try row.optionalText("finished_at").map(ISO8601.date(from:))
        )
    }

    private func rule(from row: [String: SQLiteValue]) throws -> Rule {
        let conditions = try optionalJSON([RuleCondition].self, from: row.optionalText("conditions_json")) ?? []
        let actions = try optionalJSON([RuleActionDefinition].self, from: row.optionalText("actions_json")) ?? []
        return Rule(
            id: try row.requiredText("id"),
            name: try row.requiredText("name"),
            enabled: row.optionalInteger("enabled") != 0,
            provider: row.optionalText("provider"),
            eventType: try row.requiredText("event_type"),
            conditions: conditions,
            actions: actions
        )
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        try String(decoding: jsonEncoder.encode(value), as: UTF8.self)
    }

    private func optionalJSON<T: Decodable>(_ type: T.Type, from string: String?) throws -> T? {
        guard let string else { return nil }
        return try jsonDecoder.decode(T.self, from: Data(string.utf8))
    }

    private func jobAuditTitle(for status: JobStatus) -> String {
        switch status {
        case .queued:
            return "Job queued"
        case .running:
            return "Job started"
        case .success:
            return "Job completed"
        case .failed:
            return "Job failed"
        case .cancelled:
            return "Job cancelled"
        case .skipped:
            return "Job skipped"
        }
    }

    private func jobAuditDetail(for job: JobRecord) -> String {
        var detail = "\(job.pluginID) job \(job.id) from trigger \(job.triggerID) is \(job.status.rawValue)."
        if let error = job.error, error.isEmpty == false {
            detail += " Error: \(error)"
        }
        if job.emittedEventIDs.isEmpty == false {
            detail += " Emitted events: \(job.emittedEventIDs.joined(separator: ", "))."
        }
        return detail
    }

    private func auditStatus(for status: JobStatus) -> String {
        switch status {
        case .success:
            return "success"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        case .skipped:
            return "skipped"
        case .queued, .running:
            return "pending"
        }
    }
}

private struct TriggerMetadata: Codable {
    var requestID: String?
    var failureCount: Int = 0
    var lastRunAt: String?
    var nextRunAt: String?
}

private struct JobMetadata: Codable {
    var queuedAt: String?
}

private enum ISO8601 {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func date(from string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: string) else {
            throw PersistenceError.invalidDate(string)
        }
        return date
    }
}

private struct AccountConfigurationMetadata: Codable {
    var pluginID: String
    var accountName: String
    var variables: [String: String]
}

private func accountConfigurationSyncID(_ accountID: String) -> String {
    "cfg_\(accountID)"
}

private extension Dictionary where Key == String, Value == SQLiteValue {
    func requiredText(_ column: String) throws -> String {
        guard case .text(let value)? = self[column] else {
            throw PersistenceError.missingColumn(column)
        }
        return value
    }

    func optionalURL(_ column: String) -> URL? {
        guard case .text(let value)? = self[column] else {
            return nil
        }
        return URL(string: value)
    }

    func optionalText(_ column: String) -> String? {
        guard case .text(let value)? = self[column] else {
            return nil
        }
        return value
    }

    func optionalInteger(_ column: String) -> Int64 {
        guard case .integer(let value)? = self[column] else {
            return 0
        }
        return value
    }

    func requiredDouble(_ column: String) throws -> Double {
        switch self[column] {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            throw PersistenceError.missingColumn(column)
        }
    }
}
