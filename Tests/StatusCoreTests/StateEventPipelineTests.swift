import Foundation
import Testing
@testable import StatusCore

@Test func stateEventPipelineIngestsFirstObservationWhenChangedToMatches() throws {
    let store = try temporaryStore()
    let pipeline = StateEventPipeline(
        detector: StateChangeDetector(store: store),
        ingestor: EventIngestor(store: store)
    )
    let date = Date(timeIntervalSince1970: 1_783_433_520)

    let result = try pipeline.process(
        resourceID: "res_app",
        currentState: ["appStoreState": "REJECTED"],
        capturedAt: date,
        mappings: [rejectedMapping()]
    )

    #expect(result.events.count == 1)
    #expect(result.events.first?.type == "app.review.rejected")
    #expect(result.ingestionResults.first == .inserted(eventID: result.events[0].id, statusItemID: "sti_\(result.events[0].id.dropFirst(4))"))
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntryCount() == 1)
}

@Test func stateEventPipelineDoesNotEmitRepeatedUnchangedState() throws {
    let store = try temporaryStore()
    let pipeline = StateEventPipeline(
        detector: StateChangeDetector(store: store),
        ingestor: EventIngestor(store: store)
    )
    let firstDate = Date(timeIntervalSince1970: 1_783_433_520)
    let secondDate = Date(timeIntervalSince1970: 1_783_437_120)

    _ = try pipeline.process(
        resourceID: "res_app",
        currentState: ["appStoreState": "REJECTED"],
        capturedAt: firstDate,
        mappings: [rejectedMapping()]
    )
    let second = try pipeline.process(
        resourceID: "res_app",
        currentState: ["appStoreState": "REJECTED"],
        capturedAt: secondDate,
        mappings: [rejectedMapping()]
    )

    #expect(second.events.isEmpty)
    #expect(second.ingestionResults.isEmpty)
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntryCount() == 1)
}

@Test func stateEventPipelineEmitsWhenStateTransitionsIntoTarget() throws {
    let store = try temporaryStore()
    let pipeline = StateEventPipeline(
        detector: StateChangeDetector(store: store),
        ingestor: EventIngestor(store: store)
    )
    let firstDate = Date(timeIntervalSince1970: 1_783_433_520)
    let secondDate = Date(timeIntervalSince1970: 1_783_437_120)

    let first = try pipeline.process(
        resourceID: "res_app",
        currentState: ["appStoreState": "IN_REVIEW"],
        capturedAt: firstDate,
        mappings: [rejectedMapping()]
    )
    let second = try pipeline.process(
        resourceID: "res_app",
        currentState: ["appStoreState": "REJECTED"],
        capturedAt: secondDate,
        mappings: [rejectedMapping()]
    )

    #expect(first.events.isEmpty)
    #expect(second.events.count == 1)
    #expect(second.ingestionResults.count == 1)
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntryCount() == 1)
}

private func rejectedMapping() -> StateEventMappingDefinition {
    StateEventMappingDefinition(
        provider: "appstoreconnect",
        eventType: "app.review.rejected",
        resourceID: "res_app",
        resourceName: "Example App",
        severity: .critical,
        title: "App rejected",
        summary: "Example App needs a reviewer reply.",
        actionURL: URL(string: "https://appstoreconnect.apple.com/apps/123"),
        conditions: [
            MappingCondition(path: "$.attributes.appStoreState", operation: .changedTo, value: "REJECTED")
        ],
        fingerprintStatePath: "$.attributes.appStoreState"
    )
}

private func temporaryStore() throws -> StatusPersistenceStore {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    try insertResourceFixture(database, resourceID: "res_app")
    return StatusPersistenceStore(database: database)
}

private func insertResourceFixture(_ database: SQLiteDatabase, resourceID: String) throws {
    let now = "2026-07-07T12:00:00Z"
    try database.execute(
        """
        INSERT INTO plugins
        (id, name, author, description, category, trust_level, installed_version, install_path, installed_at, updated_at)
        VALUES (?, 'App Store Connect', 'Status Foundry', 'Fixture plugin', 'developer', 'official', '0.1.0', '/tmp/plugin', ?, ?)
        """,
        bindings: [.text("com.status.appstoreconnect"), .text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO accounts
        (id, plugin_id, provider, display_name, auth_type, created_at, updated_at)
        VALUES (?, 'com.status.appstoreconnect', 'appstoreconnect', 'Example Account', 'none', ?, ?)
        """,
        bindings: [.text("acc_fixture"), .text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO resources
        (id, account_id, plugin_id, type, external_id, name, first_seen_at, last_seen_at)
        VALUES (?, 'acc_fixture', 'com.status.appstoreconnect', 'app', '123', 'Example App', ?, ?)
        """,
        bindings: [.text(resourceID), .text(now), .text(now)]
    )
}
