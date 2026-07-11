import AppKit
import StatusCore
import StatusUI
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

@main
struct StatusMacApp: App {
    var body: some Scene {
        WindowGroup("Status", id: "main") {
            MacRootView()
                .frame(minWidth: 980, minHeight: 680)
                .background(Color(nsColor: .windowBackgroundColor))
                .background(MacWindowConfigurator())
                .onOpenURL { url in
                    StatusOAuthCallbackRouter.publish(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewStatusWindowCommand()
            }
        }

        WindowGroup("App Settings", id: "integration-settings", for: String.self) { $settingsRoute in
            if let settingsRoute {
                MacPluginSettingsWindow(route: MacPluginSettingsRoute(rawValue: settingsRoute))
                    .onOpenURL { url in
                        StatusOAuthCallbackRouter.publish(url)
                    }
            }
        }
    }
}

private struct NewStatusWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New") {
            openWindow(id: "main")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

private struct MacPluginSettingsWindow: View {
    let route: MacPluginSettingsRoute

    var body: some View {
        PluginSettingsContainerView(
            viewModel: makePluginStoreViewModel(platform: .macOS),
            pluginID: route.pluginID,
            initialAccountID: route.accountID,
            onAppsChanged: {
                NotificationCenter.default.post(name: .statusConfiguredAppsDidChange, object: nil)
            },
            notificationPreferencesViewModel: makeNotificationPreferencesViewModel(),
            notificationPreferenceGroups: { plugin, accountID in
                (try? notificationPreferenceGroups(plugin: plugin, accountID: accountID)) ?? []
            }
        )
        .frame(minWidth: 640, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(MacWindowConfigurator())
        .navigationTitle("App Settings")
    }

    private func makePluginStoreViewModel(platform: PluginPlatform) -> PluginStoreViewModel {
        let registry = PluginRegistryClient(baseURL: StatusAppConfiguration.registryBaseURL())
        return PluginStoreViewModel {
            try bootstrapBundledPlugins()
            return try LocalStatusStore.openApplicationSupportStore().installedPlugins()
        } loadAvailable: {
            try await registry.plugins(platform: platform, coreVersion: "0.1.0")
        } loadRuntimeStatuses: { plugins, accountsByPluginID in
            try pluginRuntimeStatuses(for: plugins, accountsByPluginID: accountsByPluginID)
        } loadPluginResources: { plugin in
            try LocalStatusStore.openApplicationSupportStore().resources(pluginID: plugin.id)
        } loadRules: { plugin in
            try LocalStatusStore.openApplicationSupportStore()
                .rules()
                .filter { $0.provider == plugin.id }
        } saveRule: { rule in
            try LocalStatusStore.openApplicationSupportStore().upsertRule(rule, updatedAt: Date())
        } deleteRule: { rule in
            try LocalStatusStore.openApplicationSupportStore().deleteRule(id: rule.id)
        } loadActions: { plugin in
            try LocalStatusStore.openApplicationSupportStore().installedPluginDefinition(pluginID: plugin.id)?.actions ?? []
        } loadDashboardTileFields: { _, accountID in
            try dashboardTileFields(accountID: accountID)
        } saveDashboardTileFields: { plugin, accountID, fields in
            try saveDashboardTileFields(pluginID: plugin.id, accountID: accountID, fields: fields)
        } installPlugin: { _ in
        } removePlugin: { _ in
        } loadPermissions: { plugin in
            try LocalStatusStore.openApplicationSupportStore().pluginPermissions(pluginID: plugin.id)
        } setPermissionGrant: { plugin, permission, granted in
            try LocalStatusStore.openApplicationSupportStore().setPluginPermission(
                pluginID: plugin.id,
                permission: permission,
                granted: granted,
                grantedAt: granted ? Date() : nil
            )
        } loadTriggers: { plugin in
            try LocalStatusStore.openApplicationSupportStore()
                .triggers()
                .filter { $0.pluginID == plugin.id }
        } setTriggerEnabled: { _, trigger, enabled in
            try LocalStatusStore.openApplicationSupportStore().setTriggerEnabled(
                id: trigger.id,
                enabled: enabled,
                updatedAt: Date()
            )
        } canRunPlugin: { plugin in
            canRunConfiguredPlugin(pluginID: plugin.id)
        } runPlugin: { plugin, account in
            try await runConfiguredPluginCheck(pluginID: plugin.id, accountID: account.id, accountName: account.accountName)
        } canConfigurePlugin: { plugin in
            plugin.auth?.type == .oauth2 || plugin.auth?.fields.isEmpty == false || plugin.setup?.fields.contains(where: \.type.isPlainConfigurationField) == true
        } loadAccounts: { plugin in
            try LocalStatusStore.openApplicationSupportStore().accountConfigurations(pluginID: plugin.id)
        } loadConfigurationValues: { plugin, accountID in
            try configuredPluginValues(pluginID: plugin.id, accountID: accountID)
        } saveConfigurationValues: { plugin, accountID, displayName, values in
            try savePluginSetup(plugin: plugin, accountID: accountID, displayName: displayName, values: values)
        } deleteConfiguration: { _, account in
            try PluginSetupConfiguration.deleteAccountConfiguration(
                accountID: account.id,
                store: LocalStatusStore.openApplicationSupportStore(),
                credentialStore: KeychainCredentialStore()
            )
            return "Removed \(account.accountName)."
        } completeOAuthConnection: { plugin, accountID, displayName, values, request, callbackURL in
            try await saveOAuthPluginSetup(
                plugin: plugin,
                accountID: accountID,
                displayName: displayName,
                values: values,
                request: request,
                callbackURL: callbackURL
            )
        } testPluginRequest: { plugin, account, requestID in
            try await testConfiguredPluginRequest(pluginID: plugin.id, requestID: requestID, accountID: account.id)
        } previewProviderActionRequest: { action in
            try await PluginRuntimeService(store: LocalStatusStore.openApplicationSupportStore())
                .previewProviderActionRequest(action)
                .summary
        }
    }

    private func pluginRuntimeStatuses(
        for plugins: [InstalledPlugin],
        accountsByPluginID: [String: [PluginAccountConfiguration]]
    ) throws -> [String: PluginRuntimeStatus] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        var statuses: [String: PluginRuntimeStatus] = [:]
        for plugin in plugins {
            for account in accountsByPluginID[plugin.id, default: []] {
                guard let job = try store.recentJobs(pluginID: plugin.id, accountID: account.id, limit: 1).first else {
                    continue
                }
                statuses["\(plugin.id):\(account.id)"] = PluginRuntimeStatus(
                    pluginID: job.pluginID,
                    status: job.status,
                    detail: job.error ?? "Job \(job.id) completed from \(job.triggerID).",
                    timestamp: job.finishedAt ?? job.startedAt ?? job.queuedAt,
                    emittedEventCount: job.emittedEventIDs.count
                )
            }
        }
        return statuses
    }

