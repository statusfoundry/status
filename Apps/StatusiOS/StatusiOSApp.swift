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
                AlertsView(items: loadOpenAlerts())
                    .navigationTitle("Alerts")
            }
            .tabItem {
                Label("Alerts", systemImage: "bell")
            }

            NavigationStack {
                PluginStoreContainerView(viewModel: makePluginStoreViewModel(platform: .iOS))
                    .navigationTitle("Integrations")
            }
            .tabItem {
                Label("Integrations", systemImage: "puzzlepiece.extension")
            }

            NavigationStack {
                RulesContainerView(viewModel: makeRulesViewModel())
                    .navigationTitle("Rules")
            }
            .tabItem {
                Label("Rules", systemImage: "slider.horizontal.3")
            }

            NavigationStack {
                StatusSettingsView(
                    registryURL: registryBaseURL,
                    databasePath: applicationDatabasePath(),
                    pluginInstallPath: applicationPluginInstallPath(),
                    runtimeAction: makeRegistryCheckAction()
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
            try LocalStatusStore.openApplicationSupportStore().dashboardSnapshot()
        }
    }

    private func makePluginStoreViewModel(platform: PluginPlatform) -> PluginStoreViewModel {
        let registry = PluginRegistryClient(baseURL: registryBaseURL)
        return PluginStoreViewModel {
            try LocalStatusStore.openApplicationSupportStore().installedPlugins()
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
            plugin.id == WebsitePluginSetup.pluginID
        } runPlugin: { plugin in
            try await runConfiguredWebsiteCheck(pluginID: plugin.id)
        } canConfigurePlugin: { plugin in
            plugin.id == WebsitePluginSetup.pluginID
        } loadConfigurationValue: { plugin in
            try configuredWebsiteHost(pluginID: plugin.id)
        } saveConfigurationValue: { plugin, value in
            try saveWebsiteHost(pluginID: plugin.id, value: value)
        }
    }

    private var registryBaseURL: URL {
        URL(string: "https://status-registry.hakobs.com")!
    }

    private func loadOpenAlerts() -> [StatusItem] {
        ((try? LocalStatusStore.openApplicationSupportStore().statusItems(limit: 50)) ?? [])
            .filter { $0.severity >= .warning }
    }

    private func makeRulesViewModel() -> RulesViewModel {
        RulesViewModel {
            try LocalStatusStore.openApplicationSupportStore().rules()
        } saveRule: { rule in
            try LocalStatusStore.openApplicationSupportStore().upsertRule(rule, updatedAt: Date())
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

    private func runConfiguredWebsiteCheck(pluginID: String) async throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let configuration = try WebsitePluginSetup.configuredAccount(pluginID: pluginID, store: store)
        let service = PluginRuntimeService(store: store, effectDispatcher: IOSActionEffectDispatcher())
        let job = try service.enqueueManualConfiguredPluginRun(
            pluginID: pluginID,
            accountID: configuration.id
        )
        let result = try await service.runQueuedPluginJob(jobID: job.id)
        return "\(configuration.variables["host", default: configuration.accountName]): \(result.mappingOutput.resources.count) resource stored, \(result.mappingOutput.events.count) events processed."
    }

    private func configuredWebsiteHost(pluginID: String) throws -> String? {
        let store = try LocalStatusStore.openApplicationSupportStore()
        return try WebsitePluginSetup.configuredHost(pluginID: pluginID, store: store)
    }

    private func saveWebsiteHost(pluginID: String, value: String) throws -> String {
        let store = try LocalStatusStore.openApplicationSupportStore()
        let service = PluginRuntimeService(store: store)
        return try WebsitePluginSetup.saveHost(value, pluginID: pluginID, service: service)
    }

    private func runBackgroundPluginLoop() async {
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
}

private struct IOSActionEffectDispatcher: ActionEffectDispatcher {
    func dispatch(_ effects: ActionRuntimeEffects) throws {
        for notification in effects.notifications {
            deliver(notification)
        }
        for url in effects.openedURLs {
            Task { @MainActor in
                UIApplication.shared.open(url)
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
