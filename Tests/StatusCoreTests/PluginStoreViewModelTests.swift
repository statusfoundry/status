import Foundation
import Testing
@testable import StatusCore
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

@Test func pluginSetupChecklistTracksGitHubTokenSetup() {
    let plugin = setupChecklistPlugin(
        id: "com.status.github",
        name: "GitHub",
        auth: PackagedPluginAuth(
            type: .bearerToken,
            provider: "github",
            fields: [
                PackagedPluginSetupField(id: "token", label: "Personal access token", type: .secret, required: true)
            ]
        ),
        setup: PackagedPluginSetup(
            title: "Repository",
            fields: [
                PackagedPluginSetupField(id: "owner", label: "Owner", type: .text, required: true),
                PackagedPluginSetupField(id: "repo", label: "Repository", type: .text, required: true)
            ]
        )
    )

    let incomplete = PluginAppSetupChecklist(
        plugin: plugin,
        selectedAccount: nil,
        setupFields: setupChecklistFields(plugin),
        setupValues: ["owner": "statusfoundry", "repo": ""],
        permissions: setupChecklistPermissions([.network, .keychain, .backgroundRefresh], granted: []),
        runtimeRequiredPermissions: [.network, .keychain]
    )

    #expect(incomplete.items.map { $0.id } == ["save", "auth", "permissions", "refresh"])
    #expect(incomplete.items.map { $0.isComplete } == [false, false, false, false])
    #expect(incomplete.items[0].detail == "Complete Personal access token, Repository before saving.")

    let complete = PluginAppSetupChecklist(
        plugin: plugin,
        selectedAccount: PluginAccountConfiguration(
            id: "acc_github",
            pluginID: plugin.id,
            accountName: "Status repo",
            variables: ["owner": "statusfoundry", "repo": "status"],
            authType: AuthKind.bearerToken.rawValue,
            credentialRef: "keychain://github"
        ),
        setupFields: setupChecklistFields(plugin),
        setupValues: ["owner": "statusfoundry", "repo": "status"],
        permissions: setupChecklistPermissions([.network, .keychain, .backgroundRefresh], granted: [.network, .keychain]),
        runtimeRequiredPermissions: [.network, .keychain]
    )

    #expect(complete.items.map { $0.isComplete } == [true, true, true, true])
}

@Test func pluginSetupRequirementStateAcceptsStoredSecretsForSavedApps() {
    let fields = [
        PackagedPluginSetupField(id: "token", label: "Personal access token", type: .secret, required: true),
        PackagedPluginSetupField(id: "owner", label: "Owner", type: .text, required: true)
    ]

    let newAppMissing = PluginSetupRequirementState.missingRequiredFields(
        setupFields: fields,
        setupValues: ["owner": "statusfoundry"],
        selectedAccount: nil
    )
    let savedAppMissing = PluginSetupRequirementState.missingRequiredFields(
        setupFields: fields,
        setupValues: ["owner": "statusfoundry"],
        selectedAccount: PluginAccountConfiguration(
            id: "acc_github",
            pluginID: "com.status.github",
            accountName: "Status repo",
            variables: ["owner": "statusfoundry"],
            authType: AuthKind.bearerToken.rawValue,
            credentialRef: "keychain://github"
        )
    )

    #expect(newAppMissing.map { $0.id } == ["token"])
    #expect(savedAppMissing.isEmpty)
}

@Test func pluginSetupChecklistTracksYouTubeOAuthSetup() {
    let plugin = setupChecklistPlugin(
        id: "com.status.youtube",
        name: "YouTube",
        auth: PackagedPluginAuth(type: .oauth2, provider: "youtube"),
        setup: PackagedPluginSetup(
            title: "YouTube creator account",
            fields: [
                PackagedPluginSetupField(id: PluginOAuth.clientIDSetupFieldKey, label: "Google OAuth client ID", type: .text, required: true)
            ]
        )
    )

    let checklist = PluginAppSetupChecklist(
        plugin: plugin,
        selectedAccount: PluginAccountConfiguration(
            id: "acc_youtube",
            pluginID: plugin.id,
            accountName: "Creator account",
            variables: [PluginOAuth.clientIDSetupFieldKey: "client.apps.googleusercontent.com"],
            authType: AuthKind.oauth2.rawValue,
            credentialRef: nil
        ),
        setupFields: setupChecklistFields(plugin),
        setupValues: [PluginOAuth.clientIDSetupFieldKey: "client.apps.googleusercontent.com"],
        permissions: setupChecklistPermissions([.network, .keychain, .oauth], granted: [.network, .keychain, .oauth]),
        runtimeRequiredPermissions: [.network, .keychain, .oauth]
    )

    #expect(checklist.items.map { $0.id } == ["save", "auth", "permissions", "refresh"])
    #expect(checklist.items[1].label == "Connect OAuth account")
    #expect(checklist.items.map { $0.isComplete } == [true, false, true, false])
}

@Test func pluginRuntimePermissionRequirementsIncludeOAuthForConnectedOAuthApps() {
    let required = PluginRuntimePermissionRequirements(
        permissions: setupChecklistPermissions([.network, .keychain, .oauth, .backgroundRefresh], granted: []),
        authType: AuthKind.oauth2.rawValue,
        hasCredential: true
    )

    #expect(required.requiredPermissions == [.network, .keychain, .oauth])
}

@Test func pluginRuntimePermissionRequirementsDoNotRequireOAuthBeforeConnection() {
    let required = PluginRuntimePermissionRequirements(
        permissions: setupChecklistPermissions([.network, .keychain, .oauth, .backgroundRefresh], granted: []),
        authType: AuthKind.oauth2.rawValue,
        hasCredential: false
    )

    #expect(required.requiredPermissions == [.network])
}

