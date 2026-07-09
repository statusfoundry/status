import Foundation
import Testing
import StatusCore
@testable import StatusUI

@Test func integrationVisualAcceptsDottedSFSymbolNamesWithoutPrefix() {
    let visual = IntegrationVisual.visual(for: "com.status.example", icon: "app.badge", accentColor: "#2F80ED")

    #expect(visual.systemImage == "app.badge")
}

@Test func integrationVisualUsesNativeBrandMarksForOfficialProviders() {
    let github = IntegrationVisual.visual(for: "com.status.github", icon: "sf:chevron.left.forwardslash.chevron.right")
    let appStoreConnect = IntegrationVisual.visual(for: "com.status.appstoreconnect", icon: "sf:app.badge")

    #expect(github.brand == .github)
    #expect(appStoreConnect.brand == .appStoreConnect)
}

@MainActor
@Test func pluginStoreViewModelLoadsRuntimeStatusesForInstalledPlugins() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "GitHub repository checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.github",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let runtimeStatus = PluginRuntimeStatus(
        pluginID: plugin.id,
        status: .failed,
        detail: "Missing network permission.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_530)
    )
    var loadedStatusPluginIDs: [[String]] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRuntimeStatuses: { plugins in
            loadedStatusPluginIDs.append(plugins.map(\.id))
            return [plugin.id: runtimeStatus]
        },
        installPlugin: { _ in }
    )

    await viewModel.reload()

    #expect(loadedStatusPluginIDs == [[plugin.id]])
    #expect(viewModel.runtimeStatuses == [plugin.id: runtimeStatus])
}

@MainActor
@Test func pluginStoreViewModelTestsConfiguredPluginRequest() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "GitHub repository checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.github",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let account = PluginAccountConfiguration(
        id: "acct_github",
        pluginID: plugin.id,
        accountName: "Status repo",
        variables: ["owner": "statusfoundry", "repo": "status"]
    )
    var testedPluginID: String?
    var testedAccountID: String?
    var testedRequestID: String?
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadAccounts: { _ in [account] },
        testPluginRequest: { plugin, account, requestID in
            testedPluginID = plugin.id
            testedAccountID = account.id
            testedRequestID = requestID
            return "GET https://api.github.com/repos/statusfoundry/status/actions/runs\nHTTP 200\n2 bytes"
        }
    )

    await viewModel.reload()
    await viewModel.testRequest("list_workflow_runs", for: plugin)

    let key = viewModel.testRequestKey(pluginID: plugin.id, accountID: account.id, requestID: "list_workflow_runs")
    #expect(testedPluginID == plugin.id)
    #expect(testedAccountID == account.id)
    #expect(testedRequestID == "list_workflow_runs")
    #expect(viewModel.testRequestResults[key] == "GET https://api.github.com/repos/statusfoundry/status/actions/runs\nHTTP 200\n2 bytes")
    #expect(viewModel.testRequestErrors[key] == nil)
}

@MainActor
@Test func pluginStoreViewModelRemovesSelectedConfiguredApp() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "GitHub repository checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.github",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let work = PluginAccountConfiguration(
        id: "acc_work",
        pluginID: plugin.id,
        accountName: "Work GitHub",
        variables: ["owner": "statusfoundry"]
    )
    let personal = PluginAccountConfiguration(
        id: "acc_personal",
        pluginID: plugin.id,
        accountName: "Personal GitHub",
        variables: ["owner": "sil"]
    )
    var accounts = [work, personal]
    var deletedAccountID: String?
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in accounts },
        deleteConfiguration: { _, account in
            deletedAccountID = account.id
            accounts.removeAll { $0.id == account.id }
            return "Removed \(account.accountName)."
        }
    )

    await viewModel.reload()
    viewModel.selectAccount(work.id, for: plugin)
    await viewModel.removeSelectedAccount(for: plugin)

    #expect(deletedAccountID == work.id)
    #expect(viewModel.configuredAccounts[plugin.id]?.map(\.id) == [personal.id])
    #expect(viewModel.selectedAccountIDs[plugin.id] == personal.id)
    #expect(viewModel.setupResults["\(plugin.id):\(personal.id)"] == "Removed Work GitHub.")
}

