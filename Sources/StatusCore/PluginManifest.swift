import Foundation

public enum PluginPlatform: String, Codable, CaseIterable, Sendable {
    case macOS
    case iOS
}

public enum PluginPermission: String, Codable, CaseIterable, Sendable {
    case network
    case keychain
    case oauth
    case apiKey = "api-key"
    case privateKey = "private-key"
    case backgroundRefresh = "background-refresh"
    case pushWebhook = "push-webhook"
    case userConfiguredDomains = "user-configured-domains"
    case writeActions = "write-actions"
    case localNotificationSuggestion = "local-notification-suggestion"
}

public enum PluginValidationError: Error, Equatable, LocalizedError, Sendable {
    case invalidIdentifier(String)
    case invalidVersion(String)
    case emptyField(String)
    case noPlatform
    case noDomainForNetworkPermission
    case domainContainsScheme(String)
    case domainContainsPath(String)
    case domainContainsWildcard(String)
    case undeclaredRequestDomain(String)
    case writeActionWithoutPermission(String)
    case oauthWithoutPermission(String)
    case oauthWithoutKeychain(String)
    case oauthMissingProvider(String)
    case oauthMissingApplicationID(String)
    case oauthMissingConfiguration(String)
    case invalidIcon(String)
    case invalidAccentColor(String)

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let value):
            "Plugin id must be reverse-DNS style: \(value)"
        case .invalidVersion(let value):
            "Plugin version must be semver: \(value)"
        case .emptyField(let field):
            "Plugin manifest field is required: \(field)"
        case .noPlatform:
            "Plugin must support at least one platform."
        case .noDomainForNetworkPermission:
            "Plugins with network permission must declare domains."
        case .domainContainsScheme(let domain):
            "Plugin domains must be hosts, not URLs: \(domain)"
        case .domainContainsPath(let domain):
            "Plugin domains must not contain paths: \(domain)"
        case .domainContainsWildcard(let domain):
            "Plugin domains must not use wildcards in v1: \(domain)"
        case .undeclaredRequestDomain(let domain):
            "Plugin request uses undeclared domain: \(domain)"
        case .writeActionWithoutPermission(let action):
            "Plugin action requires write-actions permission: \(action)"
        case .oauthWithoutPermission(let pluginID):
            "OAuth plugin requires the oauth permission: \(pluginID)"
        case .oauthWithoutKeychain(let pluginID):
            "OAuth plugin requires the keychain permission: \(pluginID)"
        case .oauthMissingProvider(let pluginID):
            "OAuth plugin must declare an auth provider: \(pluginID)"
        case .oauthMissingApplicationID(let pluginID):
            "OAuth plugin must declare a public applicationId/client ID: \(pluginID)"
        case .oauthMissingConfiguration(let pluginID):
            "OAuth plugin must declare authorization and token endpoints: \(pluginID)"
        case .invalidIcon(let value):
            "Plugin icon must be an SF Symbol name, optionally prefixed with sf:: \(value)"
        case .invalidAccentColor(let value):
            "Plugin accentColor must be a #RRGGBB hex color: \(value)"
        }
    }
}

public struct PluginAuthor: Codable, Equatable, Sendable {
    public var name: String
    public var publisherId: String?
    public var websitePath: String?
    public var externalUrl: URL?
    public var repositoryUrl: URL?

    public init(
        name: String,
        publisherId: String? = nil,
        websitePath: String? = nil,
        externalUrl: URL? = nil,
        repositoryUrl: URL? = nil
    ) {
        self.name = name
        self.publisherId = publisherId
        self.websitePath = websitePath
        self.externalUrl = externalUrl
        self.repositoryUrl = repositoryUrl
    }
}

extension PluginAuthor: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(name: value)
    }
}

public struct PluginManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var author: PluginAuthor
    public var category: String
    public var description: String
    public var icon: String?
    public var accentColor: String?
    public var minCoreVersion: String
    public var platforms: [PluginPlatform]
    public var permissions: [PluginPermission]
    public var domains: [String]

    public init(
        id: String,
        name: String,
        version: String,
        author: PluginAuthor,
        category: String,
        description: String,
        icon: String? = "sf:puzzlepiece.extension",
        accentColor: String? = "#F59E0B",
        minCoreVersion: String,
        platforms: [PluginPlatform],
        permissions: [PluginPermission],
        domains: [String]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.category = category
        self.description = description
        self.icon = icon
        self.accentColor = accentColor
        self.minCoreVersion = minCoreVersion
        self.platforms = platforms
        self.permissions = permissions
        self.domains = domains
    }
}

public enum AuthKind: String, Codable, Sendable {
    case none
    case apiKey = "api-key"
    case bearerToken = "bearer-token"
    case basicAuth = "basic-auth"
    case oauth2
    case jwtAPIKey = "jwt-api-key"
    case privateKeyJWT = "private-key-jwt"
}

public struct PluginRequestDefinition: Equatable, Sendable {
    public var id: String
    public var method: String
    public var url: URL

    public init(id: String, method: String, url: URL) {
        self.id = id
        self.method = method
        self.url = url
    }
}

public struct PluginActionDeclaration: Equatable, Sendable {
    public var type: String
    public var label: String
    public var requiresWritePermission: Bool

    public init(type: String, label: String, requiresWritePermission: Bool) {
        self.type = type
        self.label = label
        self.requiresWritePermission = requiresWritePermission
    }
}

