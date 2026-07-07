import Foundation
import Testing
@testable import StatusCore

@Test func pluginInstallerDownloadsVerifiesWritesAndPersistsPlugin() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let manifest = githubManifest()
    let manifestData = try JSONEncoder().encode(manifest)
    let packageData = storedZip(files: [
        ("manifest.json", manifestData),
        ("triggers.json", Data("""
        {
          "triggers": [
            {
              "id": "poll_workflows",
              "type": "cron",
              "label": "Check workflow runs",
              "defaultSchedule": "*/15 * * * *",
              "request": "list_workflow_runs"
            },
            {
              "id": "refresh_activity",
              "type": "manual",
              "label": "Refresh repository activity",
              "request": "list_repository_activity"
            }
          ]
        }
        """.utf8)),
        ("rules.presets.json", Data("""
        {
          "presets": [
            {
              "name": "Notify on failed workflows",
              "when": {
                "eventType": "github.workflow.failed",
                "provider": "com.status.github"
              },
              "if": [
                {
                  "field": "severity",
                  "operator": "matches_severity",
                  "value": "warning"
                }
              ],
              "then": [
                {
                  "action": "status.inbox.add"
                },
                {
                  "action": "notification.show"
                }
              ]
            }
          ]
        }
        """.utf8))
    ])
    let version = RegistryPluginVersion(
        pluginId: manifest.id,
        version: manifest.version,
        minCoreVersion: manifest.minCoreVersion,
        platforms: manifest.platforms,
        packageUrl: try #require(URL(string: "https://status-registry.hakobs.com/package.zip")),
        manifestUrl: try #require(URL(string: "https://status-registry.hakobs.com/manifest.json")),
        sha256: PluginPackageVerifier.sha256Hex(packageData),
        signature: "dev-signature",
        signedBy: "status-foundry-dev",
        releasedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let registry = FakeRegistryMetadataProvider(version: version, revocations: emptyRevocations())
    let transport = FakePackageTransport(responses: [
        version.packageUrl: packageData,
        version.manifestUrl: manifestData
    ])
    let installRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-plugin-installer-\(UUID().uuidString)", isDirectory: true)
    let installer = PluginInstaller(
        registry: registry,
        packageTransport: transport,
        store: store,
        installRoot: installRoot
    )
    let installedAt = Date(timeIntervalSince1970: 1_783_433_520)

    let result = try await installer.install(pluginID: manifest.id, version: manifest.version, trustLevel: .official, installedAt: installedAt)

    #expect(result.plugin.id == manifest.id)
    #expect(result.plugin.installedVersion == manifest.version)
    #expect(result.version.manifest == manifest)
    #expect(result.verification.sha256 == PluginPackageVerifier.sha256Hex(packageData))
    #expect(FileManager.default.fileExists(atPath: result.plugin.installPath + "/manifest.json"))
    #expect(FileManager.default.fileExists(atPath: result.version.packagePath ?? ""))
    #expect(try store.pluginPermissions(pluginID: manifest.id).map(\.permission) == [.backgroundRefresh, .network])

    let triggers = try store.triggers()
    #expect(triggers.map(\.id) == ["trg_com_status_github_poll_workflows", "trg_com_status_github_refresh_activity"])
    #expect(triggers.first?.intervalSeconds == 900)
    #expect(triggers.map(\.requestID) == ["list_workflow_runs", "list_repository_activity"])

    let rules = try store.rules()
    #expect(rules.count == 1)
    #expect(rules[0].enabled == false)
    #expect(rules[0].eventType == "github.workflow.failed")
    #expect(rules[0].conditions == [
        RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("warning"))
    ])
    #expect(rules[0].actions.map(\.action) == ["status.inbox.add", "notification.show"])
}

