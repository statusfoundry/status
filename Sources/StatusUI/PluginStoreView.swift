import StatusCore
import SwiftUI

public struct PluginStoreCatalog: Equatable, Sendable {
    public var installed: [InstalledPlugin]
    public var available: [RegistryPluginSummary]

    public init(installed: [InstalledPlugin] = [], available: [RegistryPluginSummary] = []) {
        self.installed = installed
        self.available = available
    }
}

public struct PluginRuntimeStatus: Equatable, Sendable {
    public var pluginID: String
    public var status: JobStatus
    public var detail: String
    public var timestamp: Date
    public var emittedEventCount: Int

    public init(pluginID: String, status: JobStatus, detail: String, timestamp: Date, emittedEventCount: Int = 0) {
        self.pluginID = pluginID
        self.status = status
        self.detail = detail
        self.timestamp = timestamp
        self.emittedEventCount = emittedEventCount
    }
}

@MainActor
public final class PluginStoreViewModel: ObservableObject {
    @Published public private(set) var catalog: PluginStoreCatalog
    @Published public private(set) var loadError: String?
    @Published public private(set) var installingPluginID: String?
    @Published public private(set) var removingPluginID: String?
    @Published public private(set) var runningPluginID: String?
    @Published public private(set) var runResults: [String: String]
    @Published public private(set) var runErrors: [String: String]
    @Published public private(set) var setupValues: [String: [String: String]]
    @Published public private(set) var accountDisplayNames: [String: String]
    @Published public private(set) var configuredAccounts: [String: [PluginAccountConfiguration]]
    @Published public private(set) var selectedAccountIDs: [String: String]
    @Published public private(set) var savingSetupPluginID: String?
    @Published public private(set) var setupResults: [String: String]
    @Published public private(set) var setupErrors: [String: String]
    @Published public private(set) var installedPermissions: [String: [InstalledPluginPermission]]
    @Published public private(set) var savingPermissionID: String?
    @Published public private(set) var installedTriggers: [String: [TriggerDefinition]]
    @Published public private(set) var savingTriggerID: String?
    @Published public private(set) var runtimeStatuses: [String: PluginRuntimeStatus]
    @Published public private(set) var pluginResources: [String: [Resource]]