    private func canRunConfiguredPlugin(pluginID: String) -> Bool {
        guard let store = try? LocalStatusStore.openApplicationSupportStore(),
              (try? store.accountConfigurations(pluginID: pluginID).isEmpty == false) == true else {
            return false
        }
        return ((try? store.triggers()) ?? []).contains { trigger in
            trigger.pluginID == pluginID && trigger.kind == .manual && trigger.enabled && trigger.requestID != nil
        }
    }

    private func configuredPluginValues(pluginID: String, accountID: String?) throws -> [String: String] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        if let accountID {
            return try PluginSetupConfiguration.configuredValues(pluginID: pluginID, accountID: accountID, store: store)
        }
        return try PluginSetupConfiguration.configuredValues(pluginID: pluginID, store: store)
    }

    private func savePluginSetup(plugin: InstalledPlugin, accountID: String?, displayName: String?, values: [String: String]) throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store)
        return try PluginSetupConfiguration.saveValues(
            values,
            for: plugin,
            service: service,
            credentialStore: KeychainCredentialStore(),
            accountID: accountID,
            displayNameOverride: displayName
        )
    }

    private func saveOAuthPluginSetup(
        plugin: InstalledPlugin,
        accountID: String?,
        displayName: String?,
        values: [String: String],
        request: PluginOAuthAuthorizationRequest,
        callbackURL: URL
    ) async throws -> String {
        guard let auth = plugin.auth else {
            throw PluginOAuthError.missingOAuthConfiguration(plugin.id)
        }
        let tokenSet = try await PluginOAuth.tokenSet(
            pluginID: plugin.id,
            auth: auth,
            request: request,
            callbackURL: callbackURL
        )
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store)
        return try PluginSetupConfiguration.saveOAuthTokenSet(
            tokenSet,
            setupValues: values,
            for: plugin,
            service: service,
            credentialStore: KeychainCredentialStore(),
            accountID: accountID,
            displayNameOverride: displayName
        )
    }

    private func dashboardTileFields(accountID: String) throws -> [String] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let value = try store.accountConfiguration(accountID: accountID)?
            .variables[PluginSetupConfiguration.dashboardTileFieldsKey] ?? ""
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func saveDashboardTileFields(pluginID: String, accountID: String, fields: [String]) throws {
        let store = try LocalStatusStore.openApplicationSupportStore()
        guard var configuration = try store.accountConfiguration(accountID: accountID) else {
            throw PluginRuntimeServiceError.accountNotConfigured(pluginID)
        }
        configuration.variables[PluginSetupConfiguration.dashboardTileFieldsKey] = fields.joined(separator: ",")
        try store.upsertAccountConfiguration(configuration, updatedAt: Date())
    }

    private func runConfiguredPluginCheck(pluginID: String, accountID: String, accountName: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
        let job = try service.enqueueManualConfiguredPluginRun(
            pluginID: pluginID,
            accountID: accountID
        )
        let result = try await service.runQueuedPluginJob(jobID: job.id)
        return "\(accountName): \(result.mappingOutput.resources.count) resource stored, \(result.mappingOutput.events.count) events processed."
    }

    private func testConfiguredPluginRequest(pluginID: String, requestID: String, accountID: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
        return try await service.previewConfiguredPluginRequest(
            pluginID: pluginID,
            requestID: requestID,
            accountID: accountID
        ).summary
    }

    private func pluginInstallRoot() throws -> URL {
        let databaseURL = try LocalStatusStore.applicationSupportDatabaseURL()
        let directory = databaseURL.deletingLastPathComponent().appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func bootstrapBundledPlugins() throws {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let installer = BundledPluginInstaller(store: store, installRoot: try pluginInstallRoot())
        try installer.installAll()
        try store.upsertSyncState(
            ownerType: "app",
            ownerID: "bundled-plugins",
            cursor: "installed",
            updatedAt: Date()
        )
    }
}

private struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}

private struct MacPluginSettingsRoute: Equatable {
    var pluginID: String
    var accountID: String?

    init(pluginID: String, accountID: String? = nil) {
        self.pluginID = pluginID
        self.accountID = accountID
    }

    init(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        self.pluginID = parts.first.map(String.init) ?? rawValue
        if parts.count == 2 {
            let accountID = String(parts[1])
            self.accountID = accountID.isEmpty ? nil : accountID
        } else {
            self.accountID = nil
        }
    }

    var rawValue: String {
        "\(pluginID)|\(accountID ?? "")"
    }
}

@MainActor
private func makeNotificationPreferencesViewModel() -> NotificationPreferencesViewModel {
    NotificationPreferencesViewModel {
        try notificationPreferenceGroups(plugin: nil, accountID: nil)
    } loadPreferences: {
        try LocalStatusStore.openApplicationSupportStore().notificationPreferences()
    } setPreference: { pluginID, accountID, eventType, mode in
        try setNotificationPreference(pluginID: pluginID, accountID: accountID, eventType: eventType, mode: mode)
    }
}