@Test func pluginInstallerRejectsRevokedPackageBeforePersisting() async throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let manifest = githubManifest()
    let manifestData = try JSONEncoder().encode(manifest)
    let packageData = storedZip(files: [("manifest.json", manifestData)])
    let version = RegistryPluginVersion(
        pluginId: manifest.id,
        version: manifest.version,
        minCoreVersion: manifest.minCoreVersion,
        platforms: manifest.platforms,
        packageUrl: try #require(URL(string: "https://status-registry.hakobs.com/package.zip")),
        manifestUrl: try #require(URL(string: "https://status-registry.hakobs.com/manifest.json")),
        sha256: PluginPackageVerifier.sha256Hex(packageData),
        signature: "dev-signature",
        signedBy: "status-foundry-dev",
        releasedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let registry = FakeRegistryMetadataProvider(
        version: version,
        revocations: RegistryRevocationsResponse(
            schemaVersion: "1.0.0",
            generatedAt: Date(timeIntervalSince1970: 1_783_433_520),
            revokedPlugins: [manifest.id],
            revokedVersions: [],
            revokedHashes: [],
            revokedSigningKeys: []
        )
    )
    let transport = FakePackageTransport(responses: [
        version.packageUrl: packageData,
        version.manifestUrl: manifestData
    ])
    let installer = PluginInstaller(
        registry: registry,
        packageTransport: transport,
        store: store,
        installRoot: FileManager.default.temporaryDirectory.appendingPathComponent("status-plugin-installer-\(UUID().uuidString)", isDirectory: true)
    )

    await #expect(throws: PluginPackageVerificationError.revokedPlugin(manifest.id)) {
        try await installer.install(pluginID: manifest.id, version: manifest.version, trustLevel: .official)
    }
    #expect(try store.installedPlugin(id: manifest.id) == nil)
}

private struct FakeRegistryMetadataProvider: PluginRegistryMetadataProvider {
    var version: RegistryPluginVersion
    var revocations: RegistryRevocationsResponse

    func version(pluginID: String, version: String) async throws -> RegistryPluginVersion {
        self.version
    }

    func revocations() async throws -> RegistryRevocationsResponse {
        revocations
    }
}

private struct FakePackageTransport: RegistryHTTPTransport {
    var responses: [URL: Data]

    func data(from url: URL) async throws -> Data {
        guard let response = responses[url] else {
            throw PluginRegistryError.httpStatus(404)
        }
        return response
    }
}

private func githubManifest() -> PluginManifest {
    PluginManifest(
        id: "com.status.github",
        name: "GitHub",
        version: "0.1.0",
        author: "Status Foundry",
        category: "developer",
        description: "Read-only GitHub status events.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .backgroundRefresh],
        domains: ["api.github.com"]
    )
}

private func emptyRevocations() -> RegistryRevocationsResponse {
    RegistryRevocationsResponse(
        schemaVersion: "1.0.0",
        generatedAt: Date(timeIntervalSince1970: 1_783_433_520),
        revokedPlugins: [],
        revokedVersions: [],
        revokedHashes: [],
        revokedSigningKeys: []
    )
}

private func temporaryDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    return try SQLiteDatabase(path: path)
}

private func storedZip(files: [(String, Data)]) -> Data {
    var archive = Data()
    var centralDirectory = Data()
    var offset: UInt32 = 0

    for (name, data) in files {
        let nameData = Data(name.utf8)
        let checksum: UInt32 = 0

        var localHeader = Data()
        localHeader.appendUInt32LE(0x0403_4b50)
        localHeader.appendUInt16LE(20)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt32LE(checksum)
        localHeader.appendUInt32LE(UInt32(data.count))
        localHeader.appendUInt32LE(UInt32(data.count))
        localHeader.appendUInt16LE(UInt16(nameData.count))
        localHeader.appendUInt16LE(0)
        localHeader.append(nameData)

        var centralHeader = Data()
        centralHeader.appendUInt32LE(0x0201_4b50)
        centralHeader.appendUInt16LE(20)
        centralHeader.appendUInt16LE(20)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt32LE(checksum)
        centralHeader.appendUInt32LE(UInt32(data.count))
        centralHeader.appendUInt32LE(UInt32(data.count))
        centralHeader.appendUInt16LE(UInt16(nameData.count))
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt16LE(0)
        centralHeader.appendUInt32LE(0)
        centralHeader.appendUInt32LE(offset)
        centralHeader.append(nameData)

        archive.append(localHeader)
        archive.append(data)
        centralDirectory.append(centralHeader)
        offset += UInt32(localHeader.count + data.count)
    }

    archive.append(centralDirectory)
    archive.appendUInt32LE(0x0605_4b50)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(UInt16(files.count))
    archive.appendUInt16LE(UInt16(files.count))
    archive.appendUInt32LE(UInt32(centralDirectory.count))
    archive.appendUInt32LE(offset)
    archive.appendUInt16LE(0)
    return archive
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
