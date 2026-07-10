import Foundation
import Testing
@testable import StatusCore

@Test func registryClientBuildsCompatibilityQueryAndParsesPluginList() async throws {
    let transport = FakeRegistryTransport(responses: [
        "/v1/plugins?platform=macOS&coreVersion=0.1.0": pluginListJSON
    ])
    let client = PluginRegistryClient(
        baseURL: try #require(URL(string: "https://status-registry.hakobs.com")),
        transport: transport
    )

    let plugins = try await client.plugins(platform: .macOS, coreVersion: "0.1.0")

    #expect(transport.requestedPaths == ["/v1/plugins?platform=macOS&coreVersion=0.1.0"])
    #expect(plugins.map(\.id) == ["com.status.github"])
    #expect(plugins.first?.permissions == [.network])
    #expect(plugins.first?.iconSvg?.contains("<svg") == true)
}

@Test func registryClientParsesPluginDetailVersionsAndRevocations() async throws {
    let transport = FakeRegistryTransport(responses: [
        "/v1/plugins/com.status.github": pluginDetailJSON,
        "/v1/plugins/com.status.github/versions": versionsJSON,
        "/v1/revocations": revocationsJSON
    ])
    let client = PluginRegistryClient(
        baseURL: try #require(URL(string: "https://status-registry.hakobs.com")),
        transport: transport
    )

    let detail = try await client.plugin(id: "com.status.github")
    let versions = try await client.versions(pluginID: "com.status.github")
    let revocations = try await client.revocations()

    #expect(detail.id == "com.status.github")
    #expect(detail.versions.first?.hasLocalVerificationMaterial == true)
    #expect(versions.first?.version == "0.1.0")
    #expect(revocations.revokedPlugins == ["com.status.bad"])
}

private final class FakeRegistryTransport: RegistryHTTPTransport, @unchecked Sendable {
    private let responses: [String: String]
    private(set) var requestedPaths: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> Data {
        let path = url.query.map { "\(url.path)?\($0)" } ?? url.path
        requestedPaths.append(path)
        guard let response = responses[path] else {
            throw PluginRegistryError.httpStatus(404)
        }
        return Data(response.utf8)
    }
}

private let pluginListJSON = """
{
  "schemaVersion": "1.0.0",
  "generatedAt": "2026-07-07T12:00:00Z",
  "plugins": [
    {
      "id": "com.status.github",
      "name": "GitHub",
      "summary": "Track workflow failures.",
      "description": "Read-only GitHub events.",
      "category": "developer",
      "icon": "sf:chevron.left.slash.chevron.right",
      "iconSvg": "<svg xmlns=\\"http://www.w3.org/2000/svg\\"></svg>",
      "accentColor": "#181A20",
      "author": {
        "name": "Status Foundry",
        "publisherId": "status-foundry",
        "websitePath": "/publishers/status-foundry/",
        "externalUrl": "https://github.com/statusfoundry",
        "repositoryUrl": "https://github.com/statusfoundry/status"
      },
      "trustLevel": "official",
      "latestVersion": "0.1.0",
      "platforms": ["macOS", "iOS"],
      "permissions": ["network"],
      "domains": ["api.github.com"]
    }
  ]
}
"""

private let pluginDetailJSON = """
{
  "id": "com.status.github",
  "name": "GitHub",
  "summary": "Track workflow failures.",
  "description": "Read-only GitHub events.",
  "category": "developer",
  "icon": "sf:chevron.left.slash.chevron.right",
  "iconSvg": "<svg xmlns=\\"http://www.w3.org/2000/svg\\"></svg>",
  "accentColor": "#181A20",
  "author": {
    "name": "Status Foundry",
    "publisherId": "status-foundry",
    "websitePath": "/publishers/status-foundry/",
    "externalUrl": "https://github.com/statusfoundry",
    "repositoryUrl": "https://github.com/statusfoundry/status"
  },
  "trustLevel": "official",
  "permissions": ["network"],
  "domains": ["api.github.com"],
  "versions": [
    {
      "version": "0.1.0",
      "minCoreVersion": "0.1.0",
      "platforms": ["macOS", "iOS"],
      "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/com.status.github-0.1.0.statusplugin.zip",
      "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/manifest.json",
      "sha256": "dcd4260b527a28d62ad2a956b00c4f5616416b2fdc0506e6fe5f6b616f5df5aa",
      "signature": "dev-signature",
      "signedBy": "status-foundry-dev",
      "releasedAt": "2026-07-07T12:00:00Z"
    }
  ]
}
"""

private let versionsJSON = """
{
  "pluginId": "com.status.github",
  "versions": [
    {
      "version": "0.1.0",
      "minCoreVersion": "0.1.0",
      "platforms": ["macOS", "iOS"],
      "packageUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/com.status.github-0.1.0.statusplugin.zip",
      "manifestUrl": "https://status-registry.hakobs.com/plugins/com.status.github/0.1.0/manifest.json",
      "sha256": "dcd4260b527a28d62ad2a956b00c4f5616416b2fdc0506e6fe5f6b616f5df5aa",
      "signature": "dev-signature",
      "signedBy": "status-foundry-dev",
      "releasedAt": "2026-07-07T12:00:00Z"
    }
  ]
}
"""

private let revocationsJSON = """
{
  "schemaVersion": "1.0.0",
  "generatedAt": "2026-07-07T12:00:00Z",
  "revokedPlugins": ["com.status.bad"],
  "revokedVersions": [],
  "revokedHashes": [],
  "revokedSigningKeys": []
}
"""