@MainActor
@Test func pluginStoreViewModelLoadsResourcesForInstalledPlugins() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.website",
        name: "Website",
        author: "Status Foundry",
        description: "Website checks.",
        category: "operations",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.website",
        views: [
            PackagedPluginView(
                id: "websites",
                type: .resourceList,
                resourceType: "website",
                fields: ["statusCode"]
            )
        ],
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let resource = Resource(
        id: "res_com_status_website_example",
        accountID: "acc_website",
        pluginID: plugin.id,
        type: "website",
        name: "example.com",
        fields: ["statusCode": "200"]
    )
    var loadedResourcePluginIDs: [String] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRuntimeStatuses: { _ in [:] },
        loadPluginResources: { plugin in
            loadedResourcePluginIDs.append(plugin.id)
            return [resource]
        },
        installPlugin: { _ in }
    )

    await viewModel.reload()

    #expect(loadedResourcePluginIDs == [plugin.id])
    #expect(viewModel.pluginResources == [plugin.id: [resource]])
}

@MainActor
@Test func pluginStoreViewModelLoadsSuggestedAndAppScopedRules() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "GitHub repository checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.github",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let preset = Rule(
        id: "rule_com_status_github_failed_workflow",
        name: "Failed workflow",
        enabled: false,
        provider: plugin.id,
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "notify")]
    )
    let appRule = Rule(
        id: "rule_app_com_status_github_acc_work_rule_com_status_github_failed_workflow",
        name: "Failed workflow",
        enabled: true,
        scope: .app,
        accountID: "acc_work",
        provider: plugin.id,
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "notify")]
    )
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRules: { _ in [preset, appRule] },
        installPlugin: { _ in }
    )

    await viewModel.reload()

    #expect(viewModel.rulePresets[plugin.id] == [preset])
    #expect(viewModel.appRules[plugin.id] == [appRule])
}

@MainActor
@Test func pluginStoreViewModelEnablesPresetForSelectedApp() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "GitHub repository checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.github",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let account = PluginAccountConfiguration(
        id: "acc_work",
        pluginID: plugin.id,
        accountName: "Work",
        variables: [:]
    )
    let preset = Rule(
        id: "rule_com_status_github_failed_workflow",
        name: "Failed workflow",
        enabled: false,
        provider: plugin.id,
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "notify")]
    )
    var savedRules: [Rule] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRules: { _ in [preset] + savedRules },
        saveRule: { rule in
            savedRules.append(rule)
        },
        installPlugin: { _ in },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [account] }
    )

    await viewModel.reload()
    await viewModel.setRulePreset(preset, enabled: true, for: plugin)

    let savedRule = try #require(savedRules.first)
    #expect(savedRule.id == "rule_app_com_status_github_acc_work_rule_com_status_github_failed_workflow")
    #expect(savedRule.enabled == true)
    #expect(savedRule.scope == .app)
    #expect(savedRule.accountID == account.id)
    #expect(savedRule.provider == plugin.id)
}

@MainActor
@Test func pluginStoreViewModelManagesCustomAppNotificationRules() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.github",
        name: "GitHub",
        author: "Status Foundry",
        description: "GitHub repository checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.github",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let account = PluginAccountConfiguration(
        id: "acc_work",
        pluginID: plugin.id,
        accountName: "Work",
        variables: [:]
    )
    var storedRules: [Rule] = []
    var deletedRuleID: String?
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRules: { _ in storedRules },
        saveRule: { rule in
            storedRules.removeAll { $0.id == rule.id }
            storedRules.append(rule)
        },
        deleteRule: { rule in
            deletedRuleID = rule.id
            storedRules.removeAll { $0.id == rule.id }
        },
        installPlugin: { _ in },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [account] }
    )

    await viewModel.reload()
    await viewModel.saveAppNotificationRule(
        for: plugin,
        name: "Workflow warnings",
        eventType: "github.workflow.failed",
        minimumSeverity: .warning,
        notificationTitle: "Workflow needs attention"
    )

    let created = try #require(storedRules.first)
    #expect(created.id == "rule_custom_com_status_github_acc_work_workflow_warnings")
    #expect(created.enabled == true)
    #expect(created.scope == .app)
    #expect(created.accountID == account.id)
    #expect(created.provider == plugin.id)
    #expect(created.eventType == "github.workflow.failed")
    #expect(created.conditions == [
        RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("warning"))
    ])
    #expect(created.actions == [
        RuleActionDefinition(action: "status.inbox.add"),
        RuleActionDefinition(action: "notification.show", parameters: ["title": "Workflow needs attention"])
    ])
    #expect(viewModel.appRules[plugin.id] == [created])

    await viewModel.setAppRule(created, enabled: false, for: plugin)
    let disabled = try #require(storedRules.first)
    #expect(disabled.enabled == false)

    await viewModel.deleteAppRule(disabled, for: plugin)
    #expect(deletedRuleID == created.id)
    #expect(storedRules.isEmpty)
    #expect(viewModel.appRules[plugin.id]?.isEmpty == true)
}