@Test func pluginSetupGuideExplainsGitHubAndYouTubeOAuthSetup() throws {
    let github = try #require(PluginSetupGuide(plugin: setupChecklistPlugin(
        id: "com.status.github",
        name: "GitHub",
        auth: PackagedPluginAuth(type: .oauth2, provider: "github"),
        setup: nil
    )))
    let youtube = try #require(PluginSetupGuide(plugin: setupChecklistPlugin(
        id: "com.status.youtube",
        name: "YouTube",
        auth: PackagedPluginAuth(type: .oauth2, provider: "youtube"),
        setup: nil
    )))

    #expect(github.detail.contains("OAuth device flow"))
    #expect(github.detail.contains("without shipping a client secret"))
    #expect(github.steps.contains { $0.contains("Connect account") })
    #expect(github.steps.contains { $0.contains("Complete connection") })
    #expect(github.links.first?.url.absoluteString == "https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps")
    #expect(youtube.detail.contains("Google OAuth 2 with PKCE"))
    #expect(youtube.steps.contains { $0.contains("com.statusfoundry.status.oauth:/youtube") })
}

@Test func dashboardTileDisplayValueFormatsRawPluginValuesForUsers() {
    #expect(
        DashboardTileDisplayValue(
            item: DashboardTileItem(id: "reachable", label: "Reachable", value: "true")
        ).text == "Yes"
    )
    #expect(
        DashboardTileDisplayValue(
            item: DashboardTileItem(id: "responseTimeMs", label: "Response Time", value: "341", kind: .count)
        ).text == "341 ms"
    )
    #expect(
        DashboardTileDisplayValue(
            item: DashboardTileItem(
                id: "actionUrl",
                label: "Open",
                value: "https://status.hakobs.com",
                kind: .link,
                actionURL: URL(string: "https://status.hakobs.com")
            )
        ).text == "status.hakobs.com"
    )
}

@Test func statusFieldValueFormatterFormatsResourceValuesConsistently() {
    #expect(StatusFieldValueFormatter.displayText(fieldID: "reachable", value: "true") == "Yes")
    #expect(StatusFieldValueFormatter.displayText(fieldID: "responseTimeMs", value: "341") == "341 ms")
    #expect(
        StatusFieldValueFormatter.displayText(
            fieldID: "actionUrl",
            value: "https://github.com/statusfoundry/status",
            kind: .link
        ) == "github.com/statusfoundry/status"
    )
    #expect(StatusFieldValueFormatter.tone(fieldID: "reachable", value: "true") == .positive)
    #expect(StatusFieldValueFormatter.tone(fieldID: "reachable", value: "false") == .negative)
    #expect(StatusFieldValueFormatter.tone(fieldID: "status", value: "pending review") == .warning)
    #expect(StatusFieldValueFormatter.tone(fieldID: "lastCommit", value: "Fix dashboard") == nil)
}

@MainActor
@Test func dashboardViewModelRefreshConfiguredAppsReloadsSnapshotAndStoresResult() async {
    var loadCount = 0
    var didRefresh = false
    let refreshedSnapshot = DashboardSnapshot(
        headline: "1 app checked",
        summary: "Status refreshed your configured apps.",
        statusItems: [],
        recentEvents: [],
        metrics: [],
        integrations: [
            IntegrationSummary(
                id: "acct_github",
                name: "Status GitHub",
                provider: "com.status.github",
                state: "Ready",
                severity: .ok,
                lastSyncDescription: "Just now"
            )
        ],
        auditEntries: []
    )
    let viewModel = DashboardViewModel {
        loadCount += 1
        return loadCount == 1 ? .empty : refreshedSnapshot
    } refreshApps: {
        didRefresh = true
        return "Refreshed 1 app. 1 resource stored. 0 events processed."
    }

    viewModel.reload()
    await viewModel.refreshConfiguredApps()

    #expect(didRefresh)
    #expect(viewModel.snapshot == refreshedSnapshot)
    #expect(viewModel.refreshResult == "Refreshed 1 app. 1 resource stored. 0 events processed.")
    #expect(viewModel.refreshError == nil)
    #expect(viewModel.isRefreshingApps == false)
}

@MainActor
@Test func dashboardViewModelRefreshConfiguredAppsReloadsSnapshotAfterFailure() async {
    struct RefreshFailure: Error, LocalizedError {
        var errorDescription: String? { "Network permission is missing." }
    }

    var loadCount = 0
    let viewModel = DashboardViewModel {
        loadCount += 1
        return DashboardSnapshot(
            headline: "Loaded \(loadCount)",
            summary: "Reloaded after refresh attempt.",
            statusItems: [],
            recentEvents: [],
            metrics: [],
            integrations: [],
            auditEntries: []
        )
    } refreshApps: {
        throw RefreshFailure()
    }

    viewModel.reload()
    await viewModel.refreshConfiguredApps()

    #expect(viewModel.snapshot.headline == "Loaded 2")
    #expect(viewModel.refreshResult == nil)
    #expect(viewModel.refreshError == "Network permission is missing.")
    #expect(viewModel.isRefreshingApps == false)
}

@Test func pluginSettingsHeaderPrefersConfiguredAppName() {
    let header = PluginSettingsHeaderText(
        pluginName: "GitHub",
        pluginVersion: "0.1.0",
        appName: "Status Foundry GitHub"
    )

    #expect(header.title == "Status Foundry GitHub")
    #expect(header.metadata == "GitHub 0.1.0")
}

