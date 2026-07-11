import Foundation
import Testing
@testable import StatusCore

@Test func bundledPluginInstallerInstallsOfficialPluginsFromBundleResources() throws {
    let database = try temporaryBundledPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-bundled-\(UUID().uuidString)", isDirectory: true)
    let installer = BundledPluginInstaller(store: store, installRoot: installRoot)

    let packages = try installer.availablePlugins()
    let results = try installer.installAll(installedAt: Date(timeIntervalSince1970: 1_783_433_520))

    #expect(packages.map(\.id).sorted() == [
        "com.status.appstoreconnect",
        "com.status.github",
        "com.status.gitlab",
        "com.status.googleplay",
        "com.status.jira",
        "com.status.website",
        "com.status.youtube"
    ])
    #expect(results.map(\.plugin.id).sorted() == packages.map(\.id).sorted())
    #expect(try store.installedPlugins().map(\.id).sorted() == packages.map(\.id).sorted())
    #expect(try store.installedPlugin(id: "com.status.website")?.setup?.fields.first?.id == "host")
    #expect(try store.installedPlugin(id: "com.status.gitlab")?.setup?.fields.first?.id == "projectId")
    #expect(try store.triggers().contains { $0.pluginID == "com.status.website" && $0.kind == .manual && $0.requestID == "check_site" })
    #expect(try store.triggers().contains { $0.pluginID == "com.status.gitlab" && $0.kind == .cron && $0.requestID == "list_pipelines" })
    #expect(try store.triggers().contains { $0.pluginID == "com.status.googleplay" && $0.kind == .cron && $0.requestID == "list_reviews" })
    #expect(try store.triggers().contains { $0.pluginID == "com.status.youtube" && $0.kind == .cron && $0.requestID == "list_my_channels" })
    #expect(try store.rules().contains { $0.provider == "com.status.website" && $0.eventType == "website.down" })
    #expect(try store.rules().contains { $0.provider == "com.status.gitlab" && $0.eventType == "gitlab.pipeline.failed" })
    #expect(try store.rules().contains { $0.provider == "com.status.googleplay" && $0.eventType == "googleplay.review.needs_attention" })
    #expect(try store.rules().contains { $0.provider == "com.status.youtube" && $0.eventType == "youtube.channel.visibility_limited" })
    #expect(try store.installedPluginDefinition(pluginID: "com.status.jira")?.actions.map(\.id) == ["jira.createIssue"])
    let websiteVersion = try #require(try store.installedPluginVersions(pluginID: "com.status.website").first)
    #expect(FileManager.default.fileExists(atPath: try #require(websiteVersion.packagePath)))
}

@Test func bundledPluginInstallerIsIdempotentAndPreservesStoredRules() throws {
    let database = try temporaryBundledPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-bundled-\(UUID().uuidString)", isDirectory: true)
    let installer = BundledPluginInstaller(store: store, installRoot: installRoot)

    _ = try installer.install(pluginID: "com.status.website", installedAt: Date(timeIntervalSince1970: 1_783_433_520))
    var rule = try #require(try store.rules().first(where: { $0.provider == "com.status.website" }))
    rule.enabled = true
    try store.upsertRule(rule, updatedAt: Date(timeIntervalSince1970: 1_783_433_620))

    _ = try installer.install(pluginID: "com.status.website", installedAt: Date(timeIntervalSince1970: 1_783_433_720))

    #expect(try store.rules().first(where: { $0.id == rule.id })?.enabled == true)
    #expect(try store.installedPluginVersions(pluginID: "com.status.website").count == 1)
}

