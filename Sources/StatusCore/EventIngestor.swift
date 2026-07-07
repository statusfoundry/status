import Foundation

public enum EventIngestionResult: Equatable, Sendable {
    case inserted(eventID: String, statusItemID: String?)
    case duplicate(originalEventID: String)
}

public final class EventIngestor {
    private let store: StatusPersistenceStore

    public init(store: StatusPersistenceStore) {
        self.store = store
    }

    public func ingest(_ event: Event) throws -> EventIngestionResult {
        if let existing = try store.event(fingerprint: event.fingerprint) {
            try store.incrementDedupCount(fingerprint: event.fingerprint, seenAt: event.timestamp)
            try store.insertAuditEntry(
                AuditEntry(
                    id: auditID(for: event, suffix: "duplicate"),
                    title: "Duplicate event suppressed",
                    detail: "\(event.type) matched existing fingerprint \(event.fingerprint).",
                    timestamp: event.timestamp,
                    status: "suppressed"
                )
            )
            return .duplicate(originalEventID: existing.id)
        }

        try store.insertEvent(event)

        let statusItemID: String?
        if event.severity >= .warning {
            let item = StatusItem(
                id: makeStatusItemID(for: event),
                resourceID: event.resourceID,
                severity: event.severity,
                title: event.title,
                summary: event.summary,
                state: .open,
                updatedAt: event.timestamp,
                actionLink: event.actionURL.map { ActionLink(id: "act_\(event.id)", label: "Open", url: $0) }
            )
            try store.insertStatusItem(item)
            statusItemID = item.id
        } else {
            statusItemID = nil
        }

        try store.insertAuditEntry(
            AuditEntry(
                id: auditID(for: event, suffix: "inserted"),
                title: "Event ingested",
                detail: "\(event.type) entered the event pipeline.",
                timestamp: event.timestamp,
                status: "success"
            )
        )

        return .inserted(eventID: event.id, statusItemID: statusItemID)
    }

    private func makeStatusItemID(for event: Event) -> String {
        if event.id.hasPrefix("evt_") {
            return "sti_" + event.id.dropFirst(4)
        }
        return "sti_" + event.id
    }

    private func auditID(for event: Event, suffix: String) -> String {
        if event.id.hasPrefix("evt_") {
            return "aud_" + event.id.dropFirst(4) + "_" + suffix
        }
        return "aud_" + event.id + "_" + suffix
    }
}
