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
    @Published public private(set) var savingSetupPluginID: String?
    @Published public private(set) var setupResults: [String: String]
    @Published public private(set) var setupErrors: [String: String]
    @Published public private(set) var installedPermissions: [String: [InstalledPluginPermission]]
    @Published public private(set) var savingPermissionID: String?

    private let loadInstalled: () throws -> [InstalledPlugin]
    private let loadAvailable: () async throws -> [RegistryPluginSummary]
    private let installPlugin: (RegistryPluginSummary) async throws -> Void
    private let removePlugin: (InstalledPlugin) async throws -> Void
    private let loadPermissions: (InstalledPlugin) throws -> [InstalledPluginPermission]
    private let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) async throws -> Void
    private let canRunPlugin: (InstalledPlugin) -> Bool
    private let runPlugin: (InstalledPlugin) async throws -> String
    private let canConfigurePlugin: (InstalledPlugin) -> Bool
    private let loadConfigurationValues: (InstalledPlugin) throws -> [String: String]
    private let saveConfigurationValues: (InstalledPlugin, [String: String]) async throws -> String

    public init(
        initialCatalog: PluginStoreCatalog = PluginStoreCatalog(),
        loadInstalled: @escaping () throws -> [InstalledPlugin],
        loadAvailable: @escaping () async throws -> [RegistryPluginSummary],
        installPlugin: @escaping (RegistryPluginSummary) async throws -> Void,
        removePlugin: @escaping (InstalledPlugin) async throws -> Void = { _ in },
        loadPermissions: @escaping (InstalledPlugin) throws -> [InstalledPluginPermission] = { _ in [] },
        setPermissionGrant: @escaping (InstalledPlugin, PluginPermission, Bool) async throws -> Void = { _, _, _ in },
        canRunPlugin: @escaping (InstalledPlugin) -> Bool = { _ in false },
        runPlugin: @escaping (InstalledPlugin) async throws -> String = { _ in "" },
        canConfigurePlugin: @escaping (InstalledPlugin) -> Bool = { _ in false },
        loadConfigurationValues: @escaping (InstalledPlugin) throws -> [String: String] = { _ in [:] },
        saveConfigurationValues: @escaping (InstalledPlugin, [String: String]) async throws -> String = { _, _ in "" }
    ) {
        self.catalog = initialCatalog
        self.runResults = [:]
        self.runErrors = [:]
        self.setupValues = [:]
        self.setupResults = [:]
        self.setupErrors = [:]
        self.installedPermissions = [:]
        self.loadInstalled = loadInstalled
        self.loadAvailable = loadAvailable
        self.installPlugin = installPlugin
        self.removePlugin = removePlugin
        self.loadPermissions = loadPermissions
        self.setPermissionGrant = setPermissionGrant
        self.canRunPlugin = canRunPlugin
        self.runPlugin = runPlugin
        self.canConfigurePlugin = canConfigurePlugin
        self.loadConfigurationValues = loadConfigurationValues
        self.saveConfigurationValues = saveConfigurationValues
    }

    public func reload() async {
        do {
            let installed = try loadInstalled()
            let available = try await loadAvailable()
            catalog = PluginStoreCatalog(installed: installed, available: available)
            refreshSetupValues(for: installed)
            refreshPermissions(for: installed)
            loadError = nil
        } catch {
            let installed = (try? loadInstalled()) ?? []
            catalog = PluginStoreCatalog(installed: installed, available: [])
            refreshSetupValues(for: installed)
            refreshPermissions(for: installed)
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
            installedPermissions[plugin.id] = nil
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

    public func canRun(_ plugin: InstalledPlugin) -> Bool {
        canRunPlugin(plugin)
    }

    public func canConfigure(_ plugin: InstalledPlugin) -> Bool {
        canConfigurePlugin(plugin)
    }

    public func updateSetupValue(_ plugin: InstalledPlugin, fieldID: String, value: String) {
        var values = setupValues[plugin.id, default: defaultSetupValues(for: plugin)]
        values[fieldID] = value
        setupValues[plugin.id] = values
        setupResults[plugin.id] = nil
        setupErrors[plugin.id] = nil
    }

    public func saveSetup(_ plugin: InstalledPlugin) async {
        guard savingSetupPluginID == nil else { return }
        let values = setupValues[plugin.id, default: defaultSetupValues(for: plugin)]
        savingSetupPluginID = plugin.id
        setupResults[plugin.id] = nil
        setupErrors[plugin.id] = nil
        defer { savingSetupPluginID = nil }

        do {
            setupResults[plugin.id] = try await saveConfigurationValues(plugin, values)
            await reload()
        } catch {
            setupErrors[plugin.id] = error.localizedDescription
        }
    }

    public func run(_ plugin: InstalledPlugin) async {
        guard runningPluginID == nil else { return }
        runningPluginID = plugin.id
        runResults[plugin.id] = nil
        runErrors[plugin.id] = nil
        defer { runningPluginID = nil }

        do {
            runResults[plugin.id] = try await runPlugin(plugin)
            await reload()
        } catch {
            runErrors[plugin.id] = error.localizedDescription
        }
    }

    private func refreshSetupValues(for plugins: [InstalledPlugin]) {
        for plugin in plugins where canConfigurePlugin(plugin) {
            let loaded = (try? loadConfigurationValues(plugin)) ?? [:]
            setupValues[plugin.id] = defaultSetupValues(for: plugin).merging(loaded) { _, loaded in loaded }
        }
    }

    private func refreshPermissions(for plugins: [InstalledPlugin]) {
        installedPermissions = Dictionary(uniqueKeysWithValues: plugins.map { plugin in
            (plugin.id, (try? loadPermissions(plugin)) ?? [])
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
}

public struct PluginStoreContainerView: View {
    @StateObject private var viewModel: PluginStoreViewModel

    public init(viewModel: @autoclosure @escaping () -> PluginStoreViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
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
            savingSetupPluginID: viewModel.savingSetupPluginID,
            setupResults: viewModel.setupResults,
            setupErrors: viewModel.setupErrors,
            installedPermissions: viewModel.installedPermissions,
            savingPermissionID: viewModel.savingPermissionID,
            canConfigure: { plugin in
                viewModel.canConfigure(plugin)
            },
            updateSetupValue: { plugin, fieldID, value in
                viewModel.updateSetupValue(plugin, fieldID: fieldID, value: value)
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
            }
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

public struct PluginStoreView: View {
    private let catalog: PluginStoreCatalog
    private let installingPluginID: String?
    private let removingPluginID: String?
    private let runningPluginID: String?
    private let runResults: [String: String]
    private let runErrors: [String: String]
    private let setupValues: [String: [String: String]]
    private let savingSetupPluginID: String?
    private let setupResults: [String: String]
    private let setupErrors: [String: String]
    private let installedPermissions: [String: [InstalledPluginPermission]]
    private let savingPermissionID: String?
    private let canConfigure: (InstalledPlugin) -> Bool
    private let updateSetupValue: (InstalledPlugin, String, String) -> Void
    private let saveSetup: (InstalledPlugin) -> Void
    private let canRun: (InstalledPlugin) -> Bool
    private let run: (InstalledPlugin) -> Void
    private let install: (RegistryPluginSummary) -> Void
    private let remove: (InstalledPlugin) -> Void
    private let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) -> Void
    @State private var pluginPendingRemoval: InstalledPlugin?

    public init(
        catalog: PluginStoreCatalog,
        installingPluginID: String? = nil,
        removingPluginID: String? = nil,
        runningPluginID: String? = nil,
        runResults: [String: String] = [:],
        runErrors: [String: String] = [:],
        setupValues: [String: [String: String]] = [:],
        savingSetupPluginID: String? = nil,
        setupResults: [String: String] = [:],
        setupErrors: [String: String] = [:],
        installedPermissions: [String: [InstalledPluginPermission]] = [:],
        savingPermissionID: String? = nil,
        canConfigure: @escaping (InstalledPlugin) -> Bool = { _ in false },
        updateSetupValue: @escaping (InstalledPlugin, String, String) -> Void = { _, _, _ in },
        saveSetup: @escaping (InstalledPlugin) -> Void = { _ in },
        canRun: @escaping (InstalledPlugin) -> Bool = { _ in false },
        run: @escaping (InstalledPlugin) -> Void = { _ in },
        install: @escaping (RegistryPluginSummary) -> Void = { _ in },
        remove: @escaping (InstalledPlugin) -> Void = { _ in },
        setPermissionGrant: @escaping (InstalledPlugin, PluginPermission, Bool) -> Void = { _, _, _ in }
    ) {
        self.catalog = catalog
        self.installingPluginID = installingPluginID
        self.removingPluginID = removingPluginID
        self.runningPluginID = runningPluginID
        self.runResults = runResults
        self.runErrors = runErrors
        self.setupValues = setupValues
        self.savingSetupPluginID = savingSetupPluginID
        self.setupResults = setupResults
        self.setupErrors = setupErrors
        self.installedPermissions = installedPermissions
        self.savingPermissionID = savingPermissionID
        self.canConfigure = canConfigure
        self.updateSetupValue = updateSetupValue
        self.saveSetup = saveSetup
        self.canRun = canRun
        self.run = run
        self.install = install
        self.remove = remove
        self.setPermissionGrant = setPermissionGrant
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PluginStoreHeader(installedCount: catalog.installed.count, availableCount: catalog.available.count)
                InstalledPluginSection(
                    plugins: catalog.installed,
                    runningPluginID: runningPluginID,
                    runResults: runResults,
                    runErrors: runErrors,
                    setupValues: setupValues,
                    savingSetupPluginID: savingSetupPluginID,
                    setupResults: setupResults,
                    setupErrors: setupErrors,
                    permissions: installedPermissions,
                    savingPermissionID: savingPermissionID,
                    canConfigure: canConfigure,
                    updateSetupValue: updateSetupValue,
                    saveSetup: saveSetup,
                    canRun: canRun,
                    run: run,
                    setPermissionGrant: setPermissionGrant,
                    removingPluginID: removingPluginID,
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
    let runningPluginID: String?
    let runResults: [String: String]
    let runErrors: [String: String]
    let setupValues: [String: [String: String]]
    let savingSetupPluginID: String?
    let setupResults: [String: String]
    let setupErrors: [String: String]
    let permissions: [String: [InstalledPluginPermission]]
    let savingPermissionID: String?
    let canConfigure: (InstalledPlugin) -> Bool
    let updateSetupValue: (InstalledPlugin, String, String) -> Void
    let saveSetup: (InstalledPlugin) -> Void
    let canRun: (InstalledPlugin) -> Bool
    let run: (InstalledPlugin) -> Void
    let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) -> Void
    let removingPluginID: String?
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
                            canConfigure: canConfigure(plugin),
                            setupValues: setupValues[plugin.id, default: [:]],
                            isSavingSetup: savingSetupPluginID == plugin.id,
                            setupResult: setupResults[plugin.id],
                            setupError: setupErrors[plugin.id],
                            permissions: permissions[plugin.id, default: []],
                            savingPermissionID: savingPermissionID,
                            updateSetupValue: updateSetupValue,
                            saveSetup: saveSetup,
                            canRun: canRun(plugin),
                            isRunning: runningPluginID == plugin.id,
                            runResult: runResults[plugin.id],
                            runError: runErrors[plugin.id],
                            run: run,
                            setPermissionGrant: setPermissionGrant,
                            isRemoving: removingPluginID == plugin.id,
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
    let canConfigure: Bool
    let setupValues: [String: String]
    let isSavingSetup: Bool
    let setupResult: String?
    let setupError: String?
    let permissions: [InstalledPluginPermission]
    let savingPermissionID: String?
    let updateSetupValue: (InstalledPlugin, String, String) -> Void
    let saveSetup: (InstalledPlugin) -> Void
    let canRun: Bool
    let isRunning: Bool
    let runResult: String?
    let runError: String?
    let run: (InstalledPlugin) -> Void
    let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) -> Void
    let isRemoving: Bool
    let requestRemoval: (InstalledPlugin) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PluginTrustIcon(trustLevel: plugin.trustLevel)
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
                    Text(plugin.enabled ? "Enabled" : "Disabled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(plugin.enabled ? .green : .orange)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    PluginTrustLabel(trustLevel: plugin.trustLevel)
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
                    .disabled(isRemoving || isRunning || isSavingSetup)
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
            if canConfigure {
                VStack(alignment: .leading, spacing: 8) {
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

private struct AvailablePluginRow: View {
    let plugin: RegistryPluginSummary
    let isInstalled: Bool
    let isInstalling: Bool
    let install: (RegistryPluginSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PluginTrustIcon(trustLevel: plugin.trustLevel)
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

private extension Color {
    static let statusBackground = Color(red: 0.965, green: 0.965, blue: 0.945)
    static let statusSurface = Color.white.opacity(0.92)
}