@MainActor
@Test func pluginStoreViewModelBuildsOAuthConnectionURL() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.oauthgithub",
        name: "OAuth GitHub",
        author: "Status Foundry",
        description: "OAuth GitHub checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.oauthgithub",
        auth: PackagedPluginAuth(
            type: .oauth2,
            provider: "github",
            applicationId: "status-foundry.github",
            oauth2: PackagedPluginOAuth2(
                authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
                tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
                redirectURI: "status://oauth/github",
                scopes: ["repo"]
            )
        ),
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadPermissions: { _ in grantedOAuthPermissions(pluginID: plugin.id) },
        canConfigurePlugin: { _ in true }
    )

    await viewModel.reload()
    let launchedURL = viewModel.beginOAuthConnection(plugin)

    let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
    let url = try #require(viewModel.oauthConnectionURLs["\(plugin.id):\(selectedAccountID ?? "__new__:")"])
    #expect(launchedURL == url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(url.host == "github.com")
    #expect(query["response_type"] == "code")
    #expect(query["client_id"] == "status-foundry.github")
    #expect(query["redirect_uri"] == "status://oauth/github")
    #expect(query["scope"] == "repo")
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["code_challenge"]?.isEmpty == false)
    #expect(viewModel.oauthConnectionErrors["\(plugin.id):\(selectedAccountID ?? "__new__:")"] == nil)
}

@MainActor
@Test func pluginStoreViewModelRequiresOAuthPermissionGrantsBeforeConnecting() async throws {
    let plugin = oauthGitHubPlugin()
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadPermissions: { _ in [
            InstalledPluginPermission(id: "plp_oauth", pluginID: plugin.id, permission: .oauth, granted: true),
            InstalledPluginPermission(id: "plp_keychain", pluginID: plugin.id, permission: .keychain, granted: false),
            InstalledPluginPermission(id: "plp_network", pluginID: plugin.id, permission: .network, granted: true)
        ] },
        canConfigurePlugin: { _ in true }
    )

    await viewModel.reload()
    let launchedURL = viewModel.beginOAuthConnection(plugin)

    let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
    let key = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
    #expect(launchedURL == nil)
    #expect(viewModel.oauthConnectionURLs[key] == nil)
    #expect(viewModel.oauthConnectionErrors[key] == "Grant Keychain permission before connecting this app.")
}

@MainActor
@Test func pluginStoreViewModelCompletesOAuthCallbackForPendingConnection() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.oauthgithub",
        name: "OAuth GitHub",
        author: "Status Foundry",
        description: "OAuth GitHub checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.oauthgithub",
        auth: PackagedPluginAuth(
            type: .oauth2,
            provider: "github",
            applicationId: "status-foundry.github",
            oauth2: PackagedPluginOAuth2(
                authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
                tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
                redirectURI: "status://oauth/github",
                scopes: ["repo"]
            )
        ),
        setup: PackagedPluginSetup(title: "Repository", fields: [
            PackagedPluginSetupField(id: "owner", label: "Owner", type: .text, required: true),
            PackagedPluginSetupField(id: "repo", label: "Repository", type: .text, required: true)
        ]),
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    var completed: [(pluginID: String, accountID: String?, displayName: String?, values: [String: String], callbackURL: URL)] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadPermissions: { _ in grantedOAuthPermissions(pluginID: plugin.id) },
        canConfigurePlugin: { _ in true },
        completeOAuthConnection: { plugin, accountID, displayName, values, _, callbackURL in
            completed.append((plugin.id, accountID, displayName, values, callbackURL))
            return "Saved OAuth app."
        }
    )

    await viewModel.reload()
    viewModel.updateSetupValue(plugin, fieldID: "owner", value: "statusfoundry")
    viewModel.updateSetupValue(plugin, fieldID: "repo", value: "status")
    viewModel.updateAccountDisplayName(plugin, value: "Status Repo")
    viewModel.beginOAuthConnection(plugin)

    let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
    let key = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
    let authorizationURL = try #require(viewModel.oauthConnectionURLs[key])
    let state = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "state" }?
        .value)
    let callbackURL = try #require(URL(string: "status://oauth/github?code=code-456&state=\(state)"))

    await viewModel.completeOAuthConnection(callbackURL: callbackURL)

    let completion = try #require(completed.first)
    #expect(completion.pluginID == plugin.id)
    #expect(completion.accountID == nil)
    #expect(completion.displayName == "Status Repo")
    #expect(completion.values == ["owner": "statusfoundry", "repo": "status"])
    #expect(completion.callbackURL == callbackURL)
    #expect(viewModel.setupResults[key] == "Saved OAuth app.")
    #expect(viewModel.oauthConnectionURLs[key] == nil)
    #expect(viewModel.oauthConnectionErrors[key] == nil)
}

