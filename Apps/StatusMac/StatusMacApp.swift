import AppKit
import StatusCore
import StatusUI
import SwiftUI
@preconcurrency import UserNotifications

@main
struct StatusMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacRootView()
        }
        .windowStyle(.titleBar)
    }
}

private struct MacRootView: View {
    @State private var selection: MacSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: MacSection.overview) {
                    Label("Overview", systemImage: "rectangle.grid.2x2")
                }
                NavigationLink(value: MacSection.integrations) {
                    Label("Integrations", systemImage: "puzzlepiece.extension")
                }
                NavigationLink(value: MacSection.rules) {
                    Label("Rules", systemImage: "slider.horizontal.3")
                }
                NavigationLink(value: MacSection.audit) {
                    Label("Audit Log", systemImage: "list.bullet.rectangle")
                }
                NavigationLink(value: MacSection.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("Status")
        } detail: {
            switch selection ?? .overview {
            case .overview:
                DashboardContainerView(viewModel: makeDashboardViewModel())
                    .navigationTitle("Overview")
            case .integrations:
                PluginStoreContainerView(viewModel: makePluginStoreViewModel(platform: .macOS))
                    .navigationTitle("Integrations")
            case .rules:
                RulesContainerView(viewModel: makeRulesViewModel())
                    .navigationTitle("Rules")
            case .audit:
                AuditLogContainerView(viewModel: makeAuditLogViewModel())
                    .navigationTitle("Audit Log")
            case .settings:
                StatusSettingsView(
                    registryURL: registryBaseURL,
                    databasePath: applicationDatabasePath(),
                    pluginInstallPath: applicationPluginInstallPath(),
                    runtimeAction: makeRegistryCheckAction()
                )
                    .navigationTitle("Settings")
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
        } canRunPlugin: { plugin in
            canRunConfiguredPlugin(pluginID: plugin.id)
        } runPlugin: { plugin in
            try await runConfiguredPluginCheck(pluginID: plugin.id)
        } canConfigurePlugin: { plugin in
            plugin.auth?.fields.isEmpty == false || plugin.setup?.fields.contains(where: \.type.isPlainConfigurationField) == true
        } loadConfigurationValues: { plugin in
            try configuredPluginValues(pluginID: plugin.id)
        } saveConfigurationValues: { plugin, values in
            try savePluginSetup(plugin: plugin, values: values)
        }
    }

    private var registryBaseURL: URL {
        URL(string: "https://status-registry.hakobs.com")!
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
        let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
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

    private func runConfiguredPluginCheck(pluginID: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let configuration = try PluginSetupConfiguration.configuredAccount(pluginID: pluginID, store: store)
        let service = PluginRuntimeService(store: store, effectDispatcher: MacActionEffectDispatcher())
        let job = try service.enqueueManualConfiguredPluginRun(
            pluginID: pluginID,
            accountID: configuration.id
        )
        let result = try await service.runQueuedPluginJob(jobID: job.id)
        return "\(configuration.accountName): \(result.mappingOutput.resources.count) resource stored, \(result.mappingOutput.events.count) events processed."
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

    private func configuredPluginValues(pluginID: String) throws -> [String: String] {
        let store = try LocalStatusStore.openApplicationSupportStore()
        return try PluginSetupConfiguration.configuredValues(pluginID: pluginID, store: store)
    }

    private func savePluginSetup(plugin: InstalledPlugin, values: [String: String]) throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store)
        return try PluginSetupConfiguration.saveValues(
            values,
            for: plugin,
            service: service,
            credentialStore: KeychainCredentialStore()
        )
    }

    private func runBackgroundPluginLoop() async {
        try? bootstrapBundledPlugins()
        await runDueConfiguredPluginJobs()
        while Task.isCancelled == false {
            do {
                try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            } catch {
                return
            }
            await runDueConfiguredPluginJobs()
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
    }
}

private enum MacSection: Hashable {
    case overview
    case integrations
    case rules
    case audit
    case settings
}

private struct MacActionEffectDispatcher: ActionEffectDispatcher {
    func dispatch(_ effects: ActionRuntimeEffects) throws {
        for notification in effects.notifications {
            deliver(notification)
        }
        for url in effects.openedURLs {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
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