private func notificationPreferenceGroups(plugin: InstalledPlugin?, accountID: String?) throws -> [NotificationPreferencePluginGroup] {
    try bootstrapBundledPluginsForNotificationPreferences()
    let store = try LocalStatusStore.openApplicationSupportStore()
    let plugins = try plugin.map { [$0] } ?? store.installedPlugins()
    return try plugins.flatMap { plugin in
        let definition = try store.installedPluginDefinition(pluginID: plugin.id)
        let events = notificationPreferenceEvents(from: definition)
        if let accountID {
            let account = try store.accountConfiguration(accountID: accountID)
            return [
                NotificationPreferencePluginGroup(
                    id: accountID,
                    pluginID: plugin.id,
                    accountID: accountID,
                    name: account?.accountName ?? plugin.name,
                    events: events
                )
            ]
        }
        let accounts = try store.accountConfigurations(pluginID: plugin.id)
        if accounts.isEmpty {
            return [
                NotificationPreferencePluginGroup(id: plugin.id, pluginID: plugin.id, name: plugin.name, events: events)
            ]
        }
        return accounts.map { account in
            NotificationPreferencePluginGroup(
                id: account.id,
                pluginID: plugin.id,
                accountID: account.id,
                name: account.accountName,
                events: events
            )
        }
    }
}

private func notificationPreferenceEvents(from definition: PluginPackageDefinition?) -> [NotificationPreferenceEventRow] {
    (definition?.events ?? [])
        .sorted { lhs, rhs in lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending }
        .map { event in
            NotificationPreferenceEventRow(
                type: event.type,
                label: event.label,
                defaultMode: event.notificationDefault
            )
        }
}