@Test func bundledYouTubePluginMapsChannelsUploadsAndMetrics() throws {
    let database = try temporaryBundledPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-bundled-\(UUID().uuidString)", isDirectory: true)
    let installer = BundledPluginInstaller(store: store, installRoot: installRoot)
    _ = try installer.install(pluginID: "com.status.youtube", installedAt: Date(timeIntervalSince1970: 1_783_433_520))
    let definition = try #require(try store.installedPluginDefinition(pluginID: "com.status.youtube"))
    let capturedAt = Date(timeIntervalSince1970: 1_783_433_520)

    let channelOutput = try PluginMappingExecutor.execute(
        definition.mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.youtube",
            accountID: "acct_yt",
            provider: "com.status.youtube",
            requestID: "list_my_channels",
            payload: decodeBundledMappingJSON("""
            {
              "items": [
                {
                  "id": "UC_status",
                  "snippet": {
                    "title": "Status Foundry",
                    "description": "Product updates",
                    "country": "MT"
                  },
                  "statistics": {
                    "subscriberCount": "1200",
                    "viewCount": "45000",
                    "videoCount": "38"
                  },
                  "status": {
                    "privacyStatus": "private"
                  },
                  "contentDetails": {
                    "relatedPlaylists": {
                      "uploads": "UU_status"
                    }
                  }
                }
              ]
            }
            """),
            capturedAt: capturedAt
        )
    )
    let uploadOutput = try PluginMappingExecutor.execute(
        definition.mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.youtube",
            accountID: "acct_yt",
            provider: "com.status.youtube",
            requestID: "list_recent_uploads",
            payload: decodeBundledMappingJSON("""
            {
              "items": [
                {
                  "id": {
                    "videoId": "vid_123"
                  },
                  "snippet": {
                    "title": "Status update",
                    "channelId": "UC_status",
                    "channelTitle": "Status Foundry",
                    "publishedAt": "2026-07-09T10:00:00Z",
                    "description": "Release notes"
                  }
                }
              ]
            }
            """),
            capturedAt: capturedAt
        )
    )

    #expect(channelOutput.resources.map { $0.resource.id } == ["acct_yt:UC_status"])
    #expect(channelOutput.resources[0].resource.name == "Status Foundry")
    #expect(channelOutput.resources[0].state["subscriberCount"] == "1200")
    #expect(channelOutput.metrics.map { $0.metric.id }.sorted() == [
        "acct_yt:uc_status:metric:subscriber_count",
        "acct_yt:uc_status:metric:video_count",
        "acct_yt:uc_status:metric:view_count"
    ])
    #expect(channelOutput.events.map { $0.type } == ["youtube.channel.visibility_limited"])
    #expect(channelOutput.events[0].summary == "Status Foundry is currently private.")
    #expect(uploadOutput.resources.map { $0.resource.id } == ["acct_yt:vid_123"])
    #expect(uploadOutput.resources[0].resource.actionURL?.absoluteString == "https://www.youtube.com/watch?v=vid_123")
    #expect(uploadOutput.events.map { $0.type } == ["youtube.video.published"])
    #expect(uploadOutput.events[0].summary == "Status update was published on Status Foundry.")
    #expect(uploadOutput.events[0].timestamp == ISO8601DateFormatter().date(from: "2026-07-09T10:00:00Z"))
}

@Test func bundledGitHubPluginRunsAllManualChecksForConfiguredApp() async throws {
    let database = try temporaryBundledPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-bundled-\(UUID().uuidString)", isDirectory: true)
    let installer = BundledPluginInstaller(store: store, installRoot: installRoot)
    _ = try installer.install(pluginID: "com.status.github", installedAt: Date(timeIntervalSince1970: 1_783_433_520))
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    try grantBundledPermissions([.network, .keychain, .backgroundRefresh], pluginID: "com.status.github", store: store, at: now)
    let plugin = try #require(try store.installedPlugin(id: "com.status.github"))
    _ = try PluginSetupConfiguration.saveValues(
        ["owner": "statusfoundry", "repo": "status", "token": "github_pat_example"],
        for: plugin,
        service: PluginRuntimeService(store: store, credentialStore: nil),
        credentialStore: credentials,
        now: now
    )
    let account = try #require(try store.accountConfigurations(pluginID: "com.status.github").first)
    let activityFixture = try Data(contentsOf: bundledPluginDirectory(pluginID: "com.status.github").appendingPathComponent("fixtures/list_repository_activity.json"))
    let workflowFixture = try Data(contentsOf: bundledPluginDirectory(pluginID: "com.status.github").appendingPathComponent("fixtures/list_workflow_runs.json"))
    let transport = BundledProviderTransport(expectedAuthorization: "Bearer github_pat_example") { request in
        if request.url.path == "/repos/statusfoundry/status/events" {
            return PluginHTTPResponse(data: activityFixture, statusCode: 200, url: request.url)
        }
        if request.url.path == "/repos/statusfoundry/status/actions/runs" {
            #expect(request.url.query?.contains("per_page=25") == true)
            return PluginHTTPResponse(data: workflowFixture, statusCode: 200, url: request.url)
        }
        Issue.record("Unexpected GitHub request URL: \(request.url.absoluteString)")
        return PluginHTTPResponse(data: Data("{}".utf8), statusCode: 404, url: request.url)
    }
    let service = PluginRuntimeService(store: store, transport: transport, credentialStore: credentials)

    let jobs = try service.enqueueManualConfiguredPluginRuns(pluginID: "com.status.github", accountID: account.id, now: now)
    var resourceCount = 0
    var eventTypes: [String] = []
    for job in jobs {
        let result = try await service.runQueuedPluginJob(jobID: job.id, now: now)
        resourceCount += result.mappingOutput.resources.count
        eventTypes.append(contentsOf: result.mappingOutput.events.map(\.type))
    }

    #expect(jobs.map(\.triggerID) == ["trg_com_status_github_refresh_activity", "trg_com_status_github_refresh_workflows"])
    #expect(resourceCount == 1)
    #expect(eventTypes.sorted() == ["github.pull_request.opened", "github.workflow.failed"])
    #expect(try store.resource(id: "\(account.id):123456")?.name == "example-org/example-repo")
    #expect(try store.statusItemCount() == 1)
}