@MainActor
@Test func pluginStoreViewModelIgnoresBroadcastOAuthCallbackWithoutPendingConnection() async throws {
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [] },
        loadAvailable: { [] },
        installPlugin: { _ in }
    )
    let callbackURL = try #require(URL(string: "status://oauth/github?code=code-456&state=missing"))

    let handled = await viewModel.handleOAuthCallbackIfPending(callbackURL: callbackURL)

    #expect(handled == false)
    #expect(viewModel.oauthConnectionErrors["oauth:callback"] == nil)
}

@MainActor
@Test func pluginStoreViewModelHandlesBroadcastOAuthCallbackForPendingConnection() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.oauthgithub",
        name: "OAuth GitHub",
        author: "Status Foundry",
        description: "OAuth GitHub checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.oauthgithub",
        auth: PackagedPluginAuth(
            type: .oauth2,
            provider: "github",
            applicationId: "status-foundry.github",
            oauth2: PackagedPluginOAuth2(
                authorizationURL: try #require(URL(string: "https://github.com/login/oauth/authorize")),
                tokenURL: try #require(URL(string: "https://github.com/login/oauth/access_token")),
                redirectURI: "status://oauth/github",
                scopes: ["repo"]
            )
        ),
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    var completedCallbackURL: URL?
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadPermissions: { _ in grantedOAuthPermissions(pluginID: plugin.id) },
        canConfigurePlugin: { _ in true },
        completeOAuthConnection: { _, _, _, _, _, callbackURL in
            completedCallbackURL = callbackURL
            return "Saved OAuth app."
        }
    )

    await viewModel.reload()
    viewModel.beginOAuthConnection(plugin)

    let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
    let key = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
    let authorizationURL = try #require(viewModel.oauthConnectionURLs[key])
    let state = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "state" }?
        .value)
    let callbackURL = try #require(URL(string: "status://oauth/github?code=code-456&state=\(state)"))

    let handled = await viewModel.handleOAuthCallbackIfPending(callbackURL: callbackURL)

    #expect(handled == true)
    #expect(completedCallbackURL == callbackURL)
    #expect(viewModel.setupResults[key] == "Saved OAuth app.")
    #expect(viewModel.oauthConnectionURLs[key] == nil)
}

private func oauthGitHubPlugin() -> InstalledPlugin {
    InstalledPlugin(
        id: "com.status.oauthgithub",
        name: "OAuth GitHub",
        author: "Status Foundry",
        description: "OAuth GitHub checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.oauthgithub",
        auth: PackagedPluginAuth(
            type: .oauth2,
            provider: "github",
            applicationId: "status-foundry.github",
            oauth2: PackagedPluginOAuth2(
                authorizationURL: URL(string: "https://github.com/login/oauth/authorize")!,
                tokenURL: URL(string: "https://github.com/login/oauth/access_token")!,
                redirectURI: "status://oauth/github",
                scopes: ["repo"]
            )
        ),
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
}

private func grantedOAuthPermissions(pluginID: String) -> [InstalledPluginPermission] {
    [
        InstalledPluginPermission(id: "plp_\(pluginID)_oauth", pluginID: pluginID, permission: .oauth, granted: true),
        InstalledPluginPermission(id: "plp_\(pluginID)_keychain", pluginID: pluginID, permission: .keychain, granted: true),
        InstalledPluginPermission(id: "plp_\(pluginID)_network", pluginID: pluginID, permission: .network, granted: true)
    ]
}