@Test func pluginSettingsHeaderFallsBackToPluginName() {
    let header = PluginSettingsHeaderText(
        pluginName: "GitHub",
        pluginVersion: "0.1.0",
        appName: " "
    )

    #expect(header.title == "GitHub")
    #expect(header.metadata == "0.1.0")
}

@Test func pluginOAuthConnectionReadinessRequiresSetupFieldsBeforeConnecting() {
    let readiness = PluginOAuthConnectionReadiness(
        setupFields: [
            PackagedPluginSetupField(
                id: PluginOAuth.clientIDSetupFieldKey,
                label: "Google OAuth client ID",
                type: .text,
                required: true
            )
        ],
        setupValues: [:],
        permissions: grantedOAuthPermissions(pluginID: "com.status.youtube")
    )

    #expect(readiness.canConnect == false)
    #expect(readiness.detail == "Enter Google OAuth client ID before connecting.")
}

@Test func pluginOAuthConnectionReadinessRequiresOAuthPermissionsBeforeConnecting() {
    let readiness = PluginOAuthConnectionReadiness(
        setupFields: [
            PackagedPluginSetupField(
                id: PluginOAuth.clientIDSetupFieldKey,
                label: "Google OAuth client ID",
                type: .text,
                required: true
            )
        ],
        setupValues: [PluginOAuth.clientIDSetupFieldKey: "client.apps.googleusercontent.com"],
        permissions: [
            InstalledPluginPermission(id: "plp_network", pluginID: "com.status.youtube", permission: .network, granted: true),
            InstalledPluginPermission(id: "plp_keychain", pluginID: "com.status.youtube", permission: .keychain, granted: false),
            InstalledPluginPermission(id: "plp_oauth", pluginID: "com.status.youtube", permission: .oauth, granted: false),
            InstalledPluginPermission(id: "plp_background", pluginID: "com.status.youtube", permission: .backgroundRefresh, granted: false)
        ]
    )

    #expect(readiness.canConnect == false)
    #expect(readiness.missingPermissions == [.keychain, .oauth])
    #expect(readiness.detail == "Grant Keychain, OAuth permission before connecting.")
}

@Test func pluginOAuthConnectionReadinessAllowsReadyOAuthSetup() {
    let readiness = PluginOAuthConnectionReadiness(
        setupFields: [
            PackagedPluginSetupField(
                id: PluginOAuth.clientIDSetupFieldKey,
                label: "Google OAuth client ID",
                type: .text,
                required: true
            )
        ],
        setupValues: [PluginOAuth.clientIDSetupFieldKey: "client.apps.googleusercontent.com"],
        permissions: grantedOAuthPermissions(pluginID: "com.status.youtube")
    )

    #expect(readiness.canConnect)
    #expect(readiness.detail == "Ready to open the provider authorization page.")
}

@Test func pluginAppDetailSummaryFactsDescribeUncheckedEmptyApps() {
    let facts = PluginAppDetailSummaryFacts(runtimeStatus: nil, resources: [])

    #expect(facts.statusValue == "Not checked yet")
    #expect(facts.statusTimestamp == nil)
    #expect(facts.statusIcon == "circle.dashed")
    #expect(facts.resourceCount == 0)
    #expect(facts.resourceTypeDetail == "0 resource types")
    #expect(facts.emittedEventCount == 0)
    #expect(facts.latestResourceName == "Waiting")
    #expect(facts.latestResourceDetail == "No stored resource")
}

@Test func pluginAppDetailSummaryFactsDescribeLatestRefreshAndResources() {
    let timestamp = Date(timeIntervalSince1970: 1_783_433_520)
    let facts = PluginAppDetailSummaryFacts(
        runtimeStatus: PluginRuntimeStatus(
            pluginID: "com.status.website",
            status: .success,
            detail: "Refresh completed.",
            timestamp: timestamp,
            emittedEventCount: 2
        ),
        resources: [
            Resource(
                id: "res_site",
                accountID: "acc_site",
                pluginID: "com.status.website",
                type: "website",
                name: "status.hakobs.com"
            ),
            Resource(
                id: "res_check",
                accountID: "acc_site",
                pluginID: "com.status.website",
                type: "check",
                name: "TLS check"
            )
        ]
    )

    #expect(facts.statusValue == "Last check succeeded")
    #expect(facts.statusTimestamp == timestamp)
    #expect(facts.statusIcon == "checkmark.circle.fill")
    #expect(facts.resourceCount == 2)
    #expect(facts.resourceTypeDetail == "2 resource types")
    #expect(facts.emittedEventCount == 2)
    #expect(facts.latestResourceName == "status.hakobs.com")
    #expect(facts.latestResourceDetail == "Latest stored resource")
}

@Test func pluginCatalogAppSummaryTextDescribesNoConfiguredApps() {
    let summary = PluginCatalogAppSummaryText(accounts: [], selectedAccountID: nil)

    #expect(summary.primary == "No apps configured")
    #expect(summary.secondary == "Set up an app from this plugin.")
}

@Test func pluginCatalogAppSummaryTextDescribesOneConfiguredApp() {
    let summary = PluginCatalogAppSummaryText(
        accounts: [
            PluginAccountConfiguration(
                id: "acct_work",
                pluginID: "com.status.github",
                accountName: "Work GitHub",
                variables: [:],
                authType: "apiKey",
                credentialRef: nil
            )
        ],
        selectedAccountID: "acct_work"
    )

    #expect(summary.primary == "1 app configured")
    #expect(summary.secondary == "Work GitHub")
}