@Test func bundledYouTubePluginRunsAllManualChecksForConfiguredOAuthApp() async throws {
    let database = try temporaryBundledPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let credentials = InMemoryCredentialStore()
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-bundled-\(UUID().uuidString)", isDirectory: true)
    let installer = BundledPluginInstaller(store: store, installRoot: installRoot)
    _ = try installer.install(pluginID: "com.status.youtube", installedAt: Date(timeIntervalSince1970: 1_783_433_520))
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    try grantBundledPermissions([.network, .keychain, .oauth, .backgroundRefresh], pluginID: "com.status.youtube", store: store, at: now)
    let plugin = try #require(try store.installedPlugin(id: "com.status.youtube"))
    _ = try PluginSetupConfiguration.saveOAuthTokenSet(
        PluginOAuthTokenSet(
            accessToken: "youtube_access",
            refreshToken: "youtube_refresh",
            expiresAt: now.addingTimeInterval(3_600),
            clientID: "youtube-client.apps.googleusercontent.com"
        ),
        setupValues: [PluginOAuth.clientIDSetupFieldKey: "youtube-client.apps.googleusercontent.com"],
        for: plugin,
        service: PluginRuntimeService(store: store, credentialStore: nil),
        credentialStore: credentials,
        now: now
    )
    let account = try #require(try store.accountConfigurations(pluginID: "com.status.youtube").first)
    let channelFixture = try Data(contentsOf: bundledPluginDirectory(pluginID: "com.status.youtube").appendingPathComponent("fixtures/list_my_channels.json"))
    let uploadFixture = try Data(contentsOf: bundledPluginDirectory(pluginID: "com.status.youtube").appendingPathComponent("fixtures/list_recent_uploads.json"))
    let transport = BundledProviderTransport(expectedAuthorization: "Bearer youtube_access") { request in
        let query = request.url.query ?? ""
        if request.url.path == "/youtube/v3/channels" {
            #expect(query.contains("mine=true"))
            return PluginHTTPResponse(data: channelFixture, statusCode: 200, url: request.url)
        }
        if request.url.path == "/youtube/v3/search" {
            #expect(query.contains("forMine=true"))
            #expect(query.contains("type=video"))
            return PluginHTTPResponse(data: uploadFixture, statusCode: 200, url: request.url)
        }
        Issue.record("Unexpected YouTube request URL: \(request.url.absoluteString)")
        return PluginHTTPResponse(data: Data("{}".utf8), statusCode: 404, url: request.url)
    }
    let service = PluginRuntimeService(store: store, transport: transport, credentialStore: credentials)

    let jobs = try service.enqueueManualConfiguredPluginRuns(pluginID: "com.status.youtube", accountID: account.id, now: now)
    var resourceCount = 0
    var eventTypes: [String] = []
    var metricCount = 0
    for job in jobs {
        let result = try await service.runQueuedPluginJob(jobID: job.id, now: now)
        resourceCount += result.mappingOutput.resources.count
        eventTypes.append(contentsOf: result.mappingOutput.events.map(\.type))
        metricCount += result.mappingOutput.metrics.count
    }

    #expect(jobs.map(\.triggerID) == ["trg_com_status_youtube_refresh_channels", "trg_com_status_youtube_refresh_recent_uploads"])
    #expect(resourceCount == 2)
    #expect(eventTypes.sorted() == ["youtube.channel.visibility_limited", "youtube.video.published"])
    #expect(metricCount == 3)
    #expect(try store.resources(pluginID: "com.status.youtube", accountID: account.id).map(\.type).sorted() == ["channel", "video"])
    #expect(try store.statusItemCount() == 1)
}