private func setNotificationPreference(pluginID: String, accountID: String?, eventType: String?, mode: NotificationMode?) throws {
    let store = try LocalStatusStore.openApplicationSupportStore()
    let scope: NotificationPreferenceScope = if eventType != nil {
        .event
    } else if accountID != nil {
        .app
    } else {
        .plugin
    }
    if let mode {
        try store.upsertNotificationPreference(
            NotificationPreference(
                id: notificationPreferenceID(pluginID: pluginID, accountID: accountID, eventType: eventType),
                scope: scope,
                pluginID: pluginID,
                accountID: accountID,
                eventType: eventType,
                mode: mode,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    } else {
        try store.deleteNotificationPreference(pluginID: pluginID, scope: scope, eventType: eventType, accountID: accountID)
    }
}

private func notificationPreferenceID(pluginID: String, accountID: String?, eventType: String?) -> String {
    let suffix = ([pluginID, accountID, eventType].compactMap { $0 }.joined(separator: "_"))
        .replacingOccurrences(of: #"[^a-zA-Z0-9_]+"#, with: "_", options: .regularExpression)
        .lowercased()
    return "ntp_\(suffix)"
}

private func bootstrapBundledPluginsForNotificationPreferences() throws {
    let store = try LocalStatusStore.openApplicationSupportStore()
    let databaseURL = try LocalStatusStore.applicationSupportDatabaseURL()
    let directory = databaseURL.deletingLastPathComponent().appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let installer = BundledPluginInstaller(store: store, installRoot: directory)
    try installer.installAll()
    try store.upsertSyncState(
        ownerType: "app",
        ownerID: "bundled-plugins",
        cursor: "installed",
        updatedAt: Date()
    )
}

private struct MacRootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var selection: MacSection? = .overview
    @State private var sidebarApps: [SidebarApp] = []
    @State private var sidebarPluginError: String?
    @State private var dashboardReloadToken = 0

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("Apps") {
                    if sidebarApps.isEmpty {
                        Text(sidebarPluginError ?? "No apps configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sidebarApps) { app in
                            NavigationLink(value: MacSection.app(pluginID: app.pluginID, accountID: app.accountID)) {
                                Label {
                                    Text(app.name)
                                        .lineLimit(1)
                                } icon: {
                                    IntegrationIcon(
                                        provider: app.pluginID,
                                        icon: app.iconPath,
                                        iconAsset: app.iconAsset,
                                        accentColor: app.accentColor,
                                        size: 22
                                    )
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink(value: MacSection.overview) {
                        Label("Overview", systemImage: "rectangle.grid.2x2")
                    }
                    NavigationLink(value: MacSection.alerts) {
                        Label("Alerts", systemImage: "bell")
                    }
                    NavigationLink(value: MacSection.integrations) {
                        Label("Plugins", systemImage: "puzzlepiece.extension")
                    }
                    NavigationLink(value: MacSection.rules) {
                        Label("Cross-App", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink(value: MacSection.audit) {
                        Label("Audit Log", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink(value: MacSection.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Status")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            switch selection ?? .overview {
            case .overview:
                detailWithAppTabs {
                    DashboardContainerView(
                        viewModel: makeDashboardViewModel(),
                        reloadToken: dashboardReloadToken,
                        openApp: { app in
                            selection = .app(
                                pluginID: app.provider,
                                accountID: app.id
                            )
                        }
                    )
                }
                    .navigationTitle("Overview")
            case .alerts:
                detailWithAppTabs {
                    AlertsContainerView(viewModel: makeAlertsViewModel())
                }
                    .navigationTitle("Alerts")
            case .integrations:
                detailWithAppTabs {
                    PluginStoreContainerView(
                        viewModel: makePluginStoreViewModel(platform: .macOS),
                        openSettings: { plugin in
                            openWindow(
                                id: "integration-settings",
                                value: MacPluginSettingsRoute(pluginID: plugin.id).rawValue
                            )
                        },
                        onAppsChanged: {
                            handleConfiguredAppsChanged()
                        },
                        installLocalPlugin: {
                            try await installLocalPluginFolder()
                        },
                        previewPluginFixture: { plugin, accountID in
                            try await previewPluginFixture(plugin: plugin, accountID: accountID)
                        }
                    )
                }
                    .navigationTitle("Plugins")
            case .app(let pluginID, let accountID):
                detailWithAppTabs {
                    MacPluginAppDetail(
                        pluginID: pluginID,
                        accountID: accountID,
                        openSettings: {
                            openWindow(
                                id: "integration-settings",
                                value: MacPluginSettingsRoute(pluginID: pluginID, accountID: accountID).rawValue
                            )
                        },
                        runPlugin: { pluginID, accountID, accountName in
                            let result = try await runConfiguredPluginCheck(
                                pluginID: pluginID,
                                accountID: accountID,
                                accountName: accountName
                            )
                            NotificationCenter.default.post(name: .statusAppDataDidChange, object: nil)
                            return result
                        }
                    )
                }
                    .navigationTitle(appNavigationTitle(pluginID: pluginID, accountID: accountID))
            case .rules:
                detailWithAppTabs {
                    RulesContainerView(viewModel: makeRulesViewModel())
                }
                    .navigationTitle("Cross-App Rules")
            case .audit:
                detailWithAppTabs {
                    AuditLogContainerView(viewModel: makeAuditLogViewModel())
                }
                    .navigationTitle("Audit Log")
            case .settings:
                detailWithAppTabs {
                    StatusSettingsView(
                        registryURL: registryBaseURL,
                        databasePath: applicationDatabasePath(),
                        pluginInstallPath: applicationPluginInstallPath(),
                        runtimeAction: makeRegistryCheckAction(),
                        notificationPreferencesViewModel: makeNotificationPreferencesViewModel(),
                        notificationHistoryViewModel: makeNotificationHistoryViewModel()
                    )
                }
                    .navigationTitle("Settings")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            loadSidebarPlugins()
            await runBackgroundPluginLoop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .statusConfiguredAppsDidChange)) { _ in
            handleConfiguredAppsChanged()
        }
    }

    private func handleConfiguredAppsChanged() {
        loadSidebarPlugins()
        repairSelectionAfterSidebarReload()
        dashboardReloadToken += 1
    }

    private func loadSidebarPlugins() {
        do {
            try bootstrapBundledPlugins()
            let store = try LocalStatusStore.openApplicationSupportStore()
            sidebarApps = try store.installedPlugins()
                .filter(\.enabled)
                .flatMap { plugin in
                    let accounts = try store.accountConfigurations(pluginID: plugin.id)
                    return accounts.map { account in
                        SidebarApp(
                            pluginID: plugin.id,
                            accountID: account.id,
                            name: account.accountName,
                            iconPath: plugin.iconPath,
                            iconAsset: plugin.iconAsset,
                            accentColor: plugin.accentColor
                        )
                    }
                }
            sidebarPluginError = nil
        } catch {
            sidebarApps = []
            sidebarPluginError = error.localizedDescription
        }
    }

    private func repairSelectionAfterSidebarReload() {
        guard case let .app(pluginID, accountID) = selection else {
            return
        }
        let selectedAppStillExists = sidebarApps.contains { app in
            app.pluginID == pluginID && app.accountID == accountID
        }
        if selectedAppStillExists == false {
            selection = .overview
        }
    }

    @ViewBuilder
    private func detailWithAppTabs<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            if columnVisibility == .detailOnly && sidebarApps.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sidebarApps) { app in
                            collapsedAppTab(for: app)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
            content()
        }
    }

    private func collapsedAppTab(for app: SidebarApp) -> some View {
        let isSelected = selection == .app(pluginID: app.pluginID, accountID: app.accountID)

        return Button {
            selection = .app(pluginID: app.pluginID, accountID: app.accountID)
        } label: {
            IntegrationIcon(
                provider: app.pluginID,
                icon: app.iconPath,
                iconAsset: app.iconAsset,
                accentColor: app.accentColor,
                size: 28
            )
            .frame(width: 38, height: 34)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.52), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(app.name)
        .accessibilityLabel(Text(app.name))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func appNavigationTitle(pluginID: String, accountID: String?) -> String {
        sidebarApps.first { app in
            app.pluginID == pluginID && app.accountID == accountID
        }?.name ?? "App"
    }

    private func makeDashboardViewModel() -> DashboardViewModel {
        DashboardViewModel {
            try bootstrapBundledPlugins()
            return try LocalStatusStore.openApplicationSupportStore().dashboardSnapshot()
        }
    }

    private func makePluginStoreViewModel(platform: PluginPlatform) -> PluginStoreViewModel {
        let registry = PluginRegistryClient(baseURL: registryBaseURL)
        return PluginStoreViewModel {
            try bootstrapBundledPlugins()
            return try LocalStatusStore.openApplicationSupportStore().installedPlugins()
        } loadAvailable: {
            try await registry.plugins(platform: platform, coreVersion: "0.1.0")
        } loadRuntimeStatuses: { plugins, accountsByPluginID in
            try pluginRuntimeStatuses(for: plugins, accountsByPluginID: accountsByPluginID)
        } loadPluginResources: { plugin in
            try LocalStatusStore.openApplicationSupportStore().resources(pluginID: plugin.id)
        } loadRules: { plugin in
            try LocalStatusStore.openApplicationSupportStore()
                .rules()
                .filter { $0.provider == plugin.id }
        } saveRule: { rule in
            try LocalStatusStore.openApplicationSupportStore().upsertRule(rule, updatedAt: Date())
        } deleteRule: { rule in
            try LocalStatusStore.openApplicationSupportStore().deleteRule(id: rule.id)
        } loadActions: { plugin in
            try LocalStatusStore.openApplicationSupportStore().installedPluginDefinition(pluginID: plugin.id)?.actions ?? []
        } loadDashboardTileFields: { _, accountID in
            try dashboardTileFields(accountID: accountID)
        } saveDashboardTileFields: { plugin, accountID, fields in
            try saveDashboardTileFields(pluginID: plugin.id, accountID: accountID, fields: fields)
        } installPlugin: { plugin in
            guard let latestVersion = plugin.latestVersion else { return }
            let store = try LocalStatusStore.openApplicationSupportStore()
            let installRoot = try pluginInstallRoot()
            let installer = PluginInstaller(
                registry: registry,
                store: store,
                installRoot: installRoot
            )
            _ = try await installer.install(
                pluginID: plugin.id,
                version: latestVersion,
                trustLevel: plugin.trustLevel
            )
        } removePlugin: { plugin in
            try LocalStatusStore.openApplicationSupportStore().uninstallPlugin(id: plugin.id)
        } loadPermissions: { plugin in
            try LocalStatusStore.openApplicationSupportStore().pluginPermissions(pluginID: plugin.id)
        } setPermissionGrant: { plugin, permission, granted in
            try LocalStatusStore.openApplicationSupportStore().setPluginPermission(
                pluginID: plugin.id,
                permission: permission,
                granted: granted,
                grantedAt: granted ? Date() : nil
            )
        } loadTriggers: { plugin in
            try LocalStatusStore.openApplicationSupportStore()
                .triggers()
                .filter { $0.pluginID == plugin.id }
        } setTriggerEnabled: { _, trigger, enabled in
            try LocalStatusStore.openApplicationSupportStore().setTriggerEnabled(
                id: trigger.id,
                enabled: enabled,
                updatedAt: Date()
            )
        } canRunPlugin: { plugin in
            canRunConfiguredPlugin(pluginID: plugin.id)
        } runPlugin: { plugin, account in
            try await runConfiguredPluginCheck(pluginID: plugin.id, accountID: account.id, accountName: account.accountName)
        } canConfigurePlugin: { plugin in
            plugin.auth?.type == .oauth2 || plugin.auth?.fields.isEmpty == false || plugin.setup?.fields.contains(where: \.type.isPlainConfigurationField) == true
        } loadAccounts: { plugin in
            try LocalStatusStore.openApplicationSupportStore().accountConfigurations(pluginID: plugin.id)
        } loadConfigurationValues: { plugin, accountID in
            try configuredPluginValues(pluginID: plugin.id, accountID: accountID)
        } saveConfigurationValues: { plugin, accountID, displayName, values in
            try savePluginSetup(plugin: plugin, accountID: accountID, displayName: displayName, values: values)
        } deleteConfiguration: { _, account in
            try PluginSetupConfiguration.deleteAccountConfiguration(
                accountID: account.id,
                store: LocalStatusStore.openApplicationSupportStore(),
                credentialStore: KeychainCredentialStore()
            )
            return "Removed \(account.accountName)."
        } completeOAuthConnection: { plugin, accountID, displayName, values, request, callbackURL in
            try await saveOAuthPluginSetup(
                plugin: plugin,
                accountID: accountID,
                displayName: displayName,
                values: values,
                request: request,
                callbackURL: callbackURL
            )
        } testPluginRequest: { plugin, account, requestID in
            try await testConfiguredPluginRequest(pluginID: plugin.id, requestID: requestID, accountID: account.id)
        } previewProviderActionRequest: { action in
            try await PluginRuntimeService(store: LocalStatusStore.openApplicationSupportStore())
                .previewProviderActionRequest(action)
                .summary
        }
    }

    private var registryBaseURL: URL {
        StatusAppConfiguration.registryBaseURL()
    }

    private var registryHost: String {
        StatusAppConfiguration.registryHost()
    }

    private func makeAlertsViewModel() -> AlertsViewModel {
        AlertsViewModel {
            try bootstrapBundledPlugins()
            try reopenExpiredSnoozedItems()
            return try LocalStatusStore.openApplicationSupportStore()
                .statusItems(limit: 50)
                .filter { $0.severity >= .warning }
        } resolveItem: { item in
            try LocalStatusStore.openApplicationSupportStore().resolveStatusItem(id: item.id, at: Date())
        } snoozeItem: { item in
            let now = Date()
            try LocalStatusStore.openApplicationSupportStore()
                .snoozeStatusItem(id: item.id, until: now.addingTimeInterval(3_600), at: now)
        } dismissItem: { item in
            try LocalStatusStore.openApplicationSupportStore()
                .dismissStatusItem(id: item.id, reason: "Dismissed in Status", at: Date())
        }
    }

    private func makeRulesViewModel() -> RulesViewModel {
        RulesViewModel {
            try bootstrapBundledPlugins()
            return try LocalStatusStore.openApplicationSupportStore()
                .rules()
                .filter { $0.scope == .crossApp }
        } loadActionOptions: {
            try crossAppRuleActionOptions()
        } saveRule: { rule in
            var crossAppRule = rule
            crossAppRule.scope = .crossApp
            crossAppRule.accountID = nil
            try LocalStatusStore.openApplicationSupportStore().upsertRule(crossAppRule, updatedAt: Date())
        } deleteRule: { rule in
            try LocalStatusStore.openApplicationSupportStore().deleteRule(id: rule.id)
        }
    }

    private func crossAppRuleActionOptions() throws -> [CrossAppRuleActionOption] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        var options = CrossAppRuleActionOption.builtIn
        for plugin in try store.installedPlugins() where plugin.enabled {
            guard let definition = try store.installedPluginDefinition(pluginID: plugin.id) else {
                continue
            }
            for action in definition.actions {
                options.append(
                    CrossAppRuleActionOption(
                        action: action.id,
                        label: action.label,
                        provider: plugin.id,
                        inputFields: action.inputSchema?.fields ?? [],
                        safety: ActionRunner.safetyLevel(for: action)
                    )
                )
            }
        }
        return options
    }

    private func makeAuditLogViewModel() -> AuditLogViewModel {
        AuditLogViewModel {
            try bootstrapBundledPlugins()
            return try LocalStatusStore.openApplicationSupportStore().auditEntries(limit: 50)
        }
    }

    private func makeNotificationPreferencesViewModel() -> NotificationPreferencesViewModel {
        NotificationPreferencesViewModel {
            try notificationPreferencePluginGroups()
        } loadPreferences: {
            try LocalStatusStore.openApplicationSupportStore().notificationPreferences()
        } setPreference: { pluginID, accountID, eventType, mode in
            try setNotificationPreference(pluginID: pluginID, accountID: accountID, eventType: eventType, mode: mode)
        }
    }

    private func makeNotificationHistoryViewModel() -> NotificationHistoryViewModel {
        NotificationHistoryViewModel {
            try LocalStatusStore.openApplicationSupportStore().notifications(limit: 20)
        }
    }

    private func pluginRuntimeStatuses(
        for plugins: [InstalledPlugin],
        accountsByPluginID: [String: [PluginAccountConfiguration]]
    ) throws -> [String: PluginRuntimeStatus] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        var statuses: [String: PluginRuntimeStatus] = [:]
        for plugin in plugins {
            for account in accountsByPluginID[plugin.id, default: []] {
                guard let job = try store.recentJobs(pluginID: plugin.id, accountID: account.id, limit: 1).first else {
                    continue
                }
                statuses["\(plugin.id):\(account.id)"] = runtimeStatus(from: job)
            }
        }
        return statuses
    }

    private func runtimeStatus(from job: JobRecord) -> PluginRuntimeStatus {
        PluginRuntimeStatus(
            pluginID: job.pluginID,
            status: job.status,
            detail: runtimeStatusDetail(for: job),
            timestamp: job.finishedAt ?? job.startedAt ?? job.queuedAt,
            emittedEventCount: job.emittedEventIDs.count
        )
    }

    private func runtimeStatusDetail(for job: JobRecord) -> String {
        if let error = job.error, error.isEmpty == false {
            return error
        }
        switch job.status {
        case .success:
            return "Job \(job.id) completed from \(job.triggerID)."
        case .queued:
            return "Job \(job.id) is queued from \(job.triggerID)."
        case .running:
            return "Job \(job.id) is running from \(job.triggerID)."
        case .failed:
            return "Job \(job.id) failed without a detailed error."
        case .cancelled:
            return "Job \(job.id) was cancelled."
        case .skipped:
            return "Job \(job.id) was skipped."
        }
    }

    private func notificationPreferencePluginGroups() throws -> [NotificationPreferencePluginGroup] {
        try bootstrapBundledPlugins()
        let store = try LocalStatusStore.openApplicationSupportStore()
        return try store.installedPlugins().flatMap { plugin in
            let definition = try store.installedPluginDefinition(pluginID: plugin.id)
            let events = (definition?.events ?? [])
                .sorted { lhs, rhs in lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending }
                .map { event in
                    NotificationPreferenceEventRow(
                        type: event.type,
                        label: event.label,
                        defaultMode: event.notificationDefault
                    )
                }
            let accounts = try store.accountConfigurations(pluginID: plugin.id)
            if accounts.isEmpty {
                return [
                    NotificationPreferencePluginGroup(id: plugin.id, pluginID: plugin.id, name: plugin.name, events: events)
                ]
            }
            return accounts.map { account in
                NotificationPreferencePluginGroup(
                    id: account.id,
                    pluginID: plugin.id,
                    accountID: account.id,
                    name: account.accountName,
                    events: events
                )
            }
        }
    }

    private func setNotificationPreference(pluginID: String, accountID: String?, eventType: String?, mode: NotificationMode?) throws {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let scope: NotificationPreferenceScope = if eventType != nil {
            .event
        } else if accountID != nil {
            .app
        } else {
            .plugin
        }
        if let mode {
            try store.upsertNotificationPreference(
                NotificationPreference(
                    id: notificationPreferenceID(pluginID: pluginID, accountID: accountID, eventType: eventType),
                    scope: scope,
                    pluginID: pluginID,
                    accountID: accountID,
                    eventType: eventType,
                    mode: mode,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            )
        } else {
            try store.deleteNotificationPreference(pluginID: pluginID, scope: scope, eventType: eventType, accountID: accountID)
        }
    }

    private func notificationPreferenceID(pluginID: String, accountID: String?, eventType: String?) -> String {
        let suffix = ([pluginID, accountID, eventType].compactMap { $0 }.joined(separator: "_"))
            .replacingOccurrences(of: #"[^a-zA-Z0-9_]+"#, with: "_", options: .regularExpression)
            .lowercased()
        return "ntp_\(suffix)"
    }

    private func applicationDatabasePath() -> String {
        (try? LocalStatusStore.applicationSupportDatabaseURL().path) ?? "Unavailable"
    }

    private func applicationPluginInstallPath() -> String {
        (try? pluginInstallRoot().path) ?? "Unavailable"
    }

    private func makeRegistryCheckAction() -> RuntimeAction {
        RuntimeAction(
            title: "Registry health check",
            detail: "Runs the installed Website plugin against \(registryHost) and stores the result locally.",
            buttonTitle: "Run check"
        ) {
            try await runRegistryCheck(pluginID: WebsitePluginSetup.pluginID)
        }
    }

    private func runRegistryCheck(pluginID: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
        let result = try await service.runInstalledPluginRequest(
            PluginRuntimeRequest(
                pluginID: pluginID,
                requestID: WebsitePluginSetup.requestID,
                accountID: "acct_status_registry",
                accountName: "Status registry",
                variables: ["host": registryHost]
            )
        )
        return "\(result.mappingOutput.resources.count) resource stored, \(result.mappingOutput.events.count) events processed."
    }

    @MainActor
    private func installLocalPluginFolder() async throws -> String {
        let panel = NSOpenPanel()
        panel.title = "Install Local Status Plugin"
        panel.message = "Choose a plugin folder containing manifest.json."
        panel.prompt = "Install"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let pluginDirectory = panel.url else {
            return "Local plugin install cancelled."
        }

        let store = try LocalStatusStore.openApplicationSupportStore()
        let installer = LocalPluginInstaller(store: store, installRoot: try pluginInstallRoot())
        let result = try installer.install(pluginDirectory: pluginDirectory)
        loadSidebarPlugins()
        return localPluginInstallMessage(from: result)
    }

    private func localPluginInstallMessage(from result: LocalPluginInstallResult) -> String {
        let warningSummary = result.warnings.isEmpty ? "" : " Unsigned local-dev plugin; review permissions before enabling automation."
        return "Installed \(result.plugin.name) \(result.version.version).\(warningSummary)"
    }

    @MainActor
    private func previewPluginFixture(plugin: InstalledPlugin, accountID: String?) async throws -> String {
        let panel = NSOpenPanel()
        panel.title = "Preview Plugin Fixture"
        panel.message = "Choose a JSON fixture payload to map without saving output."
        panel.prompt = "Preview"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let fixtureURL = panel.url else {
            return "Fixture preview cancelled."
        }

        let fixtureData = try Data(contentsOf: fixtureURL)
        let store = try LocalStatusStore.openApplicationSupportStore()
        let result = try PluginDeveloperPreviewer(store: store).previewFixture(
            pluginID: plugin.id,
            accountID: accountID,
            fixtureData: fixtureData
        )
        let warningSummary = result.warnings.isEmpty ? "" : " \(result.warnings.count) warning\(result.warnings.count == 1 ? "" : "s")."
        return "Previewed \(plugin.name) \(result.requestID): \(result.summary).\(warningSummary)"
    }

    private func runConfiguredPluginCheck(pluginID: String, accountID: String, accountName: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
        let job = try service.enqueueManualConfiguredPluginRun(
            pluginID: pluginID,
            accountID: accountID
        )
        let result = try await service.runQueuedPluginJob(jobID: job.id)
        return "\(accountName): \(result.mappingOutput.resources.count) resource stored, \(result.mappingOutput.events.count) events processed."
    }

    private func testConfiguredPluginRequest(pluginID: String, requestID: String, accountID: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
        return try await service.previewConfiguredPluginRequest(
            pluginID: pluginID,
            requestID: requestID,
            accountID: accountID
        ).summary
    }

    private func canRunConfiguredPlugin(pluginID: String) -> Bool {
        guard let store = try? LocalStatusStore.openApplicationSupportStore(),
              (try? store.accountConfigurations(pluginID: pluginID).isEmpty == false) == true else {
            return false
        }
        return ((try? store.triggers()) ?? []).contains { trigger in
            trigger.pluginID == pluginID && trigger.kind == .manual && trigger.enabled && trigger.requestID != nil
        }
    }

    private func configuredPluginValues(pluginID: String, accountID: String?) throws -> [String: String] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        if let accountID {
            return try PluginSetupConfiguration.configuredValues(pluginID: pluginID, accountID: accountID, store: store)
        }
        return try PluginSetupConfiguration.configuredValues(pluginID: pluginID, store: store)
    }

    private func savePluginSetup(plugin: InstalledPlugin, accountID: String?, displayName: String?, values: [String: String]) throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store)
        return try PluginSetupConfiguration.saveValues(
            values,
            for: plugin,
            service: service,
            credentialStore: KeychainCredentialStore(),
            accountID: accountID,
            displayNameOverride: displayName
        )
    }

    private func saveOAuthPluginSetup(
        plugin: InstalledPlugin,
        accountID: String?,
        displayName: String?,
        values: [String: String],
        request: PluginOAuthAuthorizationRequest,
        callbackURL: URL
    ) async throws -> String {
        guard let auth = plugin.auth else {
            throw PluginOAuthError.missingOAuthConfiguration(plugin.id)
        }
        let tokenSet = try await PluginOAuth.tokenSet(
            pluginID: plugin.id,
            auth: auth,
            request: request,
            callbackURL: callbackURL
        )
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store)
        return try PluginSetupConfiguration.saveOAuthTokenSet(
            tokenSet,
            setupValues: values,
            for: plugin,
            service: service,
            credentialStore: KeychainCredentialStore(),
            accountID: accountID,
            displayNameOverride: displayName
        )
    }

    private func dashboardTileFields(accountID: String) throws -> [String] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let value = try store.accountConfiguration(accountID: accountID)?
            .variables[PluginSetupConfiguration.dashboardTileFieldsKey] ?? ""
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func saveDashboardTileFields(pluginID: String, accountID: String, fields: [String]) throws {
        let store = try LocalStatusStore.openApplicationSupportStore()
        guard var configuration = try store.accountConfiguration(accountID: accountID) else {
            throw PluginRuntimeServiceError.accountNotConfigured(pluginID)
        }
        configuration.variables[PluginSetupConfiguration.dashboardTileFieldsKey] = fields.joined(separator: ",")
        try store.upsertAccountConfiguration(configuration, updatedAt: Date())
    }

    private func runBackgroundPluginLoop() async {
        try? bootstrapBundledPlugins()
        await applyRegistryRevocations()
        await runDueConfiguredPluginJobs()
        while Task.isCancelled == false {
            do {
                try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            } catch {
                return
            }
            await applyRegistryRevocations()
            await runDueConfiguredPluginJobs()
        }
    }

    private func applyRegistryRevocations() async {
        do {
            let revocations = try await PluginRegistryClient(baseURL: registryBaseURL).revocations()
            _ = try LocalStatusStore.openApplicationSupportStore().applyPluginRevocations(revocations)
        } catch {
            // Already-installed plugins continue against the last successfully fetched list.
        }
    }

    private func runDueConfiguredPluginJobs() async {
        do {
            let store = try LocalStatusStore.openApplicationSupportStore()
            let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
            _ = try await service.runDueConfiguredPluginJobs()
        } catch {
            // Background refresh errors are recorded on individual jobs where possible.
        }
    }

    private func pluginInstallRoot() throws -> URL {
        let databaseURL = try LocalStatusStore.applicationSupportDatabaseURL()
        let directory = databaseURL.deletingLastPathComponent().appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func bootstrapBundledPlugins() throws {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let installer = BundledPluginInstaller(store: store, installRoot: try pluginInstallRoot())
        try installer.installAll()
        try store.upsertSyncState(
            ownerType: "app",
            ownerID: "bundled-plugins",
            cursor: "installed",
            updatedAt: Date()
        )
    }

    private func reopenExpiredSnoozedItems() throws {
        _ = try LocalStatusStore.openApplicationSupportStore().reopenExpiredSnoozedItems(at: Date())
    }
}

private struct SidebarApp: Identifiable, Hashable {
    let pluginID: String
    let accountID: String?
    let name: String
    let iconPath: String?
    let iconAsset: PackagedPluginIconAsset?
    let accentColor: String?

    var id: String {
        "\(pluginID):\(accountID ?? "__setup__")"
    }
}

private struct MacPluginAppDetail: View {
    let pluginID: String
    let accountID: String?
    let openSettings: () -> Void
    let runPlugin: (String, String, String) async throws -> String

    @State private var plugin: InstalledPlugin?
    @State private var app: PluginAccountConfiguration?
    @State private var runtimeStatus: PluginRuntimeStatus?
    @State private var resources: [Resource] = []
    @State private var missingRunPermissions: [PluginPermission] = []
    @State private var loadError: String?
    @State private var runResult: String?
    @State private var runError: String?
    @State private var isRunning = false

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView("App unavailable", systemImage: "puzzlepiece.extension", description: Text(loadError))
            } else if let plugin {
                PluginAppDetailView(
                    plugin: plugin,
                    app: app,
                    runtimeStatus: runtimeStatus,
                    resources: resources,
                    runUnavailableReason: runUnavailableReason,
                    openSettings: openSettings,
                    run: runnableAction
                )
                .overlay(alignment: .bottom) {
                    statusOverlay
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(pluginID):\(accountID ?? "__setup__")") {
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .statusConfiguredAppsDidChange)) { _ in
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .statusAppDataDidChange)) { _ in
            load()
        }
        .refreshable {
            load()
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isRunning {
            ProgressView()
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
        } else if let runResult {
            Text(runResult)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
        } else if let runError {
            Text(runError)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
        }
    }

    private var runnableAction: (() -> Void)? {
        guard let accountID, let app else {
            return nil
        }
        guard missingRunPermissions.isEmpty else {
            return nil
        }
        return {
            Task {
                await run(accountID: accountID, accountName: app.accountName)
            }
        }
    }

    private var runUnavailableReason: String? {
        guard missingRunPermissions.isEmpty == false else {
            return nil
        }
        return "Grant \(permissionList(missingRunPermissions)) permission in App Settings before refreshing this app."
    }

    private func load() {
        do {
            let store = try LocalStatusStore.openApplicationSupportStore()
            let loadedPlugin = try store.installedPlugin(id: pluginID)
            let loadedApp = try accountID.flatMap { try store.accountConfiguration(accountID: $0) }
            plugin = loadedPlugin
            app = loadedApp
            resources = try store.resources(pluginID: pluginID, accountID: accountID)
            runtimeStatus = try recentRuntimeStatus(store: store, pluginID: pluginID, accountID: accountID)
            missingRunPermissions = try missingRuntimePermissions(store: store, plugin: loadedPlugin, app: loadedApp)
            if loadedPlugin == nil {
                loadError = "This plugin is not installed on this device."
            } else if accountID != nil, loadedApp == nil {
                loadError = "This app is no longer configured on this device."
            } else {
                loadError = nil
            }
        } catch {
            plugin = nil
            app = nil
            resources = []
            runtimeStatus = nil
            missingRunPermissions = []
            loadError = error.localizedDescription
        }
    }

    private func run(accountID: String, accountName: String) async {
        isRunning = true
        runResult = nil
        runError = nil
        do {
            runResult = try await runPlugin(pluginID, accountID, accountName)
            load()
        } catch {
            runError = error.localizedDescription
        }
        isRunning = false
    }

    private func recentRuntimeStatus(store: StatusPersistenceStore, pluginID: String, accountID: String?) throws -> PluginRuntimeStatus? {
        guard let job = try store.recentJobs(pluginID: pluginID, accountID: accountID, limit: 1).first else {
            return nil
        }
        return PluginRuntimeStatus(
            pluginID: job.pluginID,
            status: job.status,
            detail: runtimeStatusDetail(for: job),
            timestamp: job.finishedAt ?? job.startedAt ?? job.queuedAt,
            emittedEventCount: job.emittedEventIDs.count
        )
    }

    private func runtimeStatusDetail(for job: JobRecord) -> String {
        if let error = job.error, error.isEmpty == false {
            return error
        }
        switch job.status {
        case .queued:
            return "Job \(job.id) is waiting to run from \(job.triggerID)."
        case .running:
            return "Job \(job.id) is running from \(job.triggerID)."
        case .success:
            return "Job \(job.id) completed from \(job.triggerID)."
        case .failed:
            return "Job \(job.id) failed from \(job.triggerID)."
        case .cancelled:
            return "Job \(job.id) was cancelled from \(job.triggerID)."
        case .skipped:
            return "Job \(job.id) was skipped from \(job.triggerID)."
        }
    }

    private func missingRuntimePermissions(
        store: StatusPersistenceStore,
        plugin: InstalledPlugin?,
        app: PluginAccountConfiguration?
    ) throws -> [PluginPermission] {
        guard let plugin else {
            return []
        }
        let permissionRows = try store.pluginPermissions(pluginID: plugin.id)
        let declared = Set(permissionRows.map(\.permission))
        let granted = Set(permissionRows.filter(\.granted).map(\.permission))
        var required: [PluginPermission] = []
        if declared.contains(.network) {
            required.append(.network)
        }
        if declared.contains(.userConfiguredDomains) {
            required.append(.userConfiguredDomains)
        }
        if app?.credentialRef != nil, declared.contains(.keychain) {
            required.append(.keychain)
        }
        if let app,
           app.credentialRef != nil,
           declared.contains(.privateKey),
           app.authType == AuthKind.jwtAPIKey.rawValue || app.authType == AuthKind.privateKeyJWT.rawValue {
            required.append(.privateKey)
        }
        return required.filter { granted.contains($0) == false }
    }

    private func permissionList(_ permissions: [PluginPermission]) -> String {
        permissions.map(permissionLabel).joined(separator: ", ")
    }

    private func permissionLabel(_ permission: PluginPermission) -> String {
        switch permission {
        case .network:
            return "Network"
        case .keychain:
            return "Keychain"
        case .oauth:
            return "OAuth"
        case .apiKey:
            return "API key"
        case .privateKey:
            return "Private key"
        case .backgroundRefresh:
            return "Background refresh"
        case .pushWebhook:
            return "Push webhook"
        case .userConfiguredDomains:
            return "User-configured domains"
        case .writeActions:
            return "Write actions"
        case .localNotificationSuggestion:
            return "Notification suggestions"
        }
    }
}

private enum MacSection: Hashable {
    case overview
    case alerts
    case integrations
    case app(pluginID: String, accountID: String?)
    case rules
    case audit
    case settings
}

private struct MacActionEffectDispatcher: ActionEffectDispatcher {
    func dispatch(_ effects: ActionRuntimeEffects) async throws {
        for notification in effects.notifications {
            deliver(notification)
        }
        for url in effects.openedURLs {
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
        for webhook in effects.webhooks {
            try await post(webhook)
        }
    }

    private func post(_ webhook: ActionRuntimeWebhook) async throws {
        do {
            let request = try ActionWebhookRequestBuilder().request(for: webhook)
            _ = try await URLSessionPluginRequestTransport().response(for: request)
        } catch {
            if let actionRunID = webhook.actionRunID {
                throw ActionEffectDispatchFailure(actionRunID: actionRunID, message: error.localizedDescription)
            }
            throw error
        }
    }

    private func deliver(_ notification: ActionRuntimeNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "status-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}