@Test func pluginCatalogAppSummaryTextDescribesSelectedAppForRefresh() {
    let summary = PluginCatalogAppSummaryText(
        accounts: [
            PluginAccountConfiguration(
                id: "acct_work",
                pluginID: "com.status.github",
                accountName: "Work GitHub",
                variables: [:],
                authType: "apiKey",
                credentialRef: nil
            ),
            PluginAccountConfiguration(
                id: "acct_personal",
                pluginID: "com.status.github",
                accountName: "Personal GitHub",
                variables: [:],
                authType: "apiKey",
                credentialRef: nil
            )
        ],
        selectedAccountID: "acct_personal"
    )

    #expect(summary.primary == "2 apps configured")
    #expect(summary.secondary == "Selected for refresh: Personal GitHub")
}

@Test func pluginAppAuditTrailKeepsEntriesForRecentAppJobs() {
    let now = Date(timeIntervalSince1970: 1_783_433_520)
    let recentJobs = [
        JobRecord(
            id: "job_recent",
            pluginID: "com.status.website",
            triggerID: "manual",
            accountID: "acc_status",
            status: .success,
            queuedAt: now
        )
    ]
    let matchingAudit = AuditEntry(
        id: "aud_job_recent_success",
        title: "Job completed",
        detail: "Website refresh completed.",
        timestamp: now,
        status: "success",
        jobID: "job_recent"
    )
    let otherAudit = AuditEntry(
        id: "aud_job_other_success",
        title: "Job completed",
        detail: "Other app refresh completed.",
        timestamp: now,
        status: "success",
        jobID: "job_other"
    )

    let trail = PluginAppAuditTrail(
        auditEntries: [matchingAudit, otherAudit],
        recentJobs: recentJobs
    )

    #expect(trail.entries == [matchingAudit])
}

@Test func pluginStoreCatalogDetectsAvailableUpdates() throws {
    let installed = InstalledPlugin(
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
    let update = registryPluginSummary(id: installed.id, latestVersion: "0.2.0")
    let catalog = PluginStoreCatalog(installed: [installed], available: [update])

    #expect(catalog.availableUpdate(for: installed) == update)
}

@Test func pluginStoreCatalogDoesNotOfferEqualOrOlderRegistryVersions() throws {
    let installed = InstalledPlugin(
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
    let same = PluginStoreCatalog(installed: [installed], available: [
        registryPluginSummary(id: installed.id, latestVersion: "0.1")
    ])
    let older = PluginStoreCatalog(installed: [installed], available: [
        registryPluginSummary(id: installed.id, latestVersion: "0.0.9")
    ])

    #expect(same.availableUpdate(for: installed) == nil)
    #expect(older.availableUpdate(for: installed) == nil)
}

@MainActor
@Test func pluginStoreViewModelLoadsRuntimeStatusesForConfiguredApps() async throws {
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
    let workAccount = PluginAccountConfiguration(
        id: "acct_work",
        pluginID: plugin.id,
        accountName: "Work GitHub",
        variables: [:],
        authType: "apiKey",
        credentialRef: nil
    )
    let personalAccount = PluginAccountConfiguration(
        id: "acct_personal",
        pluginID: plugin.id,
        accountName: "Personal GitHub",
        variables: [:],
        authType: "apiKey",
        credentialRef: nil
    )
    let workStatus = PluginRuntimeStatus(
        pluginID: plugin.id,
        status: .failed,
        detail: "Missing network permission.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_530)
    )
    let personalStatus = PluginRuntimeStatus(
        pluginID: plugin.id,
        status: .success,
        detail: "Synced personal repositories.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_540),
        emittedEventCount: 2
    )
    var loadedStatusPluginIDs: [[String]] = []
    var loadedStatusAccountIDs: [[String]] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRuntimeStatuses: { plugins, accountsByPluginID in
            loadedStatusPluginIDs.append(plugins.map(\.id))
            loadedStatusAccountIDs.append(accountsByPluginID[plugin.id, default: []].map(\.id))
            return [
                "\(plugin.id):\(workAccount.id)": workStatus,
                "\(plugin.id):\(personalAccount.id)": personalStatus
            ]
        },
        installPlugin: { _ in },
        loadAccounts: { _ in [workAccount, personalAccount] }
    )

    await viewModel.reload()

    #expect(loadedStatusPluginIDs == [[plugin.id]])
    #expect(loadedStatusAccountIDs == [[workAccount.id, personalAccount.id]])
    #expect(viewModel.runtimeStatuses == [
        "\(plugin.id):\(workAccount.id)": workStatus,
        "\(plugin.id):\(personalAccount.id)": personalStatus
    ])
}

@MainActor
@Test func pluginStoreViewModelLoadsPluginActionDefinitions() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.jira",
        name: "Jira",
        author: "Status Foundry",
        description: "Jira issue creation.",
        category: "operations",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.jira",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let action = PackagedPluginAction(
        id: "jira.createIssue",
        label: "Create Jira issue",
        description: "Create a reviewed Jira issue.",
        requiresWritePermission: true,
        safety: .reviewRequired,
        inputSchema: PackagedPluginActionInputSchema(fields: [
            PackagedPluginActionInputField(
                key: "summary",
                label: "Summary",
                type: .template,
                required: true,
                defaultValue: "{{event.title}}"
            )
        ]),
        request: "create_issue"
    )
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadActions: { _ in [action] },
        installPlugin: { _ in }
    )

    await viewModel.reload()

    #expect(viewModel.pluginActions[plugin.id] == [action])
}

