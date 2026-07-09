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
    #expect(try store.resource(id: resource.id) == Resource(
        id: resource.id,
        accountID: resource.accountID,
        pluginID: resource.pluginID,
        type: resource.type,
        name: resource.name,
        fields: [
            "id": "status.hakobs.com",
            "name": "status.hakobs.com",
            "reachable": "false",
            "statusCode": "503"
        ],
        actionURL: actionURL
    ))
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

@Test func pluginMappingOutputCommitterResolvesOpenItemsFromClosingEvents() throws {
    let database = try temporaryMappingCommitDatabase()
    try insertMappingCommitPluginFixture(database)
    let store = StatusPersistenceStore(database: database)
    let committer = PluginMappingOutputCommitter(store: store)
    let openedAt = Date(timeIntervalSince1970: 1_783_433_520)
    let closedAt = openedAt.addingTimeInterval(300)
    let actionURL = try #require(URL(string: "https://status.hakobs.com"))
    let resource = Resource(
        id: "acct_web:status.hakobs.com",
        accountID: "acct_web",
        pluginID: "com.status.website",
        type: "website",
        name: "status.hakobs.com",
        actionURL: actionURL
    )
    let declarations = [
        EventTypeDeclaration(
            type: "website.down",
            label: "Website down",
            resourceType: "website",
            defaultSeverity: .critical,
            notificationDefault: .immediate,
            opensIncident: "downtime",
            closedBy: "website.recovered"
        ),
        EventTypeDeclaration(
            type: "website.recovered",
            label: "Website recovered",
            resourceType: "website",
            defaultSeverity: .ok,
            notificationDefault: .digest
        )
    ]
    let downFingerprint = EventFingerprint.make(
        EventFingerprintInput(
            provider: "com.status.website",
            eventType: "website.down",
            resourceID: resource.id,
            relevantState: "down"
        )
    )
    let downEvent = Event(
        id: "evt_\(downFingerprint.prefix(26))",
        provider: "com.status.website",
        type: "website.down",
        resourceID: resource.id,
        resourceName: resource.name,
        severity: .critical,
        title: "Website down",
        summary: "status.hakobs.com is not responding normally.",
        timestamp: openedAt,
        actionURL: actionURL,
        fingerprint: downFingerprint
    )
    let recoveredFingerprint = EventFingerprint.make(
        EventFingerprintInput(
            provider: "com.status.website",
            eventType: "website.recovered",
            resourceID: resource.id,
            relevantState: "recovered"
        )
    )
    let recoveredEvent = Event(
        id: "evt_\(recoveredFingerprint.prefix(26))",
        provider: "com.status.website",
        type: "website.recovered",
        resourceID: resource.id,
        resourceName: resource.name,
        severity: .ok,
        title: "Website recovered",
        summary: "status.hakobs.com is responding normally again.",
        timestamp: closedAt,
        actionURL: actionURL,
        fingerprint: recoveredFingerprint
    )

    let downResult = try committer.commit(
        PluginMappingExecutionOutput(
            resources: [
                MappedPluginResource(
                    resource: resource,
                    state: ["id": "status.hakobs.com", "name": "status.hakobs.com", "reachable": "false"]
                )
            ],
            events: [downEvent],
            metrics: []
        ),
        jobID: "job_website_check",
        capturedAt: openedAt,
        eventDeclarations: declarations
    )
    let statusItemID: String
    guard case .inserted(_, let createdStatusItemID) = downResult.eventResults.first else {
        Issue.record("Expected opening event to create a status item.")
        return
    }
    statusItemID = try #require(createdStatusItemID)

    let recoveredResult = try committer.commit(
        PluginMappingExecutionOutput(resources: [], events: [recoveredEvent], metrics: []),
        jobID: "job_website_check",
        capturedAt: closedAt,
        eventDeclarations: declarations
    )

    #expect(recoveredResult.eventResults == [.inserted(eventID: recoveredEvent.id, statusItemID: nil)])
    let resolvedItem = try #require(try store.statusItem(id: statusItemID))
    #expect(resolvedItem.state == .resolved)
    #expect(resolvedItem.resolvedAt == closedAt)
    #expect(try store.statusItems().isEmpty)
    #expect(try store.statusItemCount() == 1)
}

@Test func packagedPluginEventsFileDecodesIncidentMetadataAndRegistryNotificationValues() throws {
    let json = Data(
        """
        {
          "events": [
            {
              "type": "website.down",
              "label": "Website down",
              "resourceType": "website",
              "defaultSeverity": "critical",
              "notificationDefault": "immediate",
              "opensIncident": "downtime",
              "closedBy": "website.recovered"
            },
            {
              "type": "github.workflow.failed",
              "label": "Workflow failed",
              "resourceType": "repository",
              "defaultSeverity": "warning",
              "notificationDefault": "dashboard-only"
            }
          ]
        }
        """.utf8
    )

    let decoded = try JSONDecoder().decode(PackagedPluginEventsFile.self, from: json)

    #expect(decoded.events[0].opensIncident == "downtime")
    #expect(decoded.events[0].closedBy == "website.recovered")
    #expect(decoded.events[1].notificationDefault == .dashboardOnly)
}

