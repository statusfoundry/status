import Foundation
import Testing
@testable import StatusCore

@Test func localPluginInstallerInstallsMockOperationsPluginAsLocalDev() throws {
    let database = try temporaryLocalPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-local-plugins-\(UUID().uuidString)", isDirectory: true)
    let installer = LocalPluginInstaller(store: store, installRoot: installRoot)
    let pluginDirectory = repositoryRoot()
        .appendingPathComponent("plugins/examples/mock-operations", isDirectory: true)
    let now = Date(timeIntervalSince1970: 1_783_433_520)

    let result = try installer.install(pluginDirectory: pluginDirectory, installedAt: now)

    #expect(result.plugin.id == "com.status.example.mockops")
    #expect(result.plugin.trustLevel == .localDev)
    #expect(result.version.signature == nil)
    #expect(result.version.signedBy == "local-dev")
    #expect(result.warnings == [
        .unsignedLocalDevPlugin(
            pluginID: "com.status.example.mockops",
            permissions: [.network, .backgroundRefresh, .localNotificationSuggestion, .writeActions],
            domains: ["example.com"]
        )
    ])
    #expect(try store.installedPluginDefinition(pluginID: result.plugin.id)?.actions.map(\.id) == ["mock.postWebhook"])
    #expect(try store.installedPluginDefinition(pluginID: result.plugin.id)?.views.map(\.id) == ["overview"])
}

@Test func localPluginInstallerReportsValidationDiagnosticsForInvalidLocalPlugin() throws {
    let database = try temporaryLocalPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-local-invalid-install-\(UUID().uuidString)", isDirectory: true)
    let pluginDirectory = try writeInvalidLocalPluginFixture()
    let installer = LocalPluginInstaller(store: store, installRoot: installRoot)

    let report = installer.validate(pluginDirectory: pluginDirectory)

    #expect(report.isValid == false)
    #expect(report.errors.map(\.file) == ["manifest.json"])
    #expect(report.errors.map(\.message) == ["Plugins with network permission must declare domains."])
    #expect(report.warnings.map(\.message) == [
        "Local-dev plugins are unsigned. Review permissions and domains before enabling automation."
    ])
    #expect(report.formattedSummary.contains("Error in manifest.json: Plugins with network permission must declare domains."))
    #expect(report.formattedSummary.contains("Warning in manifest.json: Local-dev plugins are unsigned."))

    #expect(throws: LocalPluginInstallerError.validationFailed(report)) {
        _ = try installer.install(pluginDirectory: pluginDirectory)
    }
}

@Test func mockOperationsPluginFixtureMapsThroughNativeEngine() throws {
    let pluginDirectory = repositoryRoot()
        .appendingPathComponent("plugins/examples/mock-operations", isDirectory: true)
    let packageData = try PluginPackageBuilder.packageData(fromDirectory: pluginDirectory)
    let definition = try PluginPackageDefinition.decode(from: packageData)
    let fixtureData = try Data(contentsOf: pluginDirectory.appendingPathComponent("fixtures/fetch_status.json"))
    let payload = try JSONDecoder().decode(MappingJSONValue.self, from: fixtureData)

    let output = try PluginMappingExecutor.execute(
        definition.mappings,
        input: PluginMappingExecutionInput(
            pluginID: "com.status.example.mockops",
            accountID: "acct_mock",
            provider: "com.status.example.mockops",
            requestID: "fetch_status",
            payload: payload,
            capturedAt: Date(timeIntervalSince1970: 1_783_433_520)
        )
    )

    #expect(output.resources.map(\.resource.id) == ["acct_mock:api", "acct_mock:worker"])
    #expect(output.resources.map(\.state["state"]) == ["degraded", "healthy"])
    #expect(output.events.map(\.type) == [
        "mock.service.degraded",
        "mock.service.recovered",
        "mock.error_rate.high"
    ])
    #expect(output.events.map(\.resourceID) == ["acct_mock:api", "acct_mock:worker", "acct_mock:api"])
    #expect(output.metrics.map(\.metric.id) == [
        "acct_mock:api:metric:error_rate_percent",
        "acct_mock:worker:metric:error_rate_percent"
    ])
    #expect(output.metrics.map(\.pointValue) == [7.5, 0.2])
}

@Test func pluginPackageBuilderIncludesReadmeWhenPresent() throws {
    let pluginDirectory = repositoryRoot()
        .appendingPathComponent("plugins/examples/mock-operations", isDirectory: true)
    let packageData = try PluginPackageBuilder.packageData(fromDirectory: pluginDirectory)
    let definition = try PluginPackageDefinition.decode(from: packageData)

    #expect(definition.readmeMarkdown?.contains("# Mock Operations") == true)
}

@Test func pluginDeveloperPreviewMapsFixtureWithoutPersistingOutput() throws {
    let database = try temporaryLocalPluginDatabase()
    let store = StatusPersistenceStore(database: database)
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-local-preview-\(UUID().uuidString)", isDirectory: true)
    let installer = LocalPluginInstaller(store: store, installRoot: installRoot)
    let pluginDirectory = repositoryRoot()
        .appendingPathComponent("plugins/examples/mock-operations", isDirectory: true)
    _ = try installer.install(pluginDirectory: pluginDirectory, installedAt: Date(timeIntervalSince1970: 1_783_433_520))
    let fixtureData = try Data(contentsOf: pluginDirectory.appendingPathComponent("fixtures/fetch_status.json"))

    let result = try PluginDeveloperPreviewer(store: store).previewFixture(
        pluginID: "com.status.example.mockops",
        requestID: "fetch_status",
        fixtureData: fixtureData,
        capturedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )

    #expect(result.summary == "2 resources, 3 events, 2 metrics")
    #expect(result.resources.map(\.resource.id) == ["preview_com_status_example_mockops:api", "preview_com_status_example_mockops:worker"])
    #expect(result.events.map(\.type) == [
        "mock.service.degraded",
        "mock.service.recovered",
        "mock.error_rate.high"
    ])
    #expect(try store.resources(pluginID: "com.status.example.mockops").isEmpty)
    #expect(try store.recentEvents(limit: 10).isEmpty)
    #expect(try store.metrics().isEmpty)
}

private func temporaryLocalPluginDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    return database
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func writeInvalidLocalPluginFixture() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-invalid-plugin-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("""
    {
      "id": "com.status.invalid.local",
      "name": "Invalid Local",
      "version": "0.1.0",
      "author": { "name": "Status Foundry" },
      "category": "developer",
      "description": "Invalid plugin fixture.",
      "icon": "sf:exclamationmark.triangle",
      "accentColor": "#EF4444",
      "minCoreVersion": "0.1.0",
      "platforms": ["macOS"],
      "permissions": ["network"],
      "domains": []
    }
    """.utf8).write(to: directory.appendingPathComponent("manifest.json"))
    try Data("""
    {
      "requests": {
        "check": {
          "method": "GET",
          "url": "https://example.com/status"
        }
      }
    }
    """.utf8).write(to: directory.appendingPathComponent("requests.json"))
    try Data("""
    {
      "resources": [],
      "events": []
    }
    """.utf8).write(to: directory.appendingPathComponent("mappings.json"))
    return directory
}