@MainActor
@Test func pluginStoreViewModelGrantsMultiplePermissionsSequentially() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.youtube",
        name: "YouTube",
        author: "Status Foundry",
        description: "YouTube creator checks.",
        category: "creator",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.youtube",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    var granted: Set<PluginPermission> = []
    var grantOrder: [PluginPermission] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadPermissions: { plugin in
            [
                InstalledPluginPermission(
                    id: "plp_network",
                    pluginID: plugin.id,
                    permission: .network,
                    granted: granted.contains(.network)
                ),
                InstalledPluginPermission(
                    id: "plp_keychain",
                    pluginID: plugin.id,
                    permission: .keychain,
                    granted: granted.contains(.keychain)
                )
            ]
        },
        setPermissionGrant: { _, permission, isGranted in
            grantOrder.append(permission)
            if isGranted {
                granted.insert(permission)
            } else {
                granted.remove(permission)
            }
        }
    )

    await viewModel.reload()
    await viewModel.setPermissions([.network, .keychain, .network], granted: true, for: plugin)

    #expect(grantOrder == [.keychain, .network])
    #expect(Set(viewModel.installedPermissions[plugin.id, default: []].filter(\.granted).map(\.permission)) == [.network, .keychain])
    #expect(viewModel.savingPermissionID == nil)
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
@Test func pluginStoreViewModelReportsAppRequiredBeforeRefresh() async throws {
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
    var didRun = false
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        canRunPlugin: { _ in true },
        runPlugin: { _, _ in
            didRun = true
            return "ran"
        },
        loadAccounts: { _ in [] }
    )

    await viewModel.reload()
    await viewModel.run(plugin)

    #expect(didRun == false)
    #expect(viewModel.runErrors["\(plugin.id):__new__:\(plugin.id)"] == "Save an app before refreshing it.")
}

@MainActor
@Test func pluginStoreViewModelReportsAppRequiredBeforeTestingRequest() async throws {
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
    var didTest = false
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadAccounts: { _ in [] },
        testPluginRequest: { _, _, _ in
            didTest = true
            return "preview"
        }
    )

    await viewModel.reload()
    await viewModel.testRequest("list_workflow_runs", for: plugin)

    #expect(didTest == false)
    #expect(viewModel.testRequestErrors["\(plugin.id):__new__:\(plugin.id)"] == "Save an app before testing requests for it.")
}

@MainActor
@Test func pluginStoreViewModelSelectsSavedAppAfterNewSetup() async throws {
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
    var accounts: [PluginAccountConfiguration] = []
    var savedAccountID: String?
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in accounts },
        saveConfigurationValues: { plugin, accountID, displayName, values in
            #expect(accountID == nil)
            #expect(values.isEmpty)
            let account = PluginAccountConfiguration(
                id: "acc_status_foundry",
                pluginID: plugin.id,
                accountName: displayName ?? plugin.name,
                variables: [:]
            )
            savedAccountID = account.id
            accounts = [account]
            return "Saved \(account.accountName)."
        }
    )

    await viewModel.reload()
    viewModel.updateAccountDisplayName(plugin, value: "Status Foundry GitHub")
    await viewModel.saveSetup(plugin)

    let persistedKey = "\(plugin.id):acc_status_foundry"
    #expect(savedAccountID == "acc_status_foundry")
    #expect(viewModel.selectedAccountIDs[plugin.id] == "acc_status_foundry")
    #expect(viewModel.setupResults[persistedKey] == "Saved Status Foundry GitHub.")
    #expect(viewModel.setupResults["\(plugin.id):__new__:\(plugin.id)"] == nil)
    #expect(viewModel.accountDisplayNames[persistedKey] == "Status Foundry GitHub")
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
@Test func pluginStoreViewModelAddAccountKeepsExistingAppsAndSelectsDraft() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.youtube",
        name: "YouTube",
        author: "Status Foundry",
        description: "YouTube creator checks.",
        category: "creator",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.youtube",
        setup: PackagedPluginSetup(
            title: "Creator channel",
            fields: [
                PackagedPluginSetupField(
                    id: "channelId",
                    label: "Channel ID",
                    type: .text,
                    required: true
                )
            ]
        ),
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let existing = PluginAccountConfiguration(
        id: "acc_creator",
        pluginID: plugin.id,
        accountName: "Creator Channel",
        variables: ["channelId": "UC123"]
    )
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [existing] },
        loadConfigurationValues: { _, accountID in
            accountID == existing.id ? existing.variables : [:]
        }
    )

    await viewModel.reload()
    viewModel.addAccount(for: plugin)

    let draftAccountID = "__new__:\(plugin.id)"
    let draftKey = "\(plugin.id):\(draftAccountID)"
    #expect(viewModel.configuredAccounts[plugin.id]?.map { $0.id } == [existing.id])
    #expect(viewModel.selectedAccountIDs[plugin.id] == draftAccountID)
    #expect(viewModel.setupValues[draftKey] == ["channelId": ""])
    #expect(viewModel.accountDisplayNames[draftKey] == "")
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
        loadRuntimeStatuses: { _, _ in [:] },
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

@Test func pluginSettingsResourceScopeFiltersToSelectedApp() {
    let work = Resource(
        id: "res_work",
        accountID: "acc_work",
        pluginID: "com.status.github",
        type: "repository",
        name: "statusfoundry/status"
    )
    let personal = Resource(
        id: "res_personal",
        accountID: "acc_personal",
        pluginID: "com.status.github",
        type: "repository",
        name: "sil/status"
    )

    #expect(PluginSettingsResourceScope.resources([work, personal], selectedAccountID: "acc_work") == [work])
    #expect(PluginSettingsResourceScope.resources([work, personal], selectedAccountID: "acc_personal") == [personal])
}

