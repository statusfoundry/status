import Foundation

public enum PluginTrustLevel: String, Codable, Equatable, Sendable {
    case official
    case verifiedThirdParty = "verified-third-party"
    case localDev = "local-dev"
}

public struct RegistryPluginSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var description: String
    public var category: String
    public var icon: String?
    public var iconSvg: String?
    public var accentColor: String?
    public var author: PluginAuthor
    public var trustLevel: PluginTrustLevel
    public var latestVersion: String?
    public var platforms: [PluginPlatform]
    public var permissions: [PluginPermission]
    public var domains: [String]
}

public struct RegistryPluginDetail: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var description: String
    public var category: String
    public var icon: String?
    public var iconSvg: String?
    public var accentColor: String?
    public var author: PluginAuthor
    public var trustLevel: PluginTrustLevel
    public var permissions: [PluginPermission]
    public var domains: [String]
    public var versions: [RegistryPluginVersion]
}

public struct RegistryPluginVersion: Codable, Equatable, Sendable {
    public var pluginId: String?
    public var version: String
    public var minCoreVersion: String
    public var platforms: [PluginPlatform]
    public var packageUrl: URL
    public var manifestUrl: URL
    public var sha256: String
    public var signature: String?
    public var signedBy: String?
    public var releasedAt: Date

    public var hasLocalVerificationMaterial: Bool {
        sha256.isEmpty == false && signature?.isEmpty == false
    }
}

public struct RegistryPluginListResponse: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var generatedAt: Date
    public var plugins: [RegistryPluginSummary]
}

public struct RegistryPluginVersionsResponse: Codable, Equatable, Sendable {
    public var pluginId: String
    public var versions: [RegistryPluginVersion]
}

public struct RegistrySnapshotResponse: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var generatedAt: Date
    public var plugins: [RegistryPluginDetail]
}

public struct RegistryRevocationsResponse: Codable, Equatable, Sendable {
    public struct RevokedVersion: Codable, Equatable, Sendable {
        public var pluginId: String
        public var version: String
    }

    public var schemaVersion: String
    public var generatedAt: Date
    public var revokedPlugins: [String]
    public var revokedVersions: [RevokedVersion]
    public var revokedHashes: [String]
    public var revokedSigningKeys: [String]
}

public protocol RegistryHTTPTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionRegistryTransport: RegistryHTTPTransport {
    public init() {}

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) == false {
            throw PluginRegistryError.httpStatus(response.statusCode)
        }
        return data
    }
}

public enum PluginRegistryError: Error, Equatable, LocalizedError, Sendable {
    case invalidBaseURL
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Registry base URL is invalid."
        case .httpStatus(let status):
            "Registry request failed with HTTP \(status)."
        }
    }
}

public struct PluginRegistryClient: Sendable {
    private let baseURL: URL
    private let transport: RegistryHTTPTransport
    private let decoder: JSONDecoder

    public init(baseURL: URL, transport: RegistryHTTPTransport = URLSessionRegistryTransport()) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func plugins(platform: PluginPlatform? = nil, coreVersion: String? = nil) async throws -> [RegistryPluginSummary] {
        let response = try await get(
            RegistryPluginListResponse.self,
            path: "/v1/plugins",
            queryItems: compatibilityQuery(platform: platform, coreVersion: coreVersion)
        )
        return response.plugins
    }

    public func plugin(id: String, platform: PluginPlatform? = nil, coreVersion: String? = nil) async throws -> RegistryPluginDetail {
        try await get(
            RegistryPluginDetail.self,
            path: "/v1/plugins/\(id)",
            queryItems: compatibilityQuery(platform: platform, coreVersion: coreVersion)
        )
    }

    public func versions(pluginID: String, platform: PluginPlatform? = nil, coreVersion: String? = nil) async throws -> [RegistryPluginVersion] {
        let response = try await get(
            RegistryPluginVersionsResponse.self,
            path: "/v1/plugins/\(pluginID)/versions",
            queryItems: compatibilityQuery(platform: platform, coreVersion: coreVersion)
        )
        return response.versions
    }

    public func version(pluginID: String, version: String) async throws -> RegistryPluginVersion {
        try await get(RegistryPluginVersion.self, path: "/v1/plugins/\(pluginID)/versions/\(version)")
    }

    public func registry() async throws -> RegistrySnapshotResponse {
        try await get(RegistrySnapshotResponse.self, path: "/v1/registry")
    }

    public func revocations() async throws -> RegistryRevocationsResponse {
        try await get(RegistryRevocationsResponse.self, path: "/v1/revocations")
    }

    private func get<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let data = try await transport.data(from: try url(path: path, queryItems: queryItems))
        return try decoder.decode(T.self, from: data)
    }

    private func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PluginRegistryError.invalidBaseURL
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw PluginRegistryError.invalidBaseURL
        }
        return url
    }

    private func compatibilityQuery(platform: PluginPlatform?, coreVersion: String?) -> [URLQueryItem] {
        [
            platform.map { URLQueryItem(name: "platform", value: $0.rawValue) },
            coreVersion.map { URLQueryItem(name: "coreVersion", value: $0) }
        ].compactMap { $0 }
    }
}