@Test func pluginMappingOutputCommitterEmitsMetricDropEventAgainstPreviousPoint() throws {
    let database = try temporaryMappingCommitDatabase()
    try insertMappingCommitPluginFixture(database)
    let store = StatusPersistenceStore(database: database)
    let committer = PluginMappingOutputCommitter(store: store)
    let resource = Resource(
        id: "acct_yt:channel-1",
        accountID: "acct_yt",
        pluginID: "com.status.youtube",
        type: "youtube_channel",
        name: "Status Channel"
    )
    let metric = Metric(
        id: "\(resource.id):metric:views_28d",
        resourceID: resource.id,
        label: "views_28d",
        value: "1000",
        delta: "count",
        severity: .ok
    )
    let firstPointAt = Date(timeIntervalSince1970: 1_783_433_520)
    let secondPointAt = firstPointAt.addingTimeInterval(3_600)

    let firstResult = try committer.commit(
        PluginMappingExecutionOutput(
            resources: [MappedPluginResource(resource: resource, state: ["id": "channel-1", "name": "Status Channel"])],
            events: [],
            metrics: [MappedPluginMetric(metric: metric, pointValue: 1_000, pointTimestamp: firstPointAt)]
        ),
        jobID: "job_youtube_first",
        capturedAt: firstPointAt
    )
    let secondResult = try committer.commit(
        PluginMappingExecutionOutput(
            resources: [],
            events: [],
            metrics: [MappedPluginMetric(metric: metric, pointValue: 750, pointTimestamp: secondPointAt)]
        ),
        jobID: "job_youtube_second",
        capturedAt: secondPointAt
    )

    #expect(firstResult.eventResults == [])
    #expect(secondResult.eventResults.count == 1)
    guard case .inserted(let eventID, let statusItemID) = secondResult.eventResults[0] else {
        Issue.record("Expected inserted metric drop event.")
        return
    }
    let event = try #require(try store.event(id: eventID))
    #expect(statusItemID == "sti_\(eventID.dropFirst(4))")
    #expect(event.provider == "com.status.youtube")
    #expect(event.type == "metric.views_28d.dropped")
    #expect(event.resourceID == resource.id)
    #expect(event.severity == .warning)
    #expect(event.summary == "Status Channel views_28d dropped 25% vs the previous point.")
    #expect(try store.statusItemCount() == 1)
    #expect(try store.metricPoints(metricID: metric.id).map(\.value) == [1_000, 750])
}

@Test func pluginMappingOutputCommitterSuppressesDuplicateMetricDropEventsInSameDayBucket() throws {
    let database = try temporaryMappingCommitDatabase()
    try insertMappingCommitPluginFixture(database)
    let store = StatusPersistenceStore(database: database)
    let committer = PluginMappingOutputCommitter(store: store)
    let resource = Resource(
        id: "acct_yt:channel-1",
        accountID: "acct_yt",
        pluginID: "com.status.youtube",
        type: "youtube_channel",
        name: "Status Channel"
    )
    let metric = Metric(
        id: "\(resource.id):metric:views_28d",
        resourceID: resource.id,
        label: "views_28d",
        value: "1000",
        delta: "count",
        severity: .ok
    )
    let firstPointAt = Date(timeIntervalSince1970: 1_783_433_520)

    _ = try committer.commit(
        PluginMappingExecutionOutput(
            resources: [MappedPluginResource(resource: resource, state: ["id": "channel-1", "name": "Status Channel"])],
            events: [],
            metrics: [MappedPluginMetric(metric: metric, pointValue: 1_000, pointTimestamp: firstPointAt)]
        ),
        jobID: "job_youtube_first",
        capturedAt: firstPointAt
    )
    let firstDropResult = try committer.commit(
        PluginMappingExecutionOutput(
            resources: [],
            events: [],
            metrics: [MappedPluginMetric(metric: metric, pointValue: 750, pointTimestamp: firstPointAt.addingTimeInterval(3_600))]
        ),
        jobID: "job_youtube_second",
        capturedAt: firstPointAt.addingTimeInterval(3_600)
    )
    let secondDropResult = try committer.commit(
        PluginMappingExecutionOutput(
            resources: [],
            events: [],
            metrics: [MappedPluginMetric(metric: metric, pointValue: 500, pointTimestamp: firstPointAt.addingTimeInterval(7_200))]
        ),
        jobID: "job_youtube_third",
        capturedAt: firstPointAt.addingTimeInterval(7_200)
    )

    #expect(firstDropResult.eventResults.count == 1)
    #expect(secondDropResult.eventResults.count == 1)
    guard case .duplicate = secondDropResult.eventResults[0] else {
        Issue.record("Expected duplicate metric drop event in the same day bucket.")
        return
    }
    #expect(try store.statusItemCount() == 1)
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
        VALUES
          ('com.status.website', 'Website Uptime', 'Status Foundry', 'Fixture plugin', 'ops', 'official', '0.1.0', '/tmp/plugin', ?, ?),
          ('com.status.youtube', 'YouTube', 'Status Foundry', 'Fixture plugin', 'media', 'official', '0.1.0', '/tmp/plugin', ?, ?)
        """,
        bindings: [.text(now), .text(now), .text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO accounts
        (id, plugin_id, provider, display_name, auth_type, created_at, updated_at)
        VALUES
          ('acct_web', 'com.status.website', 'com.status.website', 'Website checks', 'none', ?, ?),
          ('acct_yt', 'com.status.youtube', 'com.status.youtube', 'YouTube channel', 'none', ?, ?)
        """,
        bindings: [.text(now), .text(now), .text(now), .text(now)]
    )
    try database.execute(
        """
        INSERT INTO jobs
        (id, plugin_id, trigger_id, account_id, status, started_at)
        VALUES
          ('job_website_check', 'com.status.website', 'trg_website_check', 'acct_web', 'running', ?),
          ('job_youtube_first', 'com.status.youtube', 'trg_youtube_metrics', 'acct_yt', 'running', ?),
          ('job_youtube_second', 'com.status.youtube', 'trg_youtube_metrics', 'acct_yt', 'running', ?),
          ('job_youtube_third', 'com.status.youtube', 'trg_youtube_metrics', 'acct_yt', 'running', ?)
        """,
        bindings: [.text(now), .text(now), .text(now), .text(now)]
    )
}