@Test func pluginSettingsResourceScopeHidesResourcesForUnsavedApp() {
    let resource = Resource(
        id: "res_work",
        accountID: "acc_work",
        pluginID: "com.status.github",
        type: "repository",
        name: "statusfoundry/status"
    )

    #expect(PluginSettingsResourceScope.resources([resource], selectedAccountID: nil).isEmpty)
    #expect(PluginSettingsResourceScope.resources([resource], selectedAccountID: "__new__:com.status.github").isEmpty)
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
@Test func pluginStoreViewModelSavesCustomAppRuleConditionsAndSafeActions() async throws {
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
        id: "acc_personal",
        pluginID: plugin.id,
        accountName: "Personal",
        variables: [:]
    )
    var storedRules: [Rule] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRules: { _ in storedRules },
        saveRule: { rule in
            storedRules.removeAll { $0.id == rule.id }
            storedRules.append(rule)
        },
        installPlugin: { _ in },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [account] }
    )

    await viewModel.reload()
    await viewModel.saveCustomAppRule(
        for: plugin,
        name: "Repository release watch",
        eventType: "github.release.published",
        conditions: [
            RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("notice")),
            RuleCondition(field: "resourceName", operation: .contains, value: .string("status"))
        ],
        actions: [
            RuleActionDefinition(action: "status.inbox.add"),
            RuleActionDefinition(action: "status.open_url", parameters: ["url": "{{event.actionUrl}}"]),
            RuleActionDefinition(action: "audit.note", parameters: ["note": "Release seen for {{event.resourceName}}"])
        ]
    )

    let created = try #require(storedRules.first)
    #expect(created.id == "rule_custom_com_status_github_acc_personal_repository_release_watch")
    #expect(created.scope == .app)
    #expect(created.accountID == account.id)
    #expect(created.provider == plugin.id)
    #expect(created.conditions == [
        RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("notice")),
        RuleCondition(field: "resourceName", operation: .contains, value: .string("status"))
    ])
    #expect(created.actions == [
        RuleActionDefinition(action: "status.inbox.add"),
        RuleActionDefinition(action: "status.open_url", parameters: ["url": "{{event.actionUrl}}"]),
        RuleActionDefinition(action: "audit.note", parameters: ["note": "Release seen for {{event.resourceName}}"])
    ])
}

@MainActor
@Test func pluginStoreViewModelRequiresWriteGrantForReviewRequiredPreset() async throws {
    let plugin = InstalledPlugin(
        id: "com.status.jira",
        name: "Jira",
        author: "Status Foundry",
        description: "Jira issue creation.",
        category: "operations",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.status.jira",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let account = PluginAccountConfiguration(
        id: "acc_ops",
        pluginID: plugin.id,
        accountName: "Ops",
        variables: [:]
    )
    let preset = Rule(
        id: "rule_jira_issue",
        name: "Create Jira issue",
        enabled: false,
        provider: plugin.id,
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "jira.createIssue", parameters: ["summary": "{{event.title}}"])]
    )
    var storedRules: [Rule] = []
    var granted = false
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRules: { _ in [preset] + storedRules },
        saveRule: { rule in
            storedRules.removeAll { $0.id == rule.id }
            storedRules.append(rule)
        },
        loadActions: { _ in [
            PackagedPluginAction(id: "jira.createIssue", label: "Create Jira issue", requiresWritePermission: true, request: "create_issue")
        ] },
        installPlugin: { _ in },
        loadPermissions: { _ in [
            InstalledPluginPermission(id: "plp_write", pluginID: plugin.id, permission: .writeActions, granted: granted)
        ] },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [account] }
    )

    await viewModel.reload()
    await viewModel.setRulePreset(preset, enabled: true, for: plugin)

    #expect(storedRules.isEmpty)
    #expect(viewModel.loadError == "Grant Write actions permission before enabling this rule.")

    granted = true
    await viewModel.reload()
    await viewModel.setRulePreset(preset, enabled: true, for: plugin)

    let saved = try #require(storedRules.first)
    #expect(saved.enabled)
    #expect(saved.scope == .app)
    #expect(saved.accountID == account.id)
    #expect(saved.actions == preset.actions)
}

@MainActor
@Test func pluginStoreViewModelRequiresWriteGrantForCustomWebhookRule() async throws {
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
    var granted = false
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRules: { _ in storedRules },
        saveRule: { rule in
            storedRules.removeAll { $0.id == rule.id }
            storedRules.append(rule)
        },
        installPlugin: { _ in },
        loadPermissions: { _ in [
            InstalledPluginPermission(id: "plp_write", pluginID: plugin.id, permission: .writeActions, granted: granted)
        ] },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [account] }
    )

    await viewModel.reload()
    await viewModel.saveCustomAppRule(
        for: plugin,
        name: "Webhook workflow failures",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "webhook.post", parameters: ["url": "https://example.com/hooks/status"])]
    )

    #expect(storedRules.isEmpty)
    #expect(viewModel.loadError == "Grant Write actions permission before saving this rule.")

    granted = true
    await viewModel.reload()
    await viewModel.saveCustomAppRule(
        for: plugin,
        name: "Webhook workflow failures",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "webhook.post", parameters: ["url": "https://example.com/hooks/status"])]
    )

    let saved = try #require(storedRules.first)
    #expect(saved.actions == [
        RuleActionDefinition(action: "webhook.post", parameters: ["url": "https://example.com/hooks/status"])
    ])
}

