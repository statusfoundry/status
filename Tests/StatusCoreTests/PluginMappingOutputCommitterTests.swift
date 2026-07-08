import Foundation
import Testing
@testable import StatusCore

@Test func pluginMappingOutputCommitterPersistsResourcesStateEventsAndAudit() throws {
    let database = try temporaryMappingCommitDatabase()
    try insertMappingCommitPluginFixture(database)
    let store = StatusPersistenceStore(database: database)
    let committer = PluginMappingOutputCommitter(store: store)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let actionURL = try #require(URL(string: "https://status.hakobs.com"))
    let resource = Resource(
        id: "acct_web:status.hakobs.com",
        accountID: "acct_web",
        pluginID: "com.status.website",
        type: "website",
        name: "status.hakobs.com",
        actionURL: actionURL
    )
    let fingerprint = EventFingerprint.make(
        EventFingerprintInput(
            provider: "com.status.website",
            eventType: "website.down",
            resourceID: resource.id,
            relevantState: "critical|Website down"
        )
    )
    let event = Event(
        id: "evt_\(fingerprint.prefix(26))",
        provider: "com.status.website",
        type: "website.down",
        resourceID: resource.id,
        resourceName: resource.name,
        severity: .critical,
        title: "Website down",
        summary: "status.hakobs.com is not responding normally.",
        timestamp: now,
        actionURL: actionURL,
        fingerprint: fingerprint
    )

    let result = try committer.commit(
        PluginMappingExecutionOutput(
            resources: [
                MappedPluginResource(
                    resource: resource,
                    state: [
                        "id": "status.hakobs.com",
                        "name": "status.hakobs.com",
                        "reachable": "false",
                        "statusCode": "503"
                    ]
                )
            ],
            events: [event],
            metrics: [
                MappedPluginMetric(
                    metric: Metric(
                        id: "\(resource.id):metric:response_time",
                        resourceID: resource.id,
                        label: "response_time",
                        value: "120 ms",
                        delta: "ms",
                        severity: .ok
                    ),
                    pointValue: 120,
                    pointTimestamp: now
                )
            ]
        ),
        jobID: "job_website_check",
        capturedAt: now
    )

    #expect(result.resourceIDs == [resource.id])
    #expect(result.eventResults == [.inserted(eventID: event.id, statusItemID: "sti_\(event.id.dropFirst(4))")])
    #expect(result.metricIDs == ["\(resource.id):metric:response_time"])
    #expect(try store.resource(id: resource.id) == resource)
    #expect(try store.resourceStateSnapshot(resourceID: resource.id)?.state["statusCode"] == "503")
    #expect(try store.event(id: event.id) == event)
    #expect(try store.metrics() == [
        Metric(
            id: "\(resource.id):metric:response_time",
            resourceID: resource.id,
            label: "response_time",
            value: "120 ms",
            delta: "ms",
            severity: .ok
        )
    ])
    #expect(try store.metricPoints(metricID: "\(resource.id):metric:response_time").map(\.value) == [120])
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntry(id: "aud_job_website_check_mapping_commit") == result.auditEntry)
    #expect(try store.auditEntryCount() == 2)
}

private func temporaryMappingCommitDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    return database
}

private func insertMappingCommitPluginFixture(_ database: SQLiteDatabase) throws {
    let now = "2026-07-07T12:00:00Z"
    try database.execute(
        """
        INSERT INTO plugins
        (id, name, author, description, category, trust_level, installed_version, install_path, installed_at, updated_at)
        VALUES ('com.status.website', 'Website Uptime', 'Status Foundry', 'Fixture plugin', 'ops', 'official', '0.1.0', '/tmp/plugin', ?, ?)
        """,
        bindings: [.text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO accounts
        (id, plugin_id, provider, display_name, auth_type, created_at, updated_at)
        VALUES ('acct_web', 'com.status.website', 'com.status.website', 'Website checks', 'none', ?, ?)
        """,
        bindings: [.text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO jobs
        (id, plugin_id, trigger_id, account_id, status, started_at)
        VALUES ('job_website_check', 'com.status.website', 'trg_website_check', 'acct_web', 'running', ?)
        """,
        bindings: [.text(now)]
    )
}
