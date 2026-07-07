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
            (id, resource_id, kind, source_event_ids, severity, title, summary, action_url, state, created_at, updated_at)
            VALUES (?, ?, 'event', '[]', ?, ?, ?, ?, ?, ?, ?)
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
                .text(updatedAt)
            ]
        )
    }

    public func statusItem(id: String) throws -> StatusItem? {
        guard let row = try database.query("SELECT * FROM status_items WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        let actionURL = row.optionalURL("action_url")
        return try StatusItem(
            id: row.requiredText("id"),
            resourceID: row.requiredText("resource_id"),
            severity: Severity(rawValue: row.requiredText("severity")) ?? .notice,
            title: row.requiredText("title"),
            summary: row.requiredText("summary"),
            state: StatusItemState(rawValue: row.requiredText("state")) ?? .open,
            updatedAt: ISO8601.date(from: row.requiredText("updated_at")),
            actionLink: actionURL.map { ActionLink(id: "open", label: "Open", url: $0) }
        )
    }

    public func insertAuditEntry(_ entry: AuditEntry) throws {
        try database.execute(
            """
            INSERT OR REPLACE INTO audit_entries
            (id, title, detail, timestamp, status)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(entry.id),
                .text(entry.title),
                .text(entry.detail),
                .text(ISO8601.string(from: entry.timestamp)),
                .text(entry.status)
            ]
        )
    }

    public func auditEntry(id: String) throws -> AuditEntry? {
        guard let row = try database.query("SELECT * FROM audit_entries WHERE id = ?", bindings: [.text(id)]).first else {
            return nil
        }
        return try AuditEntry(
            id: row.requiredText("id"),
            title: row.requiredText("title"),
            detail: row.requiredText("detail"),
            timestamp: ISO8601.date(from: row.requiredText("timestamp")),
            status: row.requiredText("status")
        )
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

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        try String(decoding: jsonEncoder.encode(value), as: UTF8.self)
    }

    private func optionalJSON<T: Decodable>(_ type: T.Type, from string: String?) throws -> T? {
        guard let string else { return nil }
        return try jsonDecoder.decode(T.self, from: Data(string.utf8))
    }
}

private struct TriggerMetadata: Codable {
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
}