@MainActor
@Test func pluginStoreViewModelSavesDeclaredThirdPartyWriteActionRule() async throws {
    let plugin = InstalledPlugin(
        id: "com.example.linear",
        name: "Linear",
        author: "Example",
        description: "Linear issue creation.",
        category: "operations",
        trustLevel: .verifiedThirdParty,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.example.linear",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let account = PluginAccountConfiguration(
        id: "acc_linear",
        pluginID: plugin.id,
        accountName: "Team",
        variables: [:]
    )
    let action = PackagedPluginAction(
        id: "linear.createIssue",
        label: "Create Linear issue",
        requiresWritePermission: true,
        inputSchema: PackagedPluginActionInputSchema(fields: [
            PackagedPluginActionInputField(
                key: "title",
                label: "Title",
                type: .template,
                required: true,
                defaultValue: "{{event.title}}"
            )
        ]),
        request: "create_issue"
    )
    var storedRules: [Rule] = []
    var granted = false
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadRules: { _ in storedRules },
        saveRule: { rule in
            storedRules.removeAll { $0.id == rule.id }
            storedRules.append(rule)
        },
        loadActions: { _ in [action] },
        installPlugin: { _ in },
        loadPermissions: { _ in [
            InstalledPluginPermission(id: "plp_write", pluginID: plugin.id, permission: .writeActions, granted: granted)
        ] },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [account] }
    )

    await viewModel.reload()
    await viewModel.saveCustomAppRule(
        for: plugin,
        name: "Linear workflow failures",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "linear.createIssue", parameters: ["title": "{{event.title}}"])]
    )

    #expect(storedRules.isEmpty)
    #expect(viewModel.loadError == "Grant Write actions permission before saving this rule.")

    granted = true
    await viewModel.reload()
    await viewModel.saveCustomAppRule(
        for: plugin,
        name: "Linear workflow failures",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "linear.createIssue", parameters: ["title": "{{event.title}}"])]
    )

    let saved = try #require(storedRules.first)
    #expect(saved.provider == plugin.id)
    #expect(saved.accountID == account.id)
    #expect(saved.actions == [
        RuleActionDefinition(action: "linear.createIssue", parameters: ["title": "{{event.title}}"])
    ])
}

@MainActor
@Test func pluginStoreViewModelPreviewsDeclaredProviderWriteActionRequest() async throws {
    let plugin = InstalledPlugin(
        id: "com.example.linear",
        name: "Linear",
        author: "Example",
        description: "Linear issue creation.",
        category: "operations",
        trustLevel: .verifiedThirdParty,
        installedVersion: "0.1.0",
        installPath: "/tmp/com.example.linear",
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
    let account = PluginAccountConfiguration(
        id: "acc_linear",
        pluginID: plugin.id,
        accountName: "Team",
        variables: [:]
    )
    let action = PackagedPluginAction(
        id: "linear.createIssue",
        label: "Create Linear issue",
        requiresWritePermission: true,
        inputSchema: PackagedPluginActionInputSchema(fields: [
            PackagedPluginActionInputField(
                key: "title",
                label: "Title",
                type: .template,
                required: true,
                defaultValue: "{{event.title}}"
            )
        ]),
        request: "create_issue"
    )
    var capturedAction: ActionRuntimeProviderAction?
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        loadActions: { _ in [action] },
        installPlugin: { _ in },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in [account] },
        previewProviderActionRequest: { action in
            capturedAction = action
            return "POST https://api.linear.app/graphql\nBody: redacted"
        }
    )

    await viewModel.reload()
    let preview = try await viewModel.previewProviderActionRequests(
        for: plugin,
        eventType: "github.workflow.failed",
        actions: [
            RuleActionDefinition(action: "linear.createIssue", parameters: ["title": "{{event.title}}"])
        ]
    )

    let previewAction = try #require(capturedAction)
    #expect(preview == "POST https://api.linear.app/graphql\nBody: redacted")
    #expect(previewAction.action == "linear.createIssue")
    #expect(previewAction.provider == plugin.id)
    #expect(previewAction.parameters["account_id"] == account.id)
    #expect(previewAction.parameters["title"] == "{{event.title}}")
    #expect(previewAction.event.type == "github.workflow.failed")
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
                redirectURI: "com.statusfoundry.status.oauth:/github",
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
    let launchedURL = await viewModel.beginOAuthConnection(plugin)

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
    #expect(query["redirect_uri"] == "com.statusfoundry.status.oauth:/github")
    #expect(query["scope"] == "repo")
    #expect(query["code_challenge_method"] == "S256")
    #expect(query["code_challenge"]?.isEmpty == false)
    #expect(viewModel.oauthConnectionErrors["\(plugin.id):\(selectedAccountID ?? "__new__:")"] == nil)
}

