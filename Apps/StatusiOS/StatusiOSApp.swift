import StatusCore
import StatusUI
import SwiftUI
import UIKit
@preconcurrency import UserNotifications

@main
struct StatusiOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSRootView()
        }
    }
}

private struct IOSRootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardContainerView(viewModel: makeDashboardViewModel())
                    .navigationTitle("Overview")
            }
            .tabItem {
                Label("Overview", systemImage: "rectangle.grid.2x2")
            }

            NavigationStack {
                AlertsContainerView(viewModel: makeAlertsViewModel())
                    .navigationTitle("Alerts")
            }
            .tabItem {
                Label("Alerts", systemImage: "bell")
            }

            NavigationStack {
                PluginStoreContainerView(viewModel: makePluginStoreViewModel(platform: .iOS))
                    .navigationTitle("Apps")
            }
            .tabItem {
                Label("Apps", systemImage: "puzzlepiece.extension")
            }

            NavigationStack {
                RulesContainerView(viewModel: makeRulesViewModel())
                    .navigationTitle("Rules")
            }
            .tabItem {
                Label("Rules", systemImage: "slider.horizontal.3")
            }

            NavigationStack {
                AuditLogContainerView(viewModel: makeAuditLogViewModel())
                    .navigationTitle("Audit Log")
            }
            .tabItem {
                Label("Audit", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                StatusSettingsView(
                    registryURL: registryBaseURL,
                    databasePath: applicationDatabasePath(),
                    pluginInstallPath: applicationPluginInstallPath(),
                    runtimeAction: makeRegistryCheckAction(),
                    notificationPreferencesViewModel: makeNotificationPreferencesViewModel(),
                    notificationHistoryViewModel: makeNotificationHistoryViewModel()
                )
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .task {
            await runBackgroundPluginLoop()
        }
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
        } loadRuntimeStatuses: { plugins in
            try pluginRuntimeStatuses(for: plugins)
        } loadPluginResources: { plugin in
            try LocalStatusStore.openApplicationSupportStore().resources(pluginID: plugin.id)
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
            plugin.auth?.fields.isEmpty == false || plugin.setup?.fields.contains(where: \.type.isPlainConfigurationField) == true
        } loadAccounts: { plugin in
            try LocalStatusStore.openApplicationSupportStore().accountConfigurations(pluginID: plugin.id)
        } loadConfigurationValues: { plugin, accountID in
            try configuredPluginValues(pluginID: plugin.id, accountID: accountID)
        } saveConfigurationValues: { plugin, accountID, displayName, values in
            try savePluginSetup(plugin: plugin, accountID: accountID, displayName: displayName, values: values)
        }
    }

    private var registryBaseURL: URL {
        URL(string: "https://status-registry.hakobs.com")!
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
            return try LocalStatusStore.openApplicationSupportStore().rules()
        } saveRule: { rule in
            try LocalStatusStore.openApplicationSupportStore().upsertRule(rule, updatedAt: Date())
        }
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

    private func pluginRuntimeStatuses(for plugins: [InstalledPlugin]) throws -> [String: PluginRuntimeStatus] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        return try Dictionary(uniqueKeysWithValues: plugins.compactMap { plugin in
            guard let job = try store.recentJobs(pluginID: plugin.id, limit: 1).first else {
                return nil
            }
            return (plugin.id, runtimeStatus(from: job))
        })
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
            detail: "Runs the installed Website plugin against status-registry.hakobs.com and stores the result locally.",
            buttonTitle: "Run check"
        ) {
            try await runRegistryCheck(pluginID: WebsitePluginSetup.pluginID)
        }
    }

    private func runRegistryCheck(pluginID: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store, effectDispatcher: IOSActionEffectDispatcher())
        let result = try await service.runInstalledPluginRequest(
            PluginRuntimeRequest(
                pluginID: pluginID,
                requestID: WebsitePluginSetup.requestID,
                accountID: "acct_status_registry",
                accountName: "Status registry",
                variables: ["host": "status-registry.hakobs.com"]
            )
        )
        return "\(result.mappingOutput.resources.count) resource stored, \(result.mappingOutput.events.count) events processed."
    }

    private func runConfiguredPluginCheck(pluginID: String, accountID: String, accountName: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store, effectDispatcher: IOSActionEffectDispatcher())
        let job = try service.enqueueManualConfiguredPluginRun(
            pluginID: pluginID,
            accountID: accountID
        )
        let result = try await service.runQueuedPluginJob(jobID: job.id)
        return "\(accountName): \(result.mappingOutput.resources.count) resource stored, \(result.mappingOutput.events.count) events processed."
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
            let service = PluginRuntimeService(store: store, effectDispatcher: IOSActionEffectDispatcher())
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
        guard try store.syncState(ownerType: "app", ownerID: "bundled-plugins") != "installed" else {
            return
        }
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

private struct IOSActionEffectDispatcher: ActionEffectDispatcher {
    func dispatch(_ effects: ActionRuntimeEffects) async throws {
        for notification in effects.notifications {
            deliver(notification)
        }
        for url in effects.openedURLs {
            await MainActor.run {
                UIApplication.shared.open(url)
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
