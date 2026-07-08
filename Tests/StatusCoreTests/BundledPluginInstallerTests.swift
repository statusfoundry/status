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
        "com.status.website"
    ])
    #expect(results.map(\.plugin.id).sorted() == packages.map(\.id).sorted())
    #expect(try store.installedPlugins().map(\.id).sorted() == packages.map(\.id).sorted())
    #expect(try store.installedPlugin(id: "com.status.website")?.setup?.fields.first?.id == "host")
    #expect(try store.triggers().contains { $0.pluginID == "com.status.website" && $0.kind == .manual && $0.requestID == "check_site" })
    #expect(try store.rules().contains { $0.provider == "com.status.website" && $0.eventType == "website.down" })
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

private func temporaryBundledPluginDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    return database
}