@MainActor
@Test func pluginStoreViewModelUsesSetupOAuthClientIDWhenDeclared() async throws {
    var plugin = oauthGitHubPlugin()
    plugin.setup = PackagedPluginSetup(
        title: "OAuth setup",
        fields: [
            PackagedPluginSetupField(
                id: PluginOAuth.clientIDSetupFieldKey,
                label: "OAuth client ID",
                type: .text,
                required: true
            )
        ]
    )
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadPermissions: { _ in grantedOAuthPermissions(pluginID: plugin.id) },
        canConfigurePlugin: { _ in true }
    )

    await viewModel.reload()
    viewModel.updateSetupValue(plugin, fieldID: PluginOAuth.clientIDSetupFieldKey, value: "custom-client-id")
    let launchedURL = await viewModel.beginOAuthConnection(plugin)

    let key = "\(plugin.id):\(viewModel.selectedAccountIDs[plugin.id] ?? "__new__:")"
    let url = try #require(viewModel.oauthConnectionURLs[key])
    #expect(launchedURL == url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(query["client_id"] == "custom-client-id")
    #expect(viewModel.oauthConnectionErrors[key] == nil)
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
    let launchedURL = await viewModel.beginOAuthConnection(plugin)

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
                redirectURI: "com.statusfoundry.status.oauth:/github",
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
    await viewModel.beginOAuthConnection(plugin)

    let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
    let key = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
    let authorizationURL = try #require(viewModel.oauthConnectionURLs[key])
    let state = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "state" }?
        .value)
    let callbackURL = try #require(URL(string: "com.statusfoundry.status.oauth:/github?code=code-456&state=\(state)"))

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
@Test func pluginStoreViewModelSelectsSavedAppAfterOAuthSetup() async throws {
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
                redirectURI: "com.statusfoundry.status.oauth:/github",
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
    var accounts: [PluginAccountConfiguration] = []
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [plugin] },
        loadAvailable: { [] },
        installPlugin: { _ in },
        loadPermissions: { _ in grantedOAuthPermissions(pluginID: plugin.id) },
        canConfigurePlugin: { _ in true },
        loadAccounts: { _ in accounts },
        completeOAuthConnection: { plugin, accountID, displayName, values, _, _ in
            #expect(accountID == nil)
            #expect(displayName == "Status Repo")
            #expect(values == ["owner": "statusfoundry", "repo": "status"])
            accounts = [
                PluginAccountConfiguration(
                    id: "acc_status_repo",
                    pluginID: plugin.id,
                    accountName: displayName ?? plugin.name,
                    variables: values
                )
            ]
            return "Saved Status Repo."
        }
    )

    await viewModel.reload()
    viewModel.updateSetupValue(plugin, fieldID: "owner", value: "statusfoundry")
    viewModel.updateSetupValue(plugin, fieldID: "repo", value: "status")
    viewModel.updateAccountDisplayName(plugin, value: "Status Repo")
    await viewModel.beginOAuthConnection(plugin)

    let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
    let draftKey = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
    let authorizationURL = try #require(viewModel.oauthConnectionURLs[draftKey])
    let state = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "state" }?
        .value)
    let callbackURL = try #require(URL(string: "com.statusfoundry.status.oauth:/github?code=code-456&state=\(state)"))

    await viewModel.completeOAuthConnection(callbackURL: callbackURL)

    let persistedKey = "\(plugin.id):acc_status_repo"
    #expect(viewModel.selectedAccountIDs[plugin.id] == "acc_status_repo")
    #expect(viewModel.setupResults[persistedKey] == "Saved Status Repo.")
    #expect(viewModel.setupResults[draftKey] == nil)
    #expect(viewModel.oauthConnectionURLs[draftKey] == nil)
    #expect(viewModel.accountDisplayNames[persistedKey] == "Status Repo")
}

@MainActor
@Test func pluginStoreViewModelIgnoresBroadcastOAuthCallbackWithoutPendingConnection() async throws {
    let viewModel = PluginStoreViewModel(
        loadInstalled: { [] },
        loadAvailable: { [] },
        installPlugin: { _ in }
    )
    let callbackURL = try #require(URL(string: "com.statusfoundry.status.oauth:/github?code=code-456&state=missing"))

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
                redirectURI: "com.statusfoundry.status.oauth:/github",
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
    await viewModel.beginOAuthConnection(plugin)

    let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
    let key = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
    let authorizationURL = try #require(viewModel.oauthConnectionURLs[key])
    let state = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "state" }?
        .value)
    let callbackURL = try #require(URL(string: "com.statusfoundry.status.oauth:/github?code=code-456&state=\(state)"))

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
                redirectURI: "com.statusfoundry.status.oauth:/github",
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

private func setupChecklistPlugin(
    id: String,
    name: String,
    auth: PackagedPluginAuth?,
    setup: PackagedPluginSetup?
) -> InstalledPlugin {
    InstalledPlugin(
        id: id,
        name: name,
        author: "Status Foundry",
        description: "\(name) checks.",
        category: "development",
        trustLevel: .official,
        installedVersion: "0.1.0",
        installPath: "/tmp/\(id)",
        auth: auth,
        setup: setup,
        installedAt: Date(timeIntervalSince1970: 1_783_433_520),
        updatedAt: Date(timeIntervalSince1970: 1_783_433_520)
    )
}

private func setupChecklistPermissions(
    _ permissions: [PluginPermission],
    granted: Set<PluginPermission>
) -> [InstalledPluginPermission] {
    permissions.map { permission in
        InstalledPluginPermission(
            id: "plp_\(permission.rawValue)",
            pluginID: "plugin",
            permission: permission,
            granted: granted.contains(permission)
        )
    }
}

private func setupChecklistFields(_ plugin: InstalledPlugin) -> [PackagedPluginSetupField] {
    (plugin.auth?.fields ?? []) + (plugin.setup?.fields ?? [])
}

private func registryPluginSummary(id: String, latestVersion: String?) -> RegistryPluginSummary {
    RegistryPluginSummary(
        id: id,
        name: "GitHub",
        summary: "GitHub repository checks.",
        description: "Read-only GitHub status events.",
        category: "development",
        author: PluginAuthor(name: "Status Foundry", publisherId: "status-foundry"),
        trustLevel: .official,
        latestVersion: latestVersion,
        platforms: [.macOS, .iOS],
        permissions: [.network],
        domains: ["api.github.com"]
    )
}
