import Foundation

public enum WebsitePluginSetupError: Error, Equatable, LocalizedError, Sendable {
    case missingHost
    case invalidHost

    public var errorDescription: String? {
        switch self {
        case .missingHost:
            "Save a website host before running this plugin."
        case .invalidHost:
            "Enter a host name without scheme, path, port, or spaces."
        }
    }
}

public enum WebsitePluginSetup: Sendable {
    public static let pluginID = "com.status.website"
    public static let requestID = "check_site"

    public static func configuredHost(pluginID: String = Self.pluginID, store: StatusPersistenceStore) throws -> String? {
        try store.accountConfigurations(pluginID: pluginID).first?.variables["host"]
    }

    public static func configuredAccount(pluginID: String = Self.pluginID, store: StatusPersistenceStore) throws -> PluginAccountConfiguration {
        guard let configuration = try store.accountConfigurations(pluginID: pluginID).first,
              configuration.variables["host"]?.isEmpty == false else {
            throw WebsitePluginSetupError.missingHost
        }
        return configuration
    }

    @discardableResult
    public static func saveHost(
        _ value: String,
        pluginID: String = Self.pluginID,
        service: PluginRuntimeService
    ) throws -> String {
        let host = try normalizedHost(value)
        try service.saveAccountConfiguration(
            PluginAccountConfiguration(
                id: accountID(host: host),
                pluginID: pluginID,
                accountName: host,
                variables: ["host": host]
            )
        )
        return "Saved \(host)."
    }

    public static func normalizedHost(_ value: String) throws -> String {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("https://") || host.hasPrefix("http://") {
            host = URL(string: host)?.host ?? host
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard host.contains("."),
              host.contains(" ") == false,
              host.contains("/") == false,
              host.contains(":") == false else {
            throw WebsitePluginSetupError.invalidHost
        }
        return host
    }

    public static func accountID(host: String) -> String {
        let sanitizedHost = host.replacingOccurrences(
            of: #"[^a-zA-Z0-9]+"#,
            with: "_",
            options: .regularExpression
        )
        return "acct_website_\(sanitizedHost)"
    }
}
