import Foundation
import Testing
@testable import StatusCore

@Test func pluginRuntimeServiceRunsInstalledWebsitePluginRequest() async throws {
    let database = try temporaryRuntimeDatabase()
    let store = StatusPersistenceStore(database: database)
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let packageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-runtime-\(UUID().uuidString).statusplugin.zip")
    let packageData = runtimeStoredZip(files: [
        ("requests.json", Data("""
        {
          "requests": {
            "check_site": {
              "method": "GET",
              "url": "https://{{host}}",
              "timeoutSeconds": 15
            }
          }
        }
        """.utf8)),
        ("mappings.json", Data("""
        {
          "resources": [
            {
              "type": "website",
              "request": "check_site",
              "id": "{{host}}",
              "name": "{{host}}",
              "actionUrl": "https://{{host}}"
            }
          ],
          "events": [
            {
              "type": "website.down",
              "request": "check_site",
              "when": "$.statusCode >= 500 || $.reachable == false",
              "resourceId": "{{host}}",
              "title": "Website down",
              "summary": "{{host}} is not responding normally.",
              "severity": "critical",
              "actionUrl": "https://{{host}}"
            }
          ]
        }
        """.utf8))
    ])
    try packageData.write(to: packageURL)
    let manifest = PluginManifest(
        id: "com.status.website",
        name: "Website Uptime",
        version: "0.1.0",
        author: "Status Foundry",
        category: "ops",
        description: "Check configured websites.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: packageURL.deletingLastPathComponent().path,
            packagePath: packageURL.path,
            verification: PluginPackageVerificationResult(
                pluginID: manifest.id,
                version: manifest.version,
                sha256: PluginPackageVerifier.sha256Hex(packageData),
                signedBy: "status-foundry-dev"
            ),
            signature: "dev-signature",
            packageDefinition: try PluginPackageDefinition.decode(from: packageData),
            installedAt: now
        )
    )
    let url = try #require(URL(string: "https://status-registry.hakobs.com"))
    let service = PluginRuntimeService(
        store: store,
        transport: RuntimeFakeTransport(responses: [
            url: PluginHTTPResponse(data: Data("Unavailable".utf8), statusCode: 503, url: url)
        ])
    )

    let result = try await service.runInstalledPluginRequest(
        PluginRuntimeRequest(
            pluginID: manifest.id,
            requestID: "check_site",
            accountID: "acct_status_registry",
            accountName: "Status registry",
            variables: ["host": "status-registry.hakobs.com"],
            now: now
        )
    )

    let jobID = "job_com_status_website_check_site_acct_status_registry_1783433520"
    #expect(result.mappingOutput.resources.map(\.resource.id) == ["acct_status_registry:status-registry.hakobs.com"])
    #expect(result.mappingOutput.events.map(\.type) == ["website.down"])
    #expect(try store.account(id: "acct_status_registry")?.displayName == "Status registry")
    #expect(try store.job(id: jobID)?.status == .success)
    #expect(try store.resource(id: "acct_status_registry:status-registry.hakobs.com")?.name == "status-registry.hakobs.com")
    #expect(try store.statusItemCount() == 1)
    #expect(try store.auditEntry(id: "aud_\(jobID)_success")?.status == "success")
}

private struct RuntimeFakeTransport: PluginRequestHTTPTransport {
    var responses: [URL: PluginHTTPResponse]

    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        try #require(responses[request.url])
    }
}

private func temporaryRuntimeDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    let database = try SQLiteDatabase(path: path)
    try StatusDatabaseMigrator.migrate(database)
    return database
}

private func runtimeStoredZip(files: [(String, Data)]) -> Data {
    var archive = Data()
    var centralDirectory = Data()
    var offset: UInt32 = 0

    for (name, data) in files {
        let nameData = Data(name.utf8)
        var localHeader = Data()
        localHeader.appendUInt32LE(0x0403_4b50)
        localHeader.appendUInt16LE(20)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt16LE(0)
        localHeader.appendUInt32LE(0)
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
        centralHeader.appendUInt32LE(0)
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

    let centralOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.appendUInt32LE(0x0605_4b50)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(UInt16(files.count))
    archive.appendUInt16LE(UInt16(files.count))
    archive.appendUInt32LE(UInt32(centralDirectory.count))
    archive.appendUInt32LE(centralOffset)
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
