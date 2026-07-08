import Foundation

public struct InstalledPlugin: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var author: String
    public var description: String
    public var category: String
    public var iconPath: String?
    public var trustLevel: PluginTrustLevel
    public var installedVersion: String
    public var installPath: String
    public var enabled: Bool
    public var auth: PackagedPluginAuth?
    public var setup: PackagedPluginSetup?
    public var installedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        author: String,
        description: String,
        category: String,
        iconPath: String? = nil,
        trustLevel: PluginTrustLevel,
        installedVersion: String,
        installPath: String,
        enabled: Bool = true,
        auth: PackagedPluginAuth? = nil,
        setup: PackagedPluginSetup? = nil,
        installedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.description = description
        self.category = category
        self.iconPath = iconPath
        self.trustLevel = trustLevel
        self.installedVersion = installedVersion
        self.installPath = installPath
        self.enabled = enabled
        self.auth = auth
        self.setup = setup
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

public struct InstalledPluginVersion: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var pluginID: String
    public var version: String
    public var minCoreVersion: String
    public var platforms: [PluginPlatform]
    public var domains: [String]
    public var sha256: String
    public var signature: String?
    public var manifest: PluginManifest
    public var packagePath: String?
    public var revoked: Bool
    public var installedAt: Date

    public init(
        id: String,
        pluginID: String,
        version: String,
        minCoreVersion: String,
        platforms: [PluginPlatform],
        domains: [String],
        sha256: String,
        signature: String? = nil,
        manifest: PluginManifest,
        packagePath: String? = nil,
        revoked: Bool = false,
        installedAt: Date
    ) {
        self.id = id
        self.pluginID = pluginID
        self.version = version
        self.minCoreVersion = minCoreVersion
        self.platforms = platforms
        self.domains = domains
        self.sha256 = sha256
        self.signature = signature
        self.manifest = manifest
        self.packagePath = packagePath
        self.revoked = revoked
        self.installedAt = installedAt
    }
}

public struct InstalledPluginPermission: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var pluginID: String
    public var permission: PluginPermission
    public var granted: Bool
    public var grantedAt: Date?

    public init(id: String, pluginID: String, permission: PluginPermission, granted: Bool, grantedAt: Date? = nil) {
        self.id = id
        self.pluginID = pluginID
        self.permission = permission
        self.granted = granted
        self.grantedAt = grantedAt
    }
}

public struct PluginInstallRecord: Equatable, Sendable {
    public var manifest: PluginManifest
    public var trustLevel: PluginTrustLevel
    public var installPath: String
    public var packagePath: String?
    public var verification: PluginPackageVerificationResult
    public var signature: String?
    public var packageDefinition: PluginPackageDefinition
    public var installedAt: Date

    public init(
        manifest: PluginManifest,
        trustLevel: PluginTrustLevel,
        installPath: String,
        packagePath: String? = nil,
        verification: PluginPackageVerificationResult,
        signature: String? = nil,
        packageDefinition: PluginPackageDefinition = PluginPackageDefinition(),
        installedAt: Date
    ) {
        self.manifest = manifest
        self.trustLevel = trustLevel
        self.installPath = installPath
        self.packagePath = packagePath
        self.verification = verification
        self.signature = signature
        self.packageDefinition = packageDefinition
        self.installedAt = installedAt
    }
}

public struct PluginRevocationApplicationResult: Equatable, Sendable {
    public var revokedVersions: [InstalledPluginVersion]
    public var disabledPluginIDs: [String]

    public init(revokedVersions: [InstalledPluginVersion], disabledPluginIDs: [String]) {
        self.revokedVersions = revokedVersions
        self.disabledPluginIDs = disabledPluginIDs
    }
}

public enum PluginInstallationError: Error, Equatable, LocalizedError, Sendable {
    case verificationPluginMismatch(expected: String, actual: String)
    case verificationVersionMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .verificationPluginMismatch(let expected, let actual):
            "Plugin verification result belongs to \(actual), expected \(expected)."
        case .verificationVersionMismatch(let expected, let actual):
            "Plugin verification result is for version \(actual), expected \(expected)."
        }
    }
}