public struct PluginValidationInput: Equatable, Sendable {
    public var manifest: PluginManifest
    public var authKinds: [AuthKind]
    public var authDefinitions: [PackagedPluginAuth]
    public var requests: [PluginRequestDefinition]
    public var actions: [PluginActionDeclaration]

    public init(
        manifest: PluginManifest,
        authKinds: [AuthKind] = [],
        authDefinitions: [PackagedPluginAuth] = [],
        requests: [PluginRequestDefinition] = [],
        actions: [PluginActionDeclaration] = []
    ) {
        self.manifest = manifest
        self.authKinds = authKinds
        self.authDefinitions = authDefinitions
        self.requests = requests
        self.actions = actions
    }
}

public enum PluginManifestValidator {
    public static func validate(_ input: PluginValidationInput) throws {
        let manifest = input.manifest

        try requireReverseDNS(manifest.id)
        try requireSemver(manifest.version)
        try requireSemver(manifest.minCoreVersion)
        try requireNonEmpty(manifest.name, field: "name")
        try requireNonEmpty(manifest.author.name, field: "author.name")
        try requireNonEmpty(manifest.category, field: "category")
        try requireNonEmpty(manifest.description, field: "description")
        guard let icon = manifest.icon else {
            throw PluginValidationError.emptyField("icon")
        }
        try validateIcon(icon)
        guard let accentColor = manifest.accentColor else {
            throw PluginValidationError.emptyField("accentColor")
        }
        try validateAccentColor(accentColor)

        guard manifest.platforms.isEmpty == false else {
            throw PluginValidationError.noPlatform
        }

        if manifest.permissions.contains(.network),
           manifest.permissions.contains(.userConfiguredDomains) == false,
           manifest.domains.isEmpty {
            throw PluginValidationError.noDomainForNetworkPermission
        }

        for domain in manifest.domains {
            try validateDomain(domain)
        }

        let declaredDomains = Set(manifest.domains.map { $0.lowercased() })
        for request in input.requests {
            let host = request.url.host?.lowercased() ?? ""
            if manifest.permissions.contains(.userConfiguredDomains) {
                continue
            }
            try validateDeclaredDomain(host, declaredDomains: declaredDomains)
        }

        let authDefinitions = input.authDefinitions.isEmpty
            ? input.authKinds.map { PackagedPluginAuth(type: $0) }
            : input.authDefinitions
        for auth in authDefinitions where auth.type == .oauth2 {
            guard manifest.permissions.contains(.oauth) else {
                throw PluginValidationError.oauthWithoutPermission(manifest.id)
            }
            guard manifest.permissions.contains(.keychain) else {
                throw PluginValidationError.oauthWithoutKeychain(manifest.id)
            }
            guard auth.provider?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw PluginValidationError.oauthMissingProvider(manifest.id)
            }
            guard auth.applicationId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw PluginValidationError.oauthMissingApplicationID(manifest.id)
            }
            guard let oauth = auth.oauth2 else {
                throw PluginValidationError.oauthMissingConfiguration(manifest.id)
            }
            try validateDeclaredDomain(oauth.authorizationURL.host?.lowercased() ?? "", declaredDomains: declaredDomains)
            try validateDeclaredDomain(oauth.tokenURL.host?.lowercased() ?? "", declaredDomains: declaredDomains)
        }

        let hasWritePermission = manifest.permissions.contains(.writeActions)
        for action in input.actions where action.requiresWritePermission && hasWritePermission == false {
            throw PluginValidationError.writeActionWithoutPermission(action.type)
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PluginValidationError.emptyField(field)
        }
    }

    private static func requireReverseDNS(_ value: String) throws {
        let parts = value.split(separator: ".")
        let isValid = parts.count >= 3 && parts.allSatisfy { part in
            part.range(of: #"^[a-z][a-z0-9-]*$"#, options: .regularExpression) != nil
        }

        if isValid == false {
            throw PluginValidationError.invalidIdentifier(value)
        }
    }

    private static func requireSemver(_ value: String) throws {
        let isValid = value.range(of: #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
        if isValid == false {
            throw PluginValidationError.invalidVersion(value)
        }
    }

    private static func validateDomain(_ domain: String) throws {
        if domain.contains("://") {
            throw PluginValidationError.domainContainsScheme(domain)
        }
        if domain.contains("/") {
            throw PluginValidationError.domainContainsPath(domain)
        }
        if domain.contains("*") {
            throw PluginValidationError.domainContainsWildcard(domain)
        }
        try requireNonEmpty(domain, field: "domains")
    }

    private static func validateIcon(_ icon: String) throws {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw PluginValidationError.emptyField("icon")
        }
        let symbol = trimmed.hasPrefix("sf:") ? String(trimmed.dropFirst(3)) : trimmed
        let isValid = symbol.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
        if isValid == false {
            throw PluginValidationError.invalidIcon(icon)
        }
    }

    private static func validateDeclaredDomain(_ host: String, declaredDomains: Set<String>) throws {
        guard declaredDomains.contains(host) else {
            throw PluginValidationError.undeclaredRequestDomain(host)
        }
    }

    private static func validateAccentColor(_ accentColor: String) throws {
        let isValid = accentColor.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
        if isValid == false {
            throw PluginValidationError.invalidAccentColor(accentColor)
        }
    }
}