@Test func bundledGooglePlayPluginMapsReviewsAndMetrics() throws {
    let database = try temporaryBundledPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-bundled-\(UUID().uuidString)", isDirectory: true)
    let installer = BundledPluginInstaller(store: store, installRoot: installRoot)
    _ = try installer.install(pluginID: "com.status.googleplay", installedAt: Date(timeIntervalSince1970: 1_783_433_520))
    let definition = try #require(try store.installedPluginDefinition(pluginID: "com.status.googleplay"))
    let capturedAt = Date(timeIntervalSince1970: 1_783_433_520)

    let output = try PluginMappingExecutor.execute(
        definition.mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.googleplay",
            accountID: "acct_play",
            provider: "com.status.googleplay",
            requestID: "list_reviews",
            payload: decodeBundledMappingJSON("""
            {
              "reviews": [
                {
                  "reviewId": "gp_review_1",
                  "comments": [
                    {
                      "userComment": {
                        "text": "Login broke after the update.",
                        "starRating": 1,
                        "reviewerLanguage": "en",
                        "appVersionName": "2.3.0",
                        "androidOsVersion": "34",
                        "lastModified": {
                          "seconds": "1783433520",
                          "nanos": 0
                        }
                      }
                    }
                  ]
                }
              ]
            }
            """),
            capturedAt: capturedAt,
            account: .object(["packageName": .string("com.status.app")])
        )
    )

    #expect(output.resources.map { $0.resource.id } == ["acct_play:gp_review_1"])
    #expect(output.resources[0].resource.name == "Login broke after the update.")
    #expect(output.resources[0].state["packageName"] == "com.status.app")
    #expect(output.resources[0].state["starRating"] == "1")
    #expect(output.resources[0].resource.actionURL?.absoluteString == "https://play.google.com/console/developers/app/app-dashboard?packageName=com.status.app")
    #expect(output.events.map { $0.type } == [
        "googleplay.review.received",
        "googleplay.review.needs_attention"
    ])
    #expect(output.events[0].summary == "1 star review for com.status.app.")
    #expect(output.events[0].severity == Severity.warning)
    #expect(output.events[1].summary == "com.status.app received a 1 star review.")
    #expect(output.events[1].severity == Severity.warning)
    #expect(output.metrics.map { $0.metric.id } == ["acct_play:gp_review_1:metric:review_rating"])
    #expect(output.metrics[0].metric.value == "1")
}

