import Foundation
import Testing
@testable import StatusCore

@Test func eventIngestorCreatesStatusItemAndAuditEntryForWarningOrCriticalEvent() throws {
    let store = try temporaryStore()
    let ingestor = EventIngestor(store: store)
    let event = workflowFailedEvent()

    let result = try ingestor.ingest(event)

    #expect(result == .inserted(eventID: event.id, statusItemID: "sti_01workflowfailed"))
    #expect(try store.event(id: event.id) == event)
    #expect(try store.statusItem(id: "sti_01workflowfailed")?.severity == .critical)
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntryCount() == 1)
}

@Test func eventIngestorSuppressesDuplicateFingerprintAndAuditsIt() throws {
    let store = try temporaryStore()
    let ingestor = EventIngestor(store: store)
    let first = workflowFailedEvent()
    var duplicate = workflowFailedEvent()
    duplicate.id = "evt_01workflowfailedduplicate"

    #expect(try ingestor.ingest(first) == .inserted(eventID: first.id, statusItemID: "sti_01workflowfailed"))
    #expect(try ingestor.ingest(duplicate) == .duplicate(originalEventID: first.id))
    #expect(try store.event(id: duplicate.id) == nil)
    #expect(try store.dedupCount(fingerprint: first.fingerprint) == 1)
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntryCount() == 2)
}

@Test func noticeEventDoesNotCreateStatusItemByDefault() throws {
    let store = try temporaryStore()
    let ingestor = EventIngestor(store: store)
    let event = Event(
        id: "evt_01notice",
        provider: "github",
        type: "github.issue.commented",
        resourceID: "res_status_repo",
        resourceName: "status",
        severity: .notice,
        title: "Issue commented",
        summary: "A watched issue has a new comment.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_520),
        fingerprint: "github:issue.commented:res_status_repo:comment"
    )

    #expect(try ingestor.ingest(event) == .inserted(eventID: event.id, statusItemID: nil))
    #expect(try store.statusItemCount() == 0)
    #expect(try store.auditEntryCount() == 1)
}

private func temporaryStore() throws -> StatusPersistenceStore {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    return StatusPersistenceStore(database: database)
}

private func workflowFailedEvent() -> Event {
    Event(
        id: "evt_01workflowfailed",
        provider: "github",
        type: "github.workflow.failed",
        resourceID: "res_status_repo",
        resourceName: "status",
        severity: .critical,
        title: "Workflow failed",
        summary: "CI failed on main.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_520),
        actionURL: URL(string: "https://github.com/statusfoundry/status/actions"),
        fingerprint: "github:workflow.failed:res_status_repo:failure"
    )
}
