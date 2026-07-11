import Foundation
import Testing
@testable import StatusCore

@Test func validPluginManifestPassesValidation() throws {
    let manifest = appStoreConnectManifest()
    let request = PluginRequestDefinition(
        id: "list_apps",
        method: "GET",
        url: try #require(URL(string: "https://api.appstoreconnect.apple.com/v1/apps"))
    )

    try PluginManifestValidator.validate(
        PluginValidationInput(manifest: manifest, authKinds: [.jwtAPIKey], requests: [request])
    )
}

@Test func pluginManifestDecodesLegacyStringAuthor() throws {
    let data = Data("""
    {
      "id": "com.status.website",
      "name": "Website Uptime",
      "version": "0.1.0",
      "author": "Status Foundry",
      "category": "monitoring",
      "description": "Checks configured websites.",
      "minCoreVersion": "0.1.0",
      "platforms": ["macOS", "iOS"],
      "permissions": ["network", "user-configured-domains"],
      "domains": []
    }
    """.utf8)

    let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

    #expect(manifest.author == PluginAuthor(name: "Status Foundry"))
    #expect(manifest.icon == nil)
    #expect(manifest.accentColor == nil)
}

@Test func networkPluginMustDeclareRequestedDomains() throws {
    var manifest = appStoreConnectManifest()
    manifest.domains = []

    #expect(throws: PluginValidationError.noDomainForNetworkPermission) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest))
    }
}

@Test func requestDomainMustBeDeclaredByPlugin() throws {
    let manifest = appStoreConnectManifest()
    let request = PluginRequestDefinition(
        id: "bad_request",
        method: "GET",
        url: try #require(URL(string: "https://example.com/v1/apps"))
    )

    #expect(throws: PluginValidationError.undeclaredRequestDomain("example.com")) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest, requests: [request]))
    }
}

@Test func userConfiguredDomainPluginsMayUseTemplatedHosts() throws {
    let manifest = PluginManifest(
        id: "com.status.website",
        name: "Website Uptime",
        version: "1.0.0",
        author: PluginAuthor(name: "Status"),
        category: "Monitoring",
        description: "Checks websites chosen by the user.",
        icon: "sf:globe",
        accentColor: "#16A34A",
        minCoreVersion: "1.0.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .userConfiguredDomains, .backgroundRefresh],
        domains: []
    )
    let request = PluginRequestDefinition(
        id: "check_site",
        method: "GET",
        url: try #require(URL(string: "https://example.com"))
    )

    try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest, requests: [request]))
}

@Test func writeActionsRequireExplicitPermission() {
    let manifest = appStoreConnectManifest()
    let action = PluginActionDeclaration(
        type: "jira.createIssue",
        label: "Create Jira issue",
        requiresWritePermission: true
    )

    #expect(throws: PluginValidationError.writeActionWithoutPermission("jira.createIssue")) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest, actions: [action]))
    }
}

@Test func oauthRequiresExplicitPermissionAndConfiguration() throws {
    let manifest = appStoreConnectManifest()

    #expect(throws: PluginValidationError.oauthWithoutPermission(manifest.id)) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest, authKinds: [.oauth2]))
    }

    var oauthManifest = manifest
    oauthManifest.permissions.append(.oauth)
    oauthManifest.domains = ["api.appstoreconnect.apple.com", "github.com"]
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/github",
            scopes: ["repo"]
        )
    )

    try PluginManifestValidator.validate(
        PluginValidationInput(manifest: oauthManifest, authDefinitions: [auth])
    )
}

@Test func oauthRequiresNetworkPermissionForTokenExchange() throws {
    var manifest = appStoreConnectManifest()
    manifest.permissions = [.keychain, .oauth]
    manifest.domains = ["api.appstoreconnect.apple.com", "github.com"]
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/github"
        )
    )

    #expect(throws: PluginValidationError.oauthWithoutNetwork(manifest.id)) {
        try PluginManifestValidator.validate(
            PluginValidationInput(manifest: manifest, authDefinitions: [auth])
        )
    }
}

@Test func oauthEndpointDomainsMustBeDeclaredByPlugin() throws {
    var manifest = appStoreConnectManifest()
    manifest.permissions.append(.oauth)
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/github"
        )
    )

    #expect(throws: PluginValidationError.undeclaredRequestDomain("github.com")) {
        try PluginManifestValidator.validate(
            PluginValidationInput(manifest: manifest, authDefinitions: [auth])
        )
    }
}

@Test func oauthRedirectURIMustUseAppOwnedCallback() throws {
    var manifest = appStoreConnectManifest()
    manifest.permissions.append(.oauth)
    manifest.domains = ["api.appstoreconnect.apple.com", "github.com"]
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "https://example.com/oauth/callback"
        )
    )

    #expect(throws: PluginValidationError.oauthInvalidRedirectURI("https://example.com/oauth/callback")) {
        try PluginManifestValidator.validate(
            PluginValidationInput(manifest: manifest, authDefinitions: [auth])
        )
    }
}

@Test func oauthRedirectURIMustMatchProviderSlug() throws {
    var manifest = appStoreConnectManifest()
    manifest.permissions.append(.oauth)
    manifest.domains = ["api.appstoreconnect.apple.com", "github.com"]
    let auth = PackagedPluginAuth(
        type: .oauth2,
        provider: "github",
        applicationId: "status-foundry.github",
        oauth2: PackagedPluginOAuth2(
            authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
            tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
            redirectURI: "status://oauth/google"
        )
    )

    #expect(throws: PluginValidationError.oauthInvalidRedirectURI("status://oauth/google")) {
        try PluginManifestValidator.validate(
            PluginValidationInput(manifest: manifest, authDefinitions: [auth])
        )
    }
}

@Test func pluginManifestRequiresIconAndAccentColor() {
    var manifest = appStoreConnectManifest()
    manifest.icon = nil

    #expect(throws: PluginValidationError.emptyField("icon")) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest))
    }

    manifest = appStoreConnectManifest()
    manifest.accentColor = nil

    #expect(throws: PluginValidationError.emptyField("accentColor")) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest))
    }
}

@Test func pluginIconMustBeSFSymbolName() {
    var manifest = appStoreConnectManifest()
    manifest.icon = "icons/github.svg"

    #expect(throws: PluginValidationError.invalidIcon("icons/github.svg")) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest))
    }
}

@Test func accentColorMustBeHexColor() {
    var manifest = appStoreConnectManifest()
    manifest.accentColor = "blue"

    #expect(throws: PluginValidationError.invalidAccentColor("blue")) {
        try PluginManifestValidator.validate(PluginValidationInput(manifest: manifest))
    }
}

private func appStoreConnectManifest() -> PluginManifest {
    PluginManifest(
        id: "com.status.appstoreconnect",
        name: "App Store Connect",
        version: "1.0.0",
        author: PluginAuthor(name: "Status"),
        category: "Developer",
        description: "Shows app review states, versions, builds, ratings, and direct App Store Connect links.",
        icon: "sf:app.badge",
        accentColor: "#2F80ED",
        minCoreVersion: "1.0.0",
        platforms: [.macOS, .iOS],
        permissions: [.network, .keychain, .privateKey, .backgroundRefresh],
        domains: ["api.appstoreconnect.apple.com"]
    )
}
