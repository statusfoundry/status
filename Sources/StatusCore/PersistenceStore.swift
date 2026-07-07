import Foundation

public final class StatusPersistenceStore {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
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
}
