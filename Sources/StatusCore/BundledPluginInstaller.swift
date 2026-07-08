import Foundation

public struct BundledPluginPackage: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var version: String
    public var trustLevel: PluginTrustLevel
    public var minCoreVersion: String
    public var platforms: [PluginPlatform]
    public var domains: [String]
    public var sha256: String
    public var signature: String?
    public var signedBy: String?
    public var releasedAt: Date
    public var packageResourceName: String
    public var manifestResourceName: String
}

public struct BundledPluginCatalog: Decodable, Equatable, Sendable {
    public var schemaVersion: String
    public var generatedAt: Date
    public var plugins: [BundledPluginPackage]
}

public enum BundledPluginInstallerError: Error, Equatable, LocalizedError, Sendable {
    case indexUnavailable
    case pluginUnavailable(String)
    case resourceUnavailable(String)
    case installRecordMissing(String, String)

    public var errorDescription: String? {
        switch self {
        case .indexUnavailable:
            "Bundled plugin index is unavailable."
        case .pluginUnavailable(let pluginID):
            "Bundled plugin is unavailable: \(pluginID)"
        case .resourceUnavailable(let resource):
            "Bundled plugin resource is unavailable: \(resource)"
        case .installRecordMissing(let pluginID, let version):
            "Bundled plugin install record was not written for \(pluginID) \(version)."
        }
    }
}

public final class BundledPluginInstaller: @unchecked Sendable {
    private let store: StatusPersistenceStore
    private let installRoot: URL
    private let bundle: Bundle
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(
        store: StatusPersistenceStore,
        installRoot: URL,
        bundle: Bundle? = nil,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.installRoot = installRoot
        self.bundle = bundle ?? .module
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func availablePlugins() throws -> [BundledPluginPackage] {
        try catalog().plugins
    }

    @discardableResult
    public func installAll(installedAt: Date = Date()) throws -> [PluginInstallResult] {
        try availablePlugins().map { package in
            try install(pluginID: package.id, installedAt: installedAt)
        }
    }

    @discardableResult
    public func install(pluginID: String, installedAt: Date = Date()) throws -> PluginInstallResult {
        guard let package = try availablePlugins().first(where: { $0.id == pluginID }) else {
            throw BundledPluginInstallerError.pluginUnavailable(pluginID)
        }
        return try install(package, installedAt: installedAt)
    }

    private func install(_ package: BundledPluginPackage, installedAt: Date) throws -> PluginInstallResult {
        if let existingPlugin = try store.installedPlugin(id: package.id),
           existingPlugin.installedVersion == package.version,
           let existingVersion = try store.installedPluginVersions(pluginID: package.id).first(where: { $0.version == package.version }),
           existingVersion.sha256 == package.sha256 {
            return PluginInstallResult(
                plugin: existingPlugin,
                version: existingVersion,
                verification: PluginPackageVerificationResult(
                    pluginID: package.id,
                    version: package.version,
                    sha256: package.sha256,
                    signedBy: package.signedBy ?? "bundled"
                )
            )
        }

        let packageData = try data(resourceName: package.packageResourceName)
        let manifestData = try data(resourceName: package.manifestResourceName)
        let manifest = try decoder.decode(PluginManifest.self, from: manifestData)
        let version = RegistryPluginVersion(
            pluginId: package.id,
            version: package.version,
            minCoreVersion: package.minCoreVersion,
            platforms: package.platforms,
            packageUrl: URL(fileURLWithPath: package.packageResourceName),
            manifestUrl: URL(fileURLWithPath: package.manifestResourceName),
            sha256: package.sha256,
            signature: package.signature,
            signedBy: package.signedBy,
            releasedAt: package.releasedAt
        )
        let verification = try PluginPackageVerifier.verify(
            packageData: packageData,
            version: version,
            revocations: RegistryRevocationsResponse(
                schemaVersion: "1.0.0",
                generatedAt: installedAt,
                revokedPlugins: [],
                revokedVersions: [],
                revokedHashes: [],
                revokedSigningKeys: []
            )
        )
        let packageDefinition = try PluginPackageDefinition.decode(from: packageData)
        let installDirectory = installRoot
            .appendingPathComponent(manifest.id, isDirectory: true)
            .appendingPathComponent(manifest.version, isDirectory: true)
        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let installedPackageURL = installDirectory.appendingPathComponent("\(manifest.id)-\(manifest.version).statusplugin.zip")
        let installedManifestURL = installDirectory.appendingPathComponent("manifest.json")
        try packageData.write(to: installedPackageURL, options: .atomic)
        try manifestData.write(to: installedManifestURL, options: .atomic)

        try store.installPlugin(
            PluginInstallRecord(
                manifest: manifest,
                trustLevel: package.trustLevel,
                installPath: installDirectory.path,
                packagePath: installedPackageURL.path,
                verification: verification,
                signature: package.signature,
                packageDefinition: packageDefinition,
                installedAt: installedAt
            )
        )

        guard let plugin = try store.installedPlugin(id: manifest.id),
              let installedVersion = try store.installedPluginVersions(pluginID: manifest.id).first(where: { $0.version == manifest.version }) else {
            throw BundledPluginInstallerError.installRecordMissing(manifest.id, manifest.version)
        }
        return PluginInstallResult(plugin: plugin, version: installedVersion, verification: verification)
    }

    private func catalog() throws -> BundledPluginCatalog {
        let data = try data(resourceName: "index.json")
        return try decoder.decode(BundledPluginCatalog.self, from: data)
    }

    private func data(resourceName: String) throws -> Data {
        guard let root = bundle.resourceURL else {
            throw BundledPluginInstallerError.indexUnavailable
        }
        let subdirectoryURL = root
            .appendingPathComponent("BundledPlugins", isDirectory: true)
            .appendingPathComponent(resourceName)
        let rootURL = root.appendingPathComponent(resourceName)
        let url = fileManager.fileExists(atPath: subdirectoryURL.path) ? subdirectoryURL : rootURL
        guard fileManager.fileExists(atPath: url.path) else {
            throw BundledPluginInstallerError.resourceUnavailable(resourceName)
        }
        return try Data(contentsOf: url)
    }
}