    private let loadInstalled: () throws -> [InstalledPlugin]
    private let loadAvailable: () async throws -> [RegistryPluginSummary]
    private let loadRuntimeStatuses: ([InstalledPlugin]) throws -> [String: PluginRuntimeStatus]
    private let loadPluginResources: (InstalledPlugin) throws -> [Resource]
    private let installPlugin: (RegistryPluginSummary) async throws -> Void
    private let removePlugin: (InstalledPlugin) async throws -> Void
    private let loadPermissions: (InstalledPlugin) throws -> [InstalledPluginPermission]
    private let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) async throws -> Void
    private let loadTriggers: (InstalledPlugin) throws -> [TriggerDefinition]
    private let setTriggerEnabled: (InstalledPlugin, TriggerDefinition, Bool) async throws -> Void
    private let canRunPlugin: (InstalledPlugin) -> Bool
    private let runPlugin: (InstalledPlugin, PluginAccountConfiguration) async throws -> String
    private let canConfigurePlugin: (InstalledPlugin) -> Bool
    private let loadAccounts: (InstalledPlugin) throws -> [PluginAccountConfiguration]
    private let loadConfigurationValues: (InstalledPlugin, String?) throws -> [String: String]
    private let saveConfigurationValues: (InstalledPlugin, String?, String?, [String: String]) async throws -> String

    public init(
        initialCatalog: PluginStoreCatalog = PluginStoreCatalog(),
        loadInstalled: @escaping () throws -> [InstalledPlugin],
        loadAvailable: @escaping () async throws -> [RegistryPluginSummary],
        loadRuntimeStatuses: @escaping ([InstalledPlugin]) throws -> [String: PluginRuntimeStatus] = { _ in [:] },
        loadPluginResources: @escaping (InstalledPlugin) throws -> [Resource] = { _ in [] },
        installPlugin: @escaping (RegistryPluginSummary) async throws -> Void,
        removePlugin: @escaping (InstalledPlugin) async throws -> Void = { _ in },
        loadPermissions: @escaping (InstalledPlugin) throws -> [InstalledPluginPermission] = { _ in [] },
        setPermissionGrant: @escaping (InstalledPlugin, PluginPermission, Bool) async throws -> Void = { _, _, _ in },
        loadTriggers: @escaping (InstalledPlugin) throws -> [TriggerDefinition] = { _ in [] },
        setTriggerEnabled: @escaping (InstalledPlugin, TriggerDefinition, Bool) async throws -> Void = { _, _, _ in },
        canRunPlugin: @escaping (InstalledPlugin) -> Bool = { _ in false },
        runPlugin: @escaping (InstalledPlugin, PluginAccountConfiguration) async throws -> String = { _, _ in "" },
        canConfigurePlugin: @escaping (InstalledPlugin) -> Bool = { _ in false },
        loadAccounts: @escaping (InstalledPlugin) throws -> [PluginAccountConfiguration] = { _ in [] },
        loadConfigurationValues: @escaping (InstalledPlugin, String?) throws -> [String: String] = { _, _ in [:] },
        saveConfigurationValues: @escaping (InstalledPlugin, String?, String?, [String: String]) async throws -> String = { _, _, _, _ in "" }
    ) {
        self.catalog = initialCatalog
        self.runResults = [:]
        self.runErrors = [:]
        self.setupValues = [:]
        self.accountDisplayNames = [:]
        self.configuredAccounts = [:]
        self.selectedAccountIDs = [:]
        self.setupResults = [:]
        self.setupErrors = [:]
        self.installedPermissions = [:]
        self.installedTriggers = [:]
        self.runtimeStatuses = [:]
        self.pluginResources = [:]
        self.loadInstalled = loadInstalled
        self.loadAvailable = loadAvailable
        self.loadRuntimeStatuses = loadRuntimeStatuses
        self.loadPluginResources = loadPluginResources
        self.installPlugin = installPlugin
        self.removePlugin = removePlugin
        self.loadPermissions = loadPermissions
        self.setPermissionGrant = setPermissionGrant
        self.loadTriggers = loadTriggers
        self.setTriggerEnabled = setTriggerEnabled
        self.canRunPlugin = canRunPlugin
        self.runPlugin = runPlugin
        self.canConfigurePlugin = canConfigurePlugin
        self.loadAccounts = loadAccounts
        self.loadConfigurationValues = loadConfigurationValues
        self.saveConfigurationValues = saveConfigurationValues
    }

    public func reload() async {
        do {
            let installed = try loadInstalled()
            let available = try await loadAvailable()
            catalog = PluginStoreCatalog(installed: installed, available: available)
            refreshAccounts(for: installed)
            refreshSetupValues(for: installed)
            refreshPermissions(for: installed)
            refreshTriggers(for: installed)
            refreshRuntimeStatuses(for: installed)
            refreshPluginResources(for: installed)
            loadError = nil
        } catch {
            let installed = (try? loadInstalled()) ?? []
            catalog = PluginStoreCatalog(installed: installed, available: [])
            refreshAccounts(for: installed)
            refreshSetupValues(for: installed)
            refreshPermissions(for: installed)
            refreshTriggers(for: installed)
            refreshRuntimeStatuses(for: installed)
            refreshPluginResources(for: installed)
            loadError = error.localizedDescription
        }
    }

    public func install(_ plugin: RegistryPluginSummary) async {
        guard installingPluginID == nil else { return }
        guard plugin.latestVersion != nil else {
            loadError = "Plugin has no installable version."
            return
        }

        installingPluginID = plugin.id
        defer { installingPluginID = nil }

        do {
            try await installPlugin(plugin)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func remove(_ plugin: InstalledPlugin) async {
        guard removingPluginID == nil else { return }
        removingPluginID = plugin.id
        runResults[plugin.id] = nil
        runErrors[plugin.id] = nil
        setupResults[plugin.id] = nil
        setupErrors[plugin.id] = nil
        defer { removingPluginID = nil }

        do {
            try await removePlugin(plugin)
            setupValues[plugin.id] = nil
            accountDisplayNames = accountDisplayNames.filter { key, _ in key.hasPrefix("\(plugin.id):") == false }
            configuredAccounts[plugin.id] = nil
            selectedAccountIDs[plugin.id] = nil
            installedPermissions[plugin.id] = nil
            installedTriggers[plugin.id] = nil
            runtimeStatuses[plugin.id] = nil
            pluginResources[plugin.id] = nil
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func setPermission(_ permission: PluginPermission, granted: Bool, for plugin: InstalledPlugin) async {
        guard savingPermissionID == nil else { return }
        savingPermissionID = permissionChangeID(plugin: plugin, permission: permission)
        defer { savingPermissionID = nil }

        do {
            try await setPermissionGrant(plugin, permission, granted)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func setTrigger(_ trigger: TriggerDefinition, enabled: Bool, for plugin: InstalledPlugin) async {
        guard savingTriggerID == nil else { return }
        savingTriggerID = trigger.id
        defer { savingTriggerID = nil }

        do {
            try await setTriggerEnabled(plugin, trigger, enabled)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func canRun(_ plugin: InstalledPlugin) -> Bool {
        canRunPlugin(plugin)
    }

    public func canConfigure(_ plugin: InstalledPlugin) -> Bool {
        canConfigurePlugin(plugin)
    }

    public func updateSetupValue(_ plugin: InstalledPlugin, fieldID: String, value: String) {
        let key = setupKey(for: plugin)
        var values = setupValues[key, default: defaultSetupValues(for: plugin)]
        values[fieldID] = value
        setupValues[key] = values
        setupResults[key] = nil
        setupErrors[key] = nil
    }

    public func updateAccountDisplayName(_ plugin: InstalledPlugin, value: String) {
        let key = setupKey(for: plugin)
        accountDisplayNames[key] = value
        setupResults[key] = nil
        setupErrors[key] = nil
    }

    public func selectAccount(_ accountID: String, for plugin: InstalledPlugin) {
        selectedAccountIDs[plugin.id] = accountID
        let key = setupKey(pluginID: plugin.id, accountID: accountID)
        let values = (try? loadConfigurationValues(plugin, persistedAccountID(from: accountID))) ?? [:]
        setupValues[key] = defaultSetupValues(for: plugin).merging(values) { _, loaded in loaded }
        accountDisplayNames[key] = configuredAccounts[plugin.id, default: []].first { $0.id == accountID }?.accountName ?? ""
        setupResults[key] = nil
        setupErrors[key] = nil
        runResults[key] = nil
        runErrors[key] = nil
    }

    public func addAccount(for plugin: InstalledPlugin) {
        let accountID = newAccountID(for: plugin)
        selectedAccountIDs[plugin.id] = accountID
        setupValues[setupKey(pluginID: plugin.id, accountID: accountID)] = defaultSetupValues(for: plugin)
        accountDisplayNames[setupKey(pluginID: plugin.id, accountID: accountID)] = ""
    }

    public func saveSetup(_ plugin: InstalledPlugin) async {
        guard savingSetupPluginID == nil else { return }
        let selectedAccountID = selectedAccountIDs[plugin.id]
        let key = setupKey(pluginID: plugin.id, accountID: selectedAccountID)
        let values = setupValues[key, default: defaultSetupValues(for: plugin)]
        let accountName = accountDisplayNames[key]
        savingSetupPluginID = plugin.id
        setupResults[key] = nil
        setupErrors[key] = nil
        defer { savingSetupPluginID = nil }

        do {
            setupResults[key] = try await saveConfigurationValues(plugin, persistedAccountID(from: selectedAccountID), accountName, values)
            await reload()
        } catch {
            setupErrors[key] = error.localizedDescription
        }
    }

    public func run(_ plugin: InstalledPlugin) async {
        guard runningPluginID == nil else { return }
        guard let account = selectedAccount(for: plugin) else {
            runErrors[setupKey(for: plugin)] = "Save an account before running this plugin."
            return
        }
        let key = setupKey(pluginID: plugin.id, accountID: account.id)
        runningPluginID = plugin.id
        runResults[key] = nil
        runErrors[key] = nil
        defer { runningPluginID = nil }

        do {
            runResults[key] = try await runPlugin(plugin, account)
            await reload()
        } catch {
            runErrors[key] = error.localizedDescription
        }
    }

    private func refreshAccounts(for plugins: [InstalledPlugin]) {
        configuredAccounts = Dictionary(uniqueKeysWithValues: plugins.map { plugin in
            let accounts = (try? loadAccounts(plugin)) ?? []
            return (plugin.id, accounts)
        })
        for plugin in plugins {
            let accounts = configuredAccounts[plugin.id, default: []]
            let currentSelection = selectedAccountIDs[plugin.id]
            if let currentSelection, currentSelection.hasPrefix(Self.newAccountPrefix) {
                continue
            }
            if let currentSelection, accounts.contains(where: { $0.id == currentSelection }) {
                continue
            }
            selectedAccountIDs[plugin.id] = accounts.first?.id ?? newAccountID(for: plugin)
            let selectedID = selectedAccountIDs[plugin.id]
            let key = setupKey(pluginID: plugin.id, accountID: selectedID)
            if accountDisplayNames[key] == nil {
                accountDisplayNames[key] = accounts.first { $0.id == selectedID }?.accountName ?? ""
            }
        }
    }

    private func refreshSetupValues(for plugins: [InstalledPlugin]) {
        for plugin in plugins where canConfigurePlugin(plugin) {
            let accountID = selectedAccountIDs[plugin.id]
            let loaded = (try? loadConfigurationValues(plugin, persistedAccountID(from: accountID))) ?? [:]
            setupValues[setupKey(pluginID: plugin.id, accountID: accountID)] = defaultSetupValues(for: plugin).merging(loaded) { _, loaded in loaded }
        }
    }

    private func refreshPermissions(for plugins: [InstalledPlugin]) {
        installedPermissions = Dictionary(uniqueKeysWithValues: plugins.map { plugin in
            (plugin.id, (try? loadPermissions(plugin)) ?? [])
        })
    }

    private func refreshTriggers(for plugins: [InstalledPlugin]) {
        installedTriggers = Dictionary(uniqueKeysWithValues: plugins.map { plugin in
            (plugin.id, (try? loadTriggers(plugin)) ?? [])
        })
    }

    private func refreshRuntimeStatuses(for plugins: [InstalledPlugin]) {
        runtimeStatuses = (try? loadRuntimeStatuses(plugins)) ?? [:]
    }

    private func refreshPluginResources(for plugins: [InstalledPlugin]) {
        pluginResources = Dictionary(uniqueKeysWithValues: plugins.map { plugin in
            (plugin.id, (try? loadPluginResources(plugin)) ?? [])
        })
    }

    private func defaultSetupValues(for plugin: InstalledPlugin) -> [String: String] {
        Dictionary(uniqueKeysWithValues: plugin.configurationFields.map { field in
            (field.id, field.defaultValue ?? "")
        })
    }

    private func permissionChangeID(plugin: InstalledPlugin, permission: PluginPermission) -> String {
        "\(plugin.id):\(permission.rawValue)"
    }

    private func selectedAccount(for plugin: InstalledPlugin) -> PluginAccountConfiguration? {
        guard let accountID = selectedAccountIDs[plugin.id],
              accountID.hasPrefix(Self.newAccountPrefix) == false else {
            return nil
        }
        return configuredAccounts[plugin.id, default: []].first { $0.id == accountID }
    }

    private func setupKey(for plugin: InstalledPlugin) -> String {
        setupKey(pluginID: plugin.id, accountID: selectedAccountIDs[plugin.id])
    }

    private func setupKey(pluginID: String, accountID: String?) -> String {
        "\(pluginID):\(accountID ?? Self.newAccountPrefix)"
    }

    private func persistedAccountID(from accountID: String?) -> String? {
        guard let accountID, accountID.hasPrefix(Self.newAccountPrefix) == false else {
            return nil
        }
        return accountID
    }

    private func newAccountID(for plugin: InstalledPlugin) -> String {
        "\(Self.newAccountPrefix)\(plugin.id)"
    }

    private static let newAccountPrefix = "__new__:"
}

public struct PluginStoreContainerView: View {
    @StateObject private var viewModel: PluginStoreViewModel
    private let openSettings: ((InstalledPlugin) -> Void)?

    public init(
        viewModel: @autoclosure @escaping () -> PluginStoreViewModel,
        openSettings: ((InstalledPlugin) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.openSettings = openSettings
    }

    public var body: some View {
        PluginStoreView(
            catalog: viewModel.catalog,
            installingPluginID: viewModel.installingPluginID,
            removingPluginID: viewModel.removingPluginID,
            runningPluginID: viewModel.runningPluginID,
            runResults: viewModel.runResults,
            runErrors: viewModel.runErrors,
            setupValues: viewModel.setupValues,
            accountDisplayNames: viewModel.accountDisplayNames,
            configuredAccounts: viewModel.configuredAccounts,
            selectedAccountIDs: viewModel.selectedAccountIDs,
            savingSetupPluginID: viewModel.savingSetupPluginID,
            setupResults: viewModel.setupResults,
            setupErrors: viewModel.setupErrors,
            installedPermissions: viewModel.installedPermissions,
            savingPermissionID: viewModel.savingPermissionID,
            installedTriggers: viewModel.installedTriggers,
            savingTriggerID: viewModel.savingTriggerID,
            runtimeStatuses: viewModel.runtimeStatuses,
            pluginResources: viewModel.pluginResources,
            canConfigure: { plugin in
                viewModel.canConfigure(plugin)
            },
            updateSetupValue: { plugin, fieldID, value in
                viewModel.updateSetupValue(plugin, fieldID: fieldID, value: value)
            },
            updateAccountDisplayName: { plugin, value in
                viewModel.updateAccountDisplayName(plugin, value: value)
            },
            selectAccount: { plugin, accountID in
                viewModel.selectAccount(accountID, for: plugin)
            },
            addAccount: { plugin in
                viewModel.addAccount(for: plugin)
            },
            saveSetup: { plugin in
                Task {
                    await viewModel.saveSetup(plugin)
                }
            },
            canRun: { plugin in
                viewModel.canRun(plugin)
            },
            run: { plugin in
                Task {
                    await viewModel.run(plugin)
                }
            },
            install: { plugin in
                Task {
                    await viewModel.install(plugin)
                }
            },
            remove: { plugin in
                Task {
                    await viewModel.remove(plugin)
                }
            },
            setPermissionGrant: { plugin, permission, granted in
                Task {
                    await viewModel.setPermission(permission, granted: granted, for: plugin)
                }
            },
            setTriggerEnabled: { plugin, trigger, enabled in
                Task {
                    await viewModel.setTrigger(trigger, enabled: enabled, for: plugin)
                }
            },
            openSettings: openSettings
        )
        .overlay(alignment: .bottom) {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .task {
            await viewModel.reload()
        }
        .refreshable {
            await viewModel.reload()
        }
    }
}

public struct PluginSettingsContainerView: View {
    @StateObject private var viewModel: PluginStoreViewModel
    private let pluginID: String

    public init(
        viewModel: @autoclosure @escaping () -> PluginStoreViewModel,
        pluginID: String
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.pluginID = pluginID
    }

    public var body: some View {
        ScrollView {
            if let plugin = viewModel.catalog.installed.first(where: { $0.id == pluginID }) {
                settingsPanel(for: plugin)
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
            } else {
                EmptyPluginState(
                    title: "Integration unavailable",
                    detail: "This integration is not installed on this device."
                )
                .padding(24)
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
        .background(Color.statusBackground)
        .overlay(alignment: .bottom) {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .task {
            await viewModel.reload()
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    @ViewBuilder
    private func settingsPanel(for plugin: InstalledPlugin) -> some View {
        let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
        let key = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
        PluginSettingsPanel(
            plugin: plugin,
            canConfigure: viewModel.canConfigure(plugin),
            accounts: viewModel.configuredAccounts[plugin.id, default: []],
            selectedAccountID: selectedAccountID,
            accountDisplayName: viewModel.accountDisplayNames[key, default: ""],
            setupValues: viewModel.setupValues[key, default: [:]],
            isSavingSetup: viewModel.savingSetupPluginID == plugin.id,
            setupResult: viewModel.setupResults[key],
            setupError: viewModel.setupErrors[key],
            permissions: viewModel.installedPermissions[plugin.id, default: []],
            savingPermissionID: viewModel.savingPermissionID,
            triggers: viewModel.installedTriggers[plugin.id, default: []],
            savingTriggerID: viewModel.savingTriggerID,
            runtimeStatus: viewModel.runtimeStatuses[plugin.id],
            resources: viewModel.pluginResources[plugin.id, default: []],
            updateSetupValue: { plugin, fieldID, value in
                viewModel.updateSetupValue(plugin, fieldID: fieldID, value: value)
            },
            updateAccountDisplayName: { plugin, value in
                viewModel.updateAccountDisplayName(plugin, value: value)
            },
            selectAccount: { plugin, accountID in
                viewModel.selectAccount(accountID, for: plugin)
            },
            addAccount: { plugin in
                viewModel.addAccount(for: plugin)
            },
            saveSetup: { plugin in
                Task { await viewModel.saveSetup(plugin) }
            },
            canRun: viewModel.canRun(plugin),
            isRunning: viewModel.runningPluginID == plugin.id,
            runResult: viewModel.runResults[key],
            runError: viewModel.runErrors[key],
            run: { plugin in
                Task { await viewModel.run(plugin) }
            },
            setPermissionGrant: { plugin, permission, granted in
                Task { await viewModel.setPermission(permission, granted: granted, for: plugin) }
            },
            setTriggerEnabled: { plugin, trigger, enabled in
                Task { await viewModel.setTrigger(trigger, enabled: enabled, for: plugin) }
            }
        )
    }
}

public struct PluginStoreView: View {
    private let catalog: PluginStoreCatalog
    private let installingPluginID: String?
    private let removingPluginID: String?
    private let runningPluginID: String?
    private let runResults: [String: String]
    private let runErrors: [String: String]
    private let setupValues: [String: [String: String]]
    private let accountDisplayNames: [String: String]
    private let configuredAccounts: [String: [PluginAccountConfiguration]]
    private let selectedAccountIDs: [String: String]
    private let savingSetupPluginID: String?
    private let setupResults: [String: String]
    private let setupErrors: [String: String]
    private let installedPermissions: [String: [InstalledPluginPermission]]
    private let savingPermissionID: String?
    private let installedTriggers: [String: [TriggerDefinition]]
    private let savingTriggerID: String?
    private let runtimeStatuses: [String: PluginRuntimeStatus]
    private let pluginResources: [String: [Resource]]
    private let canConfigure: (InstalledPlugin) -> Bool
    private let updateSetupValue: (InstalledPlugin, String, String) -> Void
    private let updateAccountDisplayName: (InstalledPlugin, String) -> Void
    private let selectAccount: (InstalledPlugin, String) -> Void
    private let addAccount: (InstalledPlugin) -> Void
    private let saveSetup: (InstalledPlugin) -> Void
    private let canRun: (InstalledPlugin) -> Bool
    private let run: (InstalledPlugin) -> Void
    private let install: (RegistryPluginSummary) -> Void
    private let remove: (InstalledPlugin) -> Void
    private let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) -> Void
    private let setTriggerEnabled: (InstalledPlugin, TriggerDefinition, Bool) -> Void
    private let openSettings: ((InstalledPlugin) -> Void)?
    @State private var pluginPendingRemoval: InstalledPlugin?
    @State private var presentedSettingsPlugin: InstalledPlugin?

    public init(
        catalog: PluginStoreCatalog,
        installingPluginID: String? = nil,
        removingPluginID: String? = nil,
        runningPluginID: String? = nil,
        runResults: [String: String] = [:],
        runErrors: [String: String] = [:],
        setupValues: [String: [String: String]] = [:],
        accountDisplayNames: [String: String] = [:],
        configuredAccounts: [String: [PluginAccountConfiguration]] = [:],
        selectedAccountIDs: [String: String] = [:],
        savingSetupPluginID: String? = nil,
        setupResults: [String: String] = [:],
        setupErrors: [String: String] = [:],
        installedPermissions: [String: [InstalledPluginPermission]] = [:],
        savingPermissionID: String? = nil,
        installedTriggers: [String: [TriggerDefinition]] = [:],
        savingTriggerID: String? = nil,
        runtimeStatuses: [String: PluginRuntimeStatus] = [:],
        pluginResources: [String: [Resource]] = [:],
        canConfigure: @escaping (InstalledPlugin) -> Bool = { _ in false },
        updateSetupValue: @escaping (InstalledPlugin, String, String) -> Void = { _, _, _ in },
        updateAccountDisplayName: @escaping (InstalledPlugin, String) -> Void = { _, _ in },
        selectAccount: @escaping (InstalledPlugin, String) -> Void = { _, _ in },
        addAccount: @escaping (InstalledPlugin) -> Void = { _ in },
        saveSetup: @escaping (InstalledPlugin) -> Void = { _ in },
        canRun: @escaping (InstalledPlugin) -> Bool = { _ in false },
        run: @escaping (InstalledPlugin) -> Void = { _ in },
        install: @escaping (RegistryPluginSummary) -> Void = { _ in },
        remove: @escaping (InstalledPlugin) -> Void = { _ in },
        setPermissionGrant: @escaping (InstalledPlugin, PluginPermission, Bool) -> Void = { _, _, _ in },
        setTriggerEnabled: @escaping (InstalledPlugin, TriggerDefinition, Bool) -> Void = { _, _, _ in },
        openSettings: ((InstalledPlugin) -> Void)? = nil
    ) {
        self.catalog = catalog
        self.installingPluginID = installingPluginID
        self.removingPluginID = removingPluginID
        self.runningPluginID = runningPluginID
        self.runResults = runResults
        self.runErrors = runErrors
        self.setupValues = setupValues
        self.accountDisplayNames = accountDisplayNames
        self.configuredAccounts = configuredAccounts
        self.selectedAccountIDs = selectedAccountIDs
        self.savingSetupPluginID = savingSetupPluginID
        self.setupResults = setupResults
        self.setupErrors = setupErrors
        self.installedPermissions = installedPermissions
        self.savingPermissionID = savingPermissionID
        self.installedTriggers = installedTriggers
        self.savingTriggerID = savingTriggerID
        self.runtimeStatuses = runtimeStatuses
        self.pluginResources = pluginResources
        self.canConfigure = canConfigure
        self.updateSetupValue = updateSetupValue
        self.updateAccountDisplayName = updateAccountDisplayName
        self.selectAccount = selectAccount
        self.addAccount = addAccount
        self.saveSetup = saveSetup
        self.canRun = canRun
        self.run = run
        self.install = install
        self.remove = remove
        self.setPermissionGrant = setPermissionGrant
        self.setTriggerEnabled = setTriggerEnabled
        self.openSettings = openSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PluginStoreHeader(installedCount: catalog.installed.count, availableCount: catalog.available.count)
                InstalledPluginSection(
                    plugins: catalog.installed,
                    configuredAccounts: configuredAccounts,
                    runtimeStatuses: runtimeStatuses,
                    canRun: canRun,
                    run: run,
                    removingPluginID: removingPluginID,
                    openSettings: showSettings,
                    requestRemoval: { pluginPendingRemoval = $0 }
                )
                AvailablePluginSection(
                    plugins: catalog.available,
                    installedPluginIDs: Set(catalog.installed.map(\.id)),
                    installingPluginID: installingPluginID,
                    install: install
                )
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(Color.statusBackground)
        .confirmationDialog(
            "Remove plugin?",
            isPresented: Binding(
                get: { pluginPendingRemoval != nil },
                set: { isPresented in
                    if isPresented == false {
                        pluginPendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pluginPendingRemoval {
                Button("Remove \(pluginPendingRemoval.name)", role: .destructive) {
                    remove(pluginPendingRemoval)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Status will delete this plugin's local configuration, schedules, suggested rules, permissions, and resources. Historical events and audit entries stay in place.")
        }
        .sheet(item: $presentedSettingsPlugin) { plugin in
            NavigationStack {
                pluginSettingsView(for: plugin)
                    .navigationTitle(plugin.name)
            }
        }
    }

    private func showSettings(_ plugin: InstalledPlugin) {
        if let openSettings {
            openSettings(plugin)
        } else {
            presentedSettingsPlugin = plugin
        }
    }

    @ViewBuilder
    private func pluginSettingsView(for plugin: InstalledPlugin) -> some View {
        let selectedAccountID = selectedAccountIDs[plugin.id]
        PluginSettingsPanel(
            plugin: plugin,
            canConfigure: canConfigure(plugin),
            accounts: configuredAccounts[plugin.id, default: []],
            selectedAccountID: selectedAccountID,
            accountDisplayName: accountDisplayNames[setupKey(pluginID: plugin.id, accountID: selectedAccountID), default: ""],
            setupValues: setupValues[setupKey(pluginID: plugin.id, accountID: selectedAccountID), default: [:]],
            isSavingSetup: savingSetupPluginID == plugin.id,
            setupResult: setupResults[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            setupError: setupErrors[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            permissions: installedPermissions[plugin.id, default: []],
            savingPermissionID: savingPermissionID,
            triggers: installedTriggers[plugin.id, default: []],
            savingTriggerID: savingTriggerID,
            runtimeStatus: runtimeStatuses[plugin.id],
            resources: pluginResources[plugin.id, default: []],
            updateSetupValue: updateSetupValue,
            updateAccountDisplayName: updateAccountDisplayName,
            selectAccount: selectAccount,
            addAccount: addAccount,
            saveSetup: saveSetup,
            canRun: canRun(plugin),
            isRunning: runningPluginID == plugin.id,
            runResult: runResults[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            runError: runErrors[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            run: run,
            setPermissionGrant: setPermissionGrant,
            setTriggerEnabled: setTriggerEnabled
        )
    }

    private func setupKey(pluginID: String, accountID: String?) -> String {
        "\(pluginID):\(accountID ?? "__new__:")"
    }
}

private struct PluginStoreHeader: View {
    let installedCount: Int
    let availableCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Integrations")
                .font(.system(size: 42, weight: .semibold, design: .default))
            Text("\(installedCount) installed, \(availableCount) available from the Status registry.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InstalledPluginSection: View {
    let plugins: [InstalledPlugin]
    let configuredAccounts: [String: [PluginAccountConfiguration]]
    let runtimeStatuses: [String: PluginRuntimeStatus]
    let canRun: (InstalledPlugin) -> Bool
    let run: (InstalledPlugin) -> Void
    let removingPluginID: String?
    let openSettings: (InstalledPlugin) -> Void
    let requestRemoval: (InstalledPlugin) -> Void

    var body: some View {
        PluginSection(title: "Installed") {
            if plugins.isEmpty {
                EmptyPluginState(
                    title: "No plugins installed",
                    detail: "Install read-only integrations from the registry to start collecting status events."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(plugins) { plugin in
                        InstalledPluginRow(
                            plugin: plugin,
                            accounts: configuredAccounts[plugin.id, default: []],
                            runtimeStatus: runtimeStatuses[plugin.id],
                            canRun: canRun(plugin),
                            run: run,
                            isRemoving: removingPluginID == plugin.id,
                            openSettings: openSettings,
                            requestRemoval: requestRemoval
                        )
                    }
                }
            }
        }
    }

}

private struct AvailablePluginSection: View {
    let plugins: [RegistryPluginSummary]
    let installedPluginIDs: Set<String>
    let installingPluginID: String?
    let install: (RegistryPluginSummary) -> Void

    var body: some View {
        PluginSection(title: "Registry") {
            if plugins.isEmpty {
                EmptyPluginState(
                    title: "Registry unavailable",
                    detail: "Installed plugins still work locally. The registry can be refreshed when the network is available."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(plugins) { plugin in
                        AvailablePluginRow(
                            plugin: plugin,
                            isInstalled: installedPluginIDs.contains(plugin.id),
                            isInstalling: installingPluginID == plugin.id,
                            install: install
                        )
                    }
                }
            }
        }
    }
}

private struct InstalledPluginRow: View {
    let plugin: InstalledPlugin
    let accounts: [PluginAccountConfiguration]
    let runtimeStatus: PluginRuntimeStatus?
    let canRun: Bool
    let run: (InstalledPlugin) -> Void
    let isRemoving: Bool
    let openSettings: (InstalledPlugin) -> Void
    let requestRemoval: (InstalledPlugin) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IntegrationIcon(provider: plugin.id, size: 32)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(plugin.name)
                        .font(.headline)
                    Text(plugin.installedVersion)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(plugin.description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(accountSummary)
                    if let runtimeStatus {
                        Text(runtimeStatus.status.displayName)
                            .foregroundStyle(runtimeStatus.status.statusColor)
                    } else {
                        Text("Not checked yet")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                PluginTrustLabel(trustLevel: plugin.trustLevel)
                HStack(spacing: 8) {
                    Button {
                        openSettings(plugin)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    if canRun {
                        Button {
                            run(plugin)
                        } label: {
                            Label("Run", systemImage: "play")
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(role: .destructive) {
                        requestRemoval(plugin)
                    } label: {
                        if isRemoving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRemoving)
                }
            }
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var accountSummary: String {
        if accounts.isEmpty {
            return "No accounts configured"
        }
        if accounts.count == 1 {
            return accounts[0].accountName
        }
        return "\(accounts.count) accounts"
    }
}

private struct PluginSettingsPanel: View {
    let plugin: InstalledPlugin
    let canConfigure: Bool
    let accounts: [PluginAccountConfiguration]
    let selectedAccountID: String?
    let accountDisplayName: String
    let setupValues: [String: String]
    let isSavingSetup: Bool
    let setupResult: String?
    let setupError: String?
    let permissions: [InstalledPluginPermission]
    let savingPermissionID: String?
    let triggers: [TriggerDefinition]
    let savingTriggerID: String?
    let runtimeStatus: PluginRuntimeStatus?
    let resources: [Resource]
    let updateSetupValue: (InstalledPlugin, String, String) -> Void
    let updateAccountDisplayName: (InstalledPlugin, String) -> Void
    let selectAccount: (InstalledPlugin, String) -> Void
    let addAccount: (InstalledPlugin) -> Void
    let saveSetup: (InstalledPlugin) -> Void
    let canRun: Bool
    let isRunning: Bool
    let runResult: String?
    let runError: String?
    let run: (InstalledPlugin) -> Void
    let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) -> Void
    let setTriggerEnabled: (InstalledPlugin, TriggerDefinition, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IntegrationIcon(provider: plugin.id, size: 32)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(plugin.name)
                            .font(.headline)
                        Text(plugin.installedVersion)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(plugin.description)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    PluginTrustLabel(trustLevel: plugin.trustLevel)
                    if canRun {
                        Button {
                            run(plugin)
                        } label: {
                            if isRunning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Run")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                    }
                }
            }
            if permissions.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(permissions) { permission in
                            PluginPermissionToggle(
                                permission: permission,
                                isSaving: savingPermissionID == permissionChangeID(permission),
                                update: { granted in
                                    setPermissionGrant(plugin, permission.permission, granted)
                                }
                            )
                        }
                    }
                }
            }
            if triggers.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Checks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(triggers) { trigger in
                            PluginTriggerToggle(
                                trigger: trigger,
                                isSaving: savingTriggerID == trigger.id,
                                update: { enabled in
                                    setTriggerEnabled(plugin, trigger, enabled)
                                }
                            )
                        }
                    }
                }
            }
            if let runtimeStatus {
                PluginRuntimeStatusView(status: runtimeStatus)
            }
            PluginDeclaredViewsPanel(plugin: plugin, resources: resources)
            if canConfigure {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Integration name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        plugin.name,
                        text: Binding(
                            get: { accountDisplayName },
                            set: { updateAccountDisplayName(plugin, $0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    if let setup = plugin.setup {
                        Text(setup.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let description = setup.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PluginAccountPicker(
                        accounts: accounts,
                        selectedAccountID: selectedAccountID,
                        select: { selectAccount(plugin, $0) },
                        addAccount: { addAccount(plugin) }
                    )
                    VStack(spacing: 10) {
                        ForEach(setupFields, id: \.id) { field in
                            PluginSetupFieldRow(
                                field: field,
                                value: setupValues[field.id, default: field.defaultValue ?? ""],
                                updateValue: { updateSetupValue(plugin, field.id, $0) }
                            )
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            saveSetup(plugin)
                        } label: {
                            if isSavingSetup {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Save")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSavingSetup || hasMissingRequiredSetupValue)
                    }
                }
            }
            if let setupResult {
                Text(setupResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let setupError {
                Text(setupError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let runResult {
                Text(runResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let runError {
                Text(runError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var setupFields: [PackagedPluginSetupField] {
        plugin.configurationFields
    }

    private var hasMissingRequiredSetupValue: Bool {
        setupFields.contains { field in
            field.required && setupValues[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func permissionChangeID(_ permission: InstalledPluginPermission) -> String {
        "\(plugin.id):\(permission.permission.rawValue)"
    }
}

private struct PluginTriggerToggle: View {
    let trigger: TriggerDefinition
    let isSaving: Bool
    let update: (Bool) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { trigger.enabled },
                set: { update($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trigger.label)
                    .font(.caption)
                Text(trigger.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(isSaving)
    }
}

private struct PluginRuntimeStatusView: View {
    let status: PluginRuntimeStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(status.status.statusColor)
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(status.status.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.status.statusColor)
                    Text(status.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if status.emittedEventCount > 0 {
                    Text("\(status.emittedEventCount) event\(status.emittedEventCount == 1 ? "" : "s") emitted")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(status.status.statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PluginDeclaredViewsPanel: View {
    let plugin: InstalledPlugin
    let resources: [Resource]

    var body: some View {
        if plugin.views.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                Text("Views")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(plugin.views) { view in
                        PluginDeclaredViewCard(
                            plugin: plugin,
                            view: view,
                            resources: resources(for: view)
                        )
                    }
                }
            }
        }
    }

    private func resources(for view: PackagedPluginView) -> [Resource] {
        guard let resourceType = view.resourceType else {
            return resources
        }
        return resources.filter { $0.type == resourceType }
    }
}

private struct PluginDeclaredViewCard: View {
    let plugin: InstalledPlugin
    let view: PackagedPluginView
    let resources: [Resource]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(view.title ?? view.type.defaultTitle)
                    .font(.headline)
                Spacer(minLength: 12)
                Text(view.type.badge)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.statusBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch view.type {
        case .resourceList:
            PluginResourceListView(view: view, resources: resources)
        case .resourceDetail:
            if let resource = resources.first {
                PluginResourceDetailView(view: view, resource: resource)
            } else {
                Text("No \(view.resourceType ?? "resources") stored yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .overviewCards, .metricGrid:
            PluginResourceMetricGrid(view: view, resources: resources)
        case .timeline:
            PluginResourceTimeline(resources: resources)
        case .alertList:
            PluginResourceAlertList(plugin: plugin, resources: resources)
        }
    }
}

private struct PluginResourceListView: View {
    let view: PackagedPluginView
    let resources: [Resource]

    var body: some View {
        if resources.isEmpty {
            Text("No \(view.resourceType ?? "resources") stored yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                ForEach(resources) { resource in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resource.name)
                                .font(.callout.weight(.semibold))
                            PluginResourceFields(view: view, resource: resource)
                        }
                        Spacer(minLength: 12)
                        if let actionURL = resource.actionURL {
                            Link("Open", destination: actionURL)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.statusSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct PluginResourceDetailView: View {
    let view: PackagedPluginView
    let resource: Resource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(resource.name)
                .font(.callout.weight(.semibold))
            PluginResourceFields(view: view, resource: resource)
            if let actionURL = resource.actionURL {
                Link("Open source", destination: actionURL)
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

private struct PluginResourceMetricGrid: View {
    let view: PackagedPluginView
    let resources: [Resource]

    var body: some View {
        if resources.isEmpty {
            Text("No stored data yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(resources) { resource in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(resource.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        PluginResourceFields(view: view, resource: resource)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.statusSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct PluginResourceTimeline: View {
    let resources: [Resource]

    var body: some View {
        if resources.isEmpty {
            Text("No timeline resources stored yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(resources.prefix(8))) { resource in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(resource.name)
                            .font(.caption)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct PluginResourceAlertList: View {
    let plugin: InstalledPlugin
    let resources: [Resource]

    var body: some View {
        let attentionResources = resources.filter { resource in
            resource.fields.values.contains { value in
                let lowered = value.lowercased()
                return lowered.contains("failed") || lowered.contains("down") || lowered.contains("rejected")
            }
        }
        if attentionResources.isEmpty {
            Text("No \(plugin.name) resources need attention.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            PluginResourceListView(
                view: PackagedPluginView(id: "alerts", type: .resourceList, resourceType: nil, fields: []),
                resources: attentionResources
            )
        }
    }
}

private struct PluginResourceFields: View {
    let view: PackagedPluginView
    let resource: Resource

    var body: some View {
        let fields = resolvedFields
        if fields.isEmpty == false {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(fields, id: \.key) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(field.key.fieldLabel)
                            .foregroundStyle(.secondary)
                        Text(field.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var resolvedFields: [(key: String, value: String)] {
        let keys = view.fields.isEmpty ? Array(resource.fields.keys).sorted() : view.fields
        return keys.compactMap { key in
            guard let value = resource.fields[key], value.isEmpty == false else {
                return nil
            }
            return (key, value)
        }
    }
}

private struct PluginAccountPicker: View {
    let accounts: [PluginAccountConfiguration]
    let selectedAccountID: String?
    let select: (String) -> Void
    let addAccount: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if accounts.isEmpty {
                Text("New account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Account",
                    selection: Binding(
                        get: { selectedAccountID ?? accounts.first?.id ?? "" },
                        set: { select($0) }
                    )
                ) {
                    ForEach(accounts) { account in
                        Text(account.accountName).tag(account.id)
                    }
                    if let selectedAccountID, selectedAccountID.hasPrefix("__new__:") {
                        Text("New account").tag(selectedAccountID)
                    }
                }
                .pickerStyle(.menu)
            }
            Button {
                addAccount()
            } label: {
                Label("Add account", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct PluginPermissionToggle: View {
    let permission: InstalledPluginPermission
    let isSaving: Bool
    let update: (Bool) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { permission.granted },
                set: { update($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.permission.label)
                    .font(.caption)
                Text(permission.permission.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(isSaving)
    }
}

private struct PluginSetupFieldRow: View {
    let field: PackagedPluginSetupField
    let value: String
    let updateValue: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            switch field.type {
            case .toggle:
                Toggle(
                    field.label,
                    isOn: Binding(
                        get: { value == "true" },
                        set: { updateValue($0 ? "true" : "false") }
                    )
                )
                .labelsHidden()
            case .select:
                Picker(
                    field.label,
                    selection: Binding(
                        get: { value },
                        set: { updateValue($0) }
                    )
                ) {
                    ForEach(field.options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
            case .secret, .secretFile:
                SecureField(
                    field.placeholder ?? field.label,
                    text: Binding(
                        get: { value },
                        set: { updateValue($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            default:
                TextField(
                    field.placeholder ?? field.label,
                    text: Binding(
                        get: { value },
                        set: { updateValue($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(field.type == .hostname || field.type == .url ? .URL : field.type == .number ? .decimalPad : .default)
                #endif
            }
            if let help = field.help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension PackagedPluginSetupFieldType {
    var isLocallyPersistableSetupField: Bool {
        switch self {
        case .text, .url, .hostname, .number, .toggle, .select, .secret, .secretFile:
            true
        }
    }
}

private extension InstalledPlugin {
    var configurationFields: [PackagedPluginSetupField] {
        ((auth?.fields ?? []) + (setup?.fields ?? [])).filter { $0.type.isLocallyPersistableSetupField }
    }
}

private extension TriggerDefinition {
    var detail: String {
        switch kind {
        case .manual:
            return requestID.map { "Manual check: \($0)" } ?? "Manual check"
        case .cron:
            if let intervalSeconds {
                return "Scheduled every \(Self.format(intervalSeconds: intervalSeconds))"
            }
            return "Scheduled check"
        case .push:
            return "Webhook-triggered check"
        case .event:
            return "Event-triggered check"
        case .appLifecycle:
            return "Runs during app lifecycle changes"
        }
    }

    private static func format(intervalSeconds: TimeInterval) -> String {
        let seconds = Int(intervalSeconds)
        if seconds % 3_600 == 0 {
            let hours = seconds / 3_600
            return "\(hours)h"
        }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }
}

private extension JobStatus {
    var displayName: String {
        switch self {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .success:
            "Last check succeeded"
        case .failed:
            "Last check failed"
        case .cancelled:
            "Last check cancelled"
        case .skipped:
            "Last check skipped"
        }
    }

    var statusColor: Color {
        switch self {
        case .success:
            .green
        case .failed:
            .red
        case .skipped, .cancelled:
            .orange
        case .queued, .running:
            .blue
        }
    }
}

private extension PackagedPluginViewType {
    var defaultTitle: String {
        switch self {
        case .overviewCards:
            "Overview"
        case .resourceList:
            "Resources"
        case .resourceDetail:
            "Resource Detail"
        case .timeline:
            "Timeline"
        case .metricGrid:
            "Metrics"
        case .alertList:
            "Alerts"
        }
    }

    var badge: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
    }
}

private extension String {
    var fieldLabel: String {
        replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private extension PluginPermission {
    var label: String {
        switch self {
        case .network:
            "Network"
        case .keychain:
            "Keychain"
        case .oauth:
            "OAuth"
        case .apiKey:
            "API key"
        case .privateKey:
            "Private key"
        case .backgroundRefresh:
            "Background refresh"
        case .pushWebhook:
            "Push webhook"
        case .userConfiguredDomains:
            "User-configured domains"
        case .writeActions:
            "Write actions"
        case .localNotificationSuggestion:
            "Notification suggestions"
        }
    }

    var detail: String {
        switch self {
        case .network:
            "Allows the plugin to call its declared domains."
        case .keychain:
            "Allows Status to store credential references for this plugin."
        case .oauth:
            "Allows OAuth-based account connection when supported."
        case .apiKey:
            "Allows API-key based account connection."
        case .privateKey:
            "Allows private-key based account connection."
        case .backgroundRefresh:
            "Allows scheduled checks while the app is active."
        case .pushWebhook:
            "Allows incoming webhook-triggered events."
        case .userConfiguredDomains:
            "Allows requests to domains entered during setup."
        case .writeActions:
            "Allows explicitly approved write actions."
        case .localNotificationSuggestion:
            "Allows suggested notification rules."
        }
    }
}

public struct IntegrationVisual: Equatable {
    public var systemImage: String
    public var color: Color

    public init(systemImage: String, color: Color) {
        self.systemImage = systemImage
        self.color = color
    }

    public static func visual(for provider: String) -> IntegrationVisual {
        let key = provider.lowercased()
        if key.contains("github") {
            return IntegrationVisual(systemImage: "chevron.left.forwardslash.chevron.right", color: .primary)
        }
        if key.contains("appstore") {
            return IntegrationVisual(systemImage: "app.badge", color: .blue)
        }
        if key.contains("website") || key.contains("uptime") {
            return IntegrationVisual(systemImage: "globe", color: .green)
        }
        if key.contains("jira") || key.contains("atlassian") {
            return IntegrationVisual(systemImage: "diamond", color: .cyan)
        }
        return IntegrationVisual(systemImage: "puzzlepiece.extension", color: .orange)
    }
}

public struct IntegrationIcon: View {
    private let visual: IntegrationVisual
    private let size: CGFloat

    public init(provider: String, size: CGFloat = 28) {
        self.visual = IntegrationVisual.visual(for: provider)
        self.size = size
    }

    public var body: some View {
        Image(systemName: visual.systemImage)
            .font(.system(size: max(12, size * 0.48), weight: .semibold))
            .foregroundStyle(visual.color)
            .frame(width: size, height: size)
            .background(visual.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: min(8, size * 0.25)))
            .accessibilityHidden(true)
    }
}

private struct AvailablePluginRow: View {
    let plugin: RegistryPluginSummary
    let isInstalled: Bool
    let isInstalling: Bool
    let install: (RegistryPluginSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IntegrationIcon(provider: plugin.id, size: 32)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(plugin.name)
                            .font(.headline)
                        if let latestVersion = plugin.latestVersion {
                            Text(latestVersion)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(plugin.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    install(plugin)
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(isInstalled ? "Installed" : "Install")
                    }
                }
                .disabled(isInstalled || isInstalling || plugin.latestVersion == nil)
                .buttonStyle(.borderedProminent)
            }

            PluginMetadataLine(label: "Permissions", values: plugin.permissions.map(\.rawValue))
            PluginMetadataLine(label: "Domains", values: plugin.domains)
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PluginMetadataLine: View {
    let label: String
    let values: [String]

    var body: some View {
        if values.isEmpty == false {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(values.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }
}

private struct PluginTrustLabel: View {
    let trustLevel: PluginTrustLevel

    var body: some View {
        Text(trustLevel.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(trustLevel.color)
            .background(trustLevel.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct PluginTrustIcon: View {
    let trustLevel: PluginTrustLevel

    var body: some View {
        Image(systemName: trustLevel.iconName)
            .foregroundStyle(trustLevel.color)
            .frame(width: 22)
            .accessibilityLabel(Text(trustLevel.label))
    }
}

private struct EmptyPluginState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PluginSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension PluginTrustLevel {
    var label: String {
        switch self {
        case .official:
            "Official"
        case .verifiedThirdParty:
            "Verified"
        case .localDev:
            "Local"
        }
    }

    var iconName: String {
        switch self {
        case .official:
            "checkmark.seal.fill"
        case .verifiedThirdParty:
            "checkmark.shield.fill"
        case .localDev:
            "hammer.fill"
        }
    }

    var color: Color {
        switch self {
        case .official:
            .green
        case .verifiedThirdParty:
            .blue
        case .localDev:
            .orange
        }
    }
}