@Test func bundledPluginFixturesMapThroughNativeEngine() throws {
    let capturedAt = Date(timeIntervalSince1970: 1_783_433_520)
    let cases: [BundledFixtureMappingCase] = [
        BundledFixtureMappingCase(
            pluginID: "com.status.appstoreconnect",
            requestID: "list_apps",
            expectedResourceCount: 1
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.appstoreconnect",
            requestID: "list_app_store_versions",
            expectedEventTypes: ["app.review.rejected", "app.version.ready_for_sale"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.github",
            requestID: "list_repository_activity",
            expectedResourceCount: 1,
            expectedEventTypes: ["github.pull_request.opened"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.github",
            requestID: "list_workflow_runs",
            expectedEventTypes: ["github.workflow.failed"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.gitlab",
            requestID: "get_project",
            expectedResourceCount: 1,
            account: ["projectId": "278964"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.gitlab",
            requestID: "list_pipelines",
            expectedEventTypes: ["gitlab.pipeline.failed"],
            account: ["projectId": "278964"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.gitlab",
            requestID: "list_project_events",
            expectedEventTypes: ["gitlab.merge_request.opened", "gitlab.issue.opened"],
            account: ["projectId": "278964"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.googleplay",
            requestID: "list_reviews",
            expectedResourceCount: 2,
            expectedEventTypes: ["googleplay.review.received", "googleplay.review.received", "googleplay.review.needs_attention"],
            expectedMetricCount: 2,
            account: ["packageName": "com.example.app"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.jira",
            requestID: "search_project_issues",
            expectedResourceCount: 2,
            expectedEventTypes: ["jira.issue.open"],
            account: ["site": "example.atlassian.net", "projectKey": "STATUS"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.website",
            requestID: "check_site",
            expectedResourceCount: 1,
            expectedEventTypes: ["website.down"],
            account: ["host": "status.example.com"]
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.youtube",
            requestID: "list_my_channels",
            expectedResourceCount: 1,
            expectedEventTypes: ["youtube.channel.visibility_limited"],
            expectedMetricCount: 3
        ),
        BundledFixtureMappingCase(
            pluginID: "com.status.youtube",
            requestID: "list_recent_uploads",
            expectedResourceCount: 1,
            expectedEventTypes: ["youtube.video.published"]
        )
    ]

    for testCase in cases {
        let pluginDirectory = bundledPluginDirectory(pluginID: testCase.pluginID)
        let definition = try PluginPackageDefinition.decode(from: try PluginPackageBuilder.packageData(fromDirectory: pluginDirectory))
        let fixtureData = try Data(contentsOf: pluginDirectory.appendingPathComponent("fixtures/\(testCase.requestID).json"))
        let payload = try JSONDecoder().decode(MappingJSONValue.self, from: fixtureData)
        let output = try PluginMappingExecutor.execute(
            definition.mappings,
            input: PluginMappingExecutionInput(
                pluginID: testCase.pluginID,
                accountID: testCase.accountID,
                provider: testCase.pluginID,
                requestID: testCase.requestID,
                payload: payload,
                capturedAt: capturedAt,
                account: .object(testCase.account.mapValues(MappingJSONValue.string))
            )
        )

        #expect(output.resources.count == testCase.expectedResourceCount, "\(testCase.pluginID) \(testCase.requestID) resource count")
        #expect(output.events.map(\.type) == testCase.expectedEventTypes, "\(testCase.pluginID) \(testCase.requestID) event types")
        #expect(output.metrics.count == testCase.expectedMetricCount, "\(testCase.pluginID) \(testCase.requestID) metric count")
        #expect(output.warnings.isEmpty, "\(testCase.pluginID) \(testCase.requestID) warnings")
    }
}

private func decodeBundledMappingJSON(_ string: String) throws -> MappingJSONValue {
    try JSONDecoder().decode(MappingJSONValue.self, from: Data(string.utf8))
}

private struct BundledFixtureMappingCase {
    var pluginID: String
    var requestID: String
    var expectedResourceCount: Int
    var expectedEventTypes: [String]
    var expectedMetricCount: Int
    var account: [String: String]

    var accountID: String {
        "acct_" + pluginID
            .replacingOccurrences(of: "com.status.", with: "")
            .replacingOccurrences(of: ".", with: "_")
    }

    init(
        pluginID: String,
        requestID: String,
        expectedResourceCount: Int = 0,
        expectedEventTypes: [String] = [],
        expectedMetricCount: Int = 0,
        account: [String: String] = [:]
    ) {
        self.pluginID = pluginID
        self.requestID = requestID
        self.expectedResourceCount = expectedResourceCount
        self.expectedEventTypes = expectedEventTypes
        self.expectedMetricCount = expectedMetricCount
        self.account = account
    }
}

private func bundledPluginDirectory(pluginID: String) -> URL {
    let name = pluginID.replacingOccurrences(of: "com.status.", with: "")
    return repositoryRoot().appendingPathComponent("plugins/bundled/\(name)", isDirectory: true)
}

private func temporaryBundledPluginDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    return database
}

private func grantBundledPermissions(_ permissions: [PluginPermission], pluginID: String, store: StatusPersistenceStore, at date: Date) throws {
    for permission in permissions {
        try store.setPluginPermission(pluginID: pluginID, permission: permission, granted: true, grantedAt: date)
    }
}

private struct BundledProviderTransport: PluginRequestHTTPTransport {
    var expectedAuthorization: String
    var responseForRequest: @Sendable (PluginHTTPRequest) throws -> PluginHTTPResponse

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        #expect(request.headers["Authorization"] == expectedAuthorization)
        return try responseForRequest(request)
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
