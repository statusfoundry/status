import StatusCore
import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

public enum StatusOAuthCallbackRouter {
    public static let notificationName = Notification.Name("StatusOAuthCallbackRouter.callbackURL")

    public static func publish(_ url: URL) {
        guard isOAuthCallback(url) else { return }
        NotificationCenter.default.post(name: notificationName, object: url)
    }

    private static func isOAuthCallback(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme == "status" && components.host == "oauth"
    }
}

public struct PluginStoreCatalog: Equatable, Sendable {
    public var installed: [InstalledPlugin]
    public var available: [RegistryPluginSummary]

    public init(installed: [InstalledPlugin] = [], available: [RegistryPluginSummary] = []) {
        self.installed = installed
        self.available = available
    }

    public func availableUpdate(for plugin: InstalledPlugin) -> RegistryPluginSummary? {
        guard let availablePlugin = available.first(where: { $0.id == plugin.id }),
              let latestVersion = availablePlugin.latestVersion,
              Self.compareVersion(latestVersion, to: plugin.installedVersion) == .orderedDescending else {
            return nil
        }
        return availablePlugin
    }

    private static func compareVersion(_ lhs: String, to rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let delta = (left[safe: index] ?? 0) - (right[safe: index] ?? 0)
            if delta > 0 { return .orderedDescending }
            if delta < 0 { return .orderedAscending }
        }
        return .orderedSame
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum PluginStoreAccountSelection {
    static let newAccountPrefix = "__new__:"
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

struct PluginSettingsResourceScope {
    static func resources(_ resources: [Resource], selectedAccountID: String?) -> [Resource] {
        guard let selectedAccountID,
              selectedAccountID.hasPrefix(PluginStoreAccountSelection.newAccountPrefix) == false else {
            return []
        }
        return resources.filter { $0.accountID == selectedAccountID }
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
    @Published public private(set) var removingAccountID: String?
    @Published public private(set) var setupResults: [String: String]
    @Published public private(set) var setupErrors: [String: String]
    @Published public private(set) var installedPermissions: [String: [InstalledPluginPermission]]
    @Published public private(set) var savingPermissionID: String?
    @Published public private(set) var installedTriggers: [String: [TriggerDefinition]]
    @Published public private(set) var savingTriggerID: String?
    @Published public private(set) var pluginActions: [String: [PackagedPluginAction]]
    @Published public private(set) var runtimeStatuses: [String: PluginRuntimeStatus]
    @Published public private(set) var pluginResources: [String: [Resource]]
    @Published public private(set) var rulePresets: [String: [Rule]]
    @Published public private(set) var appRules: [String: [Rule]]
    @Published public private(set) var savingRuleID: String?
    @Published public private(set) var dashboardTileFields: [String: [String]]
    @Published public private(set) var savingDashboardTileFieldKey: String?
    @Published public private(set) var oauthConnectionURLs: [String: URL]
    @Published public private(set) var oauthConnectionErrors: [String: String]
    @Published public private(set) var completingOAuthConnectionKey: String?
    @Published public private(set) var testingRequestKey: String?
    @Published public private(set) var testRequestResults: [String: String]
    @Published public private(set) var testRequestErrors: [String: String]

    private let loadInstalled: () throws -> [InstalledPlugin]
    private let loadAvailable: () async throws -> [RegistryPluginSummary]
    private let loadRuntimeStatuses: ([InstalledPlugin], [String: [PluginAccountConfiguration]]) throws -> [String: PluginRuntimeStatus]
    private let loadPluginResources: (InstalledPlugin) throws -> [Resource]
    private let loadRules: (InstalledPlugin) throws -> [Rule]
    private let saveRule: (Rule) async throws -> Void
    private let deleteRule: (Rule) async throws -> Void
    private let loadActions: (InstalledPlugin) throws -> [PackagedPluginAction]
    private let loadDashboardTileFields: (InstalledPlugin, String) throws -> [String]
    private let saveDashboardTileFields: (InstalledPlugin, String, [String]) async throws -> Void
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
    private let deleteConfiguration: (InstalledPlugin, PluginAccountConfiguration) async throws -> String
    private let completeOAuthConnection: (InstalledPlugin, String?, String?, [String: String], PluginOAuthAuthorizationRequest, URL) async throws -> String
    private let testPluginRequest: (InstalledPlugin, PluginAccountConfiguration, String) async throws -> String
    private let previewProviderActionRequest: (ActionRuntimeProviderAction) async throws -> String
    private var oauthConnectionRequests: [String: PluginOAuthAuthorizationRequest]

    public init(
        initialCatalog: PluginStoreCatalog = PluginStoreCatalog(),
        loadInstalled: @escaping () throws -> [InstalledPlugin],
        loadAvailable: @escaping () async throws -> [RegistryPluginSummary],
        loadRuntimeStatuses: @escaping ([InstalledPlugin], [String: [PluginAccountConfiguration]]) throws -> [String: PluginRuntimeStatus] = { _, _ in [:] },
        loadPluginResources: @escaping (InstalledPlugin) throws -> [Resource] = { _ in [] },
        loadRules: @escaping (InstalledPlugin) throws -> [Rule] = { _ in [] },
        saveRule: @escaping (Rule) async throws -> Void = { _ in },
        deleteRule: @escaping (Rule) async throws -> Void = { _ in },
        loadActions: @escaping (InstalledPlugin) throws -> [PackagedPluginAction] = { _ in [] },
        loadDashboardTileFields: @escaping (InstalledPlugin, String) throws -> [String] = { _, _ in [] },
        saveDashboardTileFields: @escaping (InstalledPlugin, String, [String]) async throws -> Void = { _, _, _ in },
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
        saveConfigurationValues: @escaping (InstalledPlugin, String?, String?, [String: String]) async throws -> String = { _, _, _, _ in "" },
        deleteConfiguration: @escaping (InstalledPlugin, PluginAccountConfiguration) async throws -> String = { _, account in
            "Removed \(account.accountName)."
        },
        completeOAuthConnection: @escaping (InstalledPlugin, String?, String?, [String: String], PluginOAuthAuthorizationRequest, URL) async throws -> String = { _, _, _, _, _, _ in
            "OAuth callback received."
        },
        testPluginRequest: @escaping (InstalledPlugin, PluginAccountConfiguration, String) async throws -> String = { _, _, _ in "" },
        previewProviderActionRequest: @escaping (ActionRuntimeProviderAction) async throws -> String = { _ in "" }
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
        self.removingAccountID = nil
        self.installedPermissions = [:]
        self.installedTriggers = [:]
        self.pluginActions = [:]
        self.runtimeStatuses = [:]
        self.pluginResources = [:]
        self.rulePresets = [:]
        self.appRules = [:]
        self.dashboardTileFields = [:]
        self.oauthConnectionURLs = [:]
        self.oauthConnectionErrors = [:]
        self.completingOAuthConnectionKey = nil
        self.testingRequestKey = nil
        self.testRequestResults = [:]
        self.testRequestErrors = [:]
        self.oauthConnectionRequests = [:]
        self.loadInstalled = loadInstalled
        self.loadAvailable = loadAvailable
        self.loadRuntimeStatuses = loadRuntimeStatuses
        self.loadPluginResources = loadPluginResources
        self.loadRules = loadRules
        self.saveRule = saveRule
        self.deleteRule = deleteRule
        self.loadActions = loadActions
        self.loadDashboardTileFields = loadDashboardTileFields
        self.saveDashboardTileFields = saveDashboardTileFields
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
        self.deleteConfiguration = deleteConfiguration
        self.completeOAuthConnection = completeOAuthConnection
        self.testPluginRequest = testPluginRequest
        self.previewProviderActionRequest = previewProviderActionRequest
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
            refreshPluginActions(for: installed)
            refreshRuntimeStatuses(for: installed)
            refreshPluginResources(for: installed)
            refreshRules(for: installed)
            refreshDashboardTileFields(for: installed)
            loadError = nil
        } catch {
            let installed = (try? loadInstalled()) ?? []
            catalog = PluginStoreCatalog(installed: installed, available: [])
            refreshAccounts(for: installed)
            refreshSetupValues(for: installed)
            refreshPermissions(for: installed)
            refreshTriggers(for: installed)
            refreshPluginActions(for: installed)
            refreshRuntimeStatuses(for: installed)
            refreshPluginResources(for: installed)
            refreshRules(for: installed)
            refreshDashboardTileFields(for: installed)
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
        testRequestResults = testRequestResults.filter { key, _ in key.hasPrefix("\(plugin.id):") == false }
        testRequestErrors = testRequestErrors.filter { key, _ in key.hasPrefix("\(plugin.id):") == false }
        defer { removingPluginID = nil }

        do {
            try await removePlugin(plugin)
            setupValues[plugin.id] = nil
            accountDisplayNames = accountDisplayNames.filter { key, _ in key.hasPrefix("\(plugin.id):") == false }
            configuredAccounts[plugin.id] = nil
            selectedAccountIDs[plugin.id] = nil
            installedPermissions[plugin.id] = nil
            installedTriggers[plugin.id] = nil
            pluginActions[plugin.id] = nil
            runtimeStatuses = runtimeStatuses.filter { key, _ in key != plugin.id && key.hasPrefix("\(plugin.id):") == false }
            pluginResources[plugin.id] = nil
            rulePresets[plugin.id] = nil
            appRules[plugin.id] = nil
            dashboardTileFields = dashboardTileFields.filter { key, _ in key.hasPrefix("\(plugin.id):") == false }
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

    public func setRulePreset(_ preset: Rule, enabled: Bool, for plugin: InstalledPlugin) async {
        guard savingRuleID == nil else { return }
        guard let account = selectedAccount(for: plugin) else {
            loadError = "Save an app before enabling suggested rules."
            return
        }
        if enabled, requiresWritePermission(preset.actions, for: plugin), hasGrantedPermission(.writeActions, for: plugin) == false {
            loadError = "Grant Write actions permission before enabling this rule."
            return
        }

        let appRuleID = appScopedRuleID(pluginID: plugin.id, accountID: account.id, presetID: preset.id)
        savingRuleID = appRuleID
        defer { savingRuleID = nil }

        do {
            var appRule = appRules[plugin.id, default: []].first { $0.id == appRuleID } ?? preset
            appRule.id = appRuleID
            appRule.enabled = enabled
            appRule.scope = .app
            appRule.accountID = account.id
            appRule.provider = appRule.provider ?? plugin.id
            try await saveRule(appRule)
            refreshRules(for: [plugin])
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func saveAppNotificationRule(
        for plugin: InstalledPlugin,
        ruleID: String? = nil,
        name: String,
        eventType: String,
        minimumSeverity: Severity?,
        notificationTitle: String
    ) async {
        let conditions = minimumSeverity.map {
            [RuleCondition(field: "severity", operation: .matchesSeverity, value: .string($0.rawValue))]
        } ?? []
        let title = notificationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let actions = [
            RuleActionDefinition(action: "status.inbox.add"),
            RuleActionDefinition(
                action: "notification.show",
                parameters: title.isEmpty ? [:] : ["title": title]
            )
        ]
        await saveCustomAppRule(
            for: plugin,
            ruleID: ruleID,
            name: name,
            eventType: eventType,
            conditions: conditions,
            actions: actions
        )
    }

    public func saveCustomAppRule(
        for plugin: InstalledPlugin,
        ruleID: String? = nil,
        name: String,
        eventType: String,
        conditions: [RuleCondition],
        actions: [RuleActionDefinition]
    ) async {
        guard savingRuleID == nil else { return }
        guard let account = selectedAccount(for: plugin) else {
            loadError = "Save an app before editing rules."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEventType = eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            loadError = "Rule name is required."
            return
        }
        guard trimmedEventType.isEmpty == false else {
            loadError = "Event type is required."
            return
        }
        guard actions.isEmpty == false else {
            loadError = "At least one action is required."
            return
        }
        if let unsupportedAction = actions.first(where: { actionSafetyLevel(for: $0, plugin: plugin) == .unsupported }) {
            loadError = "\(unsupportedAction.action) is not supported by Status."
            return
        }
        if requiresWritePermission(actions, for: plugin), hasGrantedPermission(.writeActions, for: plugin) == false {
            loadError = "Grant Write actions permission before saving this rule."
            return
        }

        let ruleID = ruleID ?? customAppRuleID(pluginID: plugin.id, accountID: account.id, name: trimmedName)
        savingRuleID = ruleID
        defer { savingRuleID = nil }

        do {
            try await saveRule(
                Rule(
                    id: ruleID,
                    name: trimmedName,
                    enabled: true,
                    scope: .app,
                    accountID: account.id,
                    provider: plugin.id,
                    eventType: trimmedEventType,
                    conditions: conditions,
                    actions: actions
                )
            )
            refreshRules(for: [plugin])
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func previewProviderActionRequests(
        for plugin: InstalledPlugin,
        eventType: String,
        actions: [RuleActionDefinition]
    ) async throws -> String {
        guard let account = selectedAccount(for: plugin) else {
            throw PluginRulePreviewError.accountRequired
        }
        let trimmedEventType = eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEventType.isEmpty == false else {
            throw PluginRulePreviewError.eventTypeRequired
        }
        let previewableActions = actions.filter { action in
            actionSafetyLevel(for: action, plugin: plugin) == .reviewRequired &&
                declaredAction(action.action, for: plugin) != nil
        }
        guard previewableActions.isEmpty == false else {
            throw PluginRulePreviewError.noProviderActions
        }
        let event = Event(
            id: "evt_preview_\(plugin.id.replacingOccurrences(of: ".", with: "_"))",
            provider: plugin.id,
            type: trimmedEventType,
            resourceID: "preview_resource",
            resourceName: "Preview resource",
            severity: .warning,
            title: "Preview event",
            summary: "Preview event summary.",
            timestamp: Date(),
            fingerprint: "preview:\(plugin.id):\(trimmedEventType)"
        )
        var previews: [String] = []
        for action in previewableActions {
            let runtimeAction = ActionRuntimeProviderAction(
                actionRunID: "run_preview_\(action.action.replacingOccurrences(of: ".", with: "_"))",
                action: action.action,
                provider: plugin.id,
                parameters: action.parameters.merging(["account_id": account.id]) { _, selectedAccountID in selectedAccountID },
                event: event
            )
            previews.append(try await previewProviderActionRequest(runtimeAction))
        }
        return previews.joined(separator: "\n\n---\n\n")
    }

    public func setAppRule(_ rule: Rule, enabled: Bool, for plugin: InstalledPlugin) async {
        guard savingRuleID == nil else { return }
        guard let account = selectedAccount(for: plugin), rule.accountID == account.id else {
            loadError = "Select the app that owns this rule before editing it."
            return
        }
        savingRuleID = rule.id
        defer { savingRuleID = nil }

        do {
            var updated = rule
            updated.enabled = enabled
            updated.scope = .app
            updated.accountID = account.id
            updated.provider = plugin.id
            try await saveRule(updated)
            refreshRules(for: [plugin])
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func deleteAppRule(_ rule: Rule, for plugin: InstalledPlugin) async {
        guard savingRuleID == nil else { return }
        guard let account = selectedAccount(for: plugin), rule.accountID == account.id else {
            loadError = "Select the app that owns this rule before deleting it."
            return
        }
        savingRuleID = rule.id
        defer { savingRuleID = nil }

        do {
            try await deleteRule(rule)
            refreshRules(for: [plugin])
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func setDashboardTileField(_ field: String, enabled: Bool, for plugin: InstalledPlugin) async {
        guard let account = selectedAccount(for: plugin) else {
            loadError = "Save an app before changing dashboard tile fields."
            return
        }
        let key = setupKey(pluginID: plugin.id, accountID: account.id)
        savingDashboardTileFieldKey = "\(key):\(field)"
        defer { savingDashboardTileFieldKey = nil }

        do {
            var fields = dashboardTileFields[key, default: []]
            if enabled {
                if fields.contains(field) == false {
                    fields.append(field)
                }
            } else {
                fields.removeAll { $0 == field }
            }
            fields = Array(fields.prefix(4))
            try await saveDashboardTileFields(plugin, account.id, fields)
            dashboardTileFields[key] = fields
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
        let previousAccountIDs = Set(configuredAccounts[plugin.id, default: []].map(\.id))
        savingSetupPluginID = plugin.id
        setupResults[key] = nil
        setupErrors[key] = nil
        defer { savingSetupPluginID = nil }

        do {
            let result = try await saveConfigurationValues(plugin, persistedAccountID(from: selectedAccountID), accountName, values)
            await reload()
            if persistedAccountID(from: selectedAccountID) == nil,
               let savedAccount = newlySavedAccount(for: plugin, previousAccountIDs: previousAccountIDs, displayName: accountName) {
                selectAccount(savedAccount.id, for: plugin)
                setupResults[setupKey(pluginID: plugin.id, accountID: savedAccount.id)] = result
            } else {
                setupResults[key] = result
            }
        } catch {
            setupErrors[key] = error.localizedDescription
        }
    }

    public func removeSelectedAccount(for plugin: InstalledPlugin) async {
        guard removingAccountID == nil,
              let account = selectedAccount(for: plugin) else { return }
        let key = setupKey(pluginID: plugin.id, accountID: account.id)
        removingAccountID = account.id
        setupResults[key] = nil
        setupErrors[key] = nil
        defer { removingAccountID = nil }

        do {
            let result = try await deleteConfiguration(plugin, account)
            await reload()
            let nextSelection = selectedAccountIDs[plugin.id]
            let resultKey = setupKey(pluginID: plugin.id, accountID: nextSelection)
            setupResults[resultKey] = result
        } catch {
            setupErrors[key] = error.localizedDescription
        }
    }

    @discardableResult
    public func beginOAuthConnection(_ plugin: InstalledPlugin) -> URL? {
        let key = setupKey(for: plugin)
        oauthConnectionURLs[key] = nil
        oauthConnectionErrors[key] = nil
        do {
            guard let auth = plugin.auth, auth.type == .oauth2 else {
                oauthConnectionErrors[key] = "This plugin does not use OAuth."
                return nil
            }
            let missingPermissions = missingOAuthPermissions(for: plugin)
            guard missingPermissions.isEmpty else {
                oauthConnectionErrors[key] = "Grant \(missingPermissions.map(\.label).joined(separator: ", ")) permission before connecting this app."
                return nil
            }
            let request = try PluginOAuth.authorizationRequest(pluginID: plugin.id, auth: auth)
            oauthConnectionRequests[key] = request
            oauthConnectionURLs[key] = request.url
            return request.url
        } catch {
            oauthConnectionErrors[key] = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func handleOAuthCallbackIfPending(callbackURL: URL) async -> Bool {
        guard completingOAuthConnectionKey == nil else { return true }
        guard let match = pendingOAuthConnection(for: callbackURL) else { return false }
        await completeOAuthConnection(callbackURL: callbackURL, match: match)
        return true
    }

    public func completeOAuthConnection(callbackURL: URL) async {
        guard completingOAuthConnectionKey == nil else { return }
        guard let match = pendingOAuthConnection(for: callbackURL) else {
            oauthConnectionErrors["oauth:callback"] = "No pending OAuth connection matches this callback."
            return
        }
        await completeOAuthConnection(callbackURL: callbackURL, match: match)
    }

    private func pendingOAuthConnection(for callbackURL: URL) -> (key: String, value: PluginOAuthAuthorizationRequest)? {
        oauthConnectionRequests.first { _, request in
            callbackURL.queryValue(named: "state") == request.state
        }
    }

    private func missingOAuthPermissions(for plugin: InstalledPlugin) -> [PluginPermission] {
        let granted = Set(installedPermissions[plugin.id, default: []]
            .filter(\.granted)
            .map(\.permission))
        return [PluginPermission.oauth, .keychain, .network].filter { granted.contains($0) == false }
    }

    private func completeOAuthConnection(
        callbackURL: URL,
        match: (key: String, value: PluginOAuthAuthorizationRequest)
    ) async {
        guard let pluginID = pluginID(fromSetupKey: match.key),
              let plugin = catalog.installed.first(where: { $0.id == pluginID }) else {
            oauthConnectionErrors[match.key] = "OAuth plugin is no longer installed."
            return
        }

        completingOAuthConnectionKey = match.key
        setupResults[match.key] = nil
        setupErrors[match.key] = nil
        oauthConnectionErrors[match.key] = nil
        defer { completingOAuthConnectionKey = nil }

        do {
            let accountID = persistedAccountID(from: accountID(fromSetupKey: match.key))
            let accountName = accountDisplayNames[match.key]
            let values = setupValues[match.key, default: defaultSetupValues(for: plugin)]
            let previousAccountIDs = Set(configuredAccounts[plugin.id, default: []].map(\.id))
            let result = try await completeOAuthConnection(plugin, accountID, accountName, values, match.value, callbackURL)
            oauthConnectionRequests[match.key] = nil
            oauthConnectionURLs[match.key] = nil
            await reload()
            if accountID == nil,
               let savedAccount = newlySavedAccount(for: plugin, previousAccountIDs: previousAccountIDs, displayName: accountName) {
                selectAccount(savedAccount.id, for: plugin)
                setupResults[setupKey(pluginID: plugin.id, accountID: savedAccount.id)] = result
            } else {
                setupResults[match.key] = result
            }
        } catch {
            oauthConnectionErrors[match.key] = error.localizedDescription
            setupErrors[match.key] = error.localizedDescription
        }
    }

    public func run(_ plugin: InstalledPlugin) async {
        guard runningPluginID == nil else { return }
        guard let account = selectedAccount(for: plugin) else {
            runErrors[setupKey(for: plugin)] = "Save an app before refreshing it."
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

    public func testRequest(_ requestID: String, for plugin: InstalledPlugin) async {
        guard testingRequestKey == nil else { return }
        guard let account = selectedAccount(for: plugin) else {
            testRequestErrors[setupKey(for: plugin)] = "Save an app before testing requests for it."
            return
        }
        let key = testRequestKey(pluginID: plugin.id, accountID: account.id, requestID: requestID)
        testingRequestKey = key
        testRequestResults[key] = nil
        testRequestErrors[key] = nil
        defer { testingRequestKey = nil }

        do {
            testRequestResults[key] = try await testPluginRequest(plugin, account, requestID)
        } catch {
            testRequestErrors[key] = error.localizedDescription
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

    private func newlySavedAccount(
        for plugin: InstalledPlugin,
        previousAccountIDs: Set<String>,
        displayName: String?
    ) -> PluginAccountConfiguration? {
        let accounts = configuredAccounts[plugin.id, default: []]
        let newAccounts = accounts.filter { previousAccountIDs.contains($0.id) == false }
        guard newAccounts.isEmpty == false else {
            return nil
        }
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedDisplayName.isEmpty == false,
           let matchingAccount = newAccounts.first(where: { $0.accountName == trimmedDisplayName }) {
            return matchingAccount
        }
        return newAccounts.first
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

    private func refreshPluginActions(for plugins: [InstalledPlugin]) {
        pluginActions = Dictionary(uniqueKeysWithValues: plugins.map { plugin in
            (plugin.id, (try? loadActions(plugin)) ?? [])
        })
    }

    private func refreshRuntimeStatuses(for plugins: [InstalledPlugin]) {
        runtimeStatuses = (try? loadRuntimeStatuses(plugins, configuredAccounts)) ?? [:]
    }

    private func refreshPluginResources(for plugins: [InstalledPlugin]) {
        pluginResources = Dictionary(uniqueKeysWithValues: plugins.map { plugin in
            (plugin.id, (try? loadPluginResources(plugin)) ?? [])
        })
    }

    private func refreshRules(for plugins: [InstalledPlugin]) {
        var refreshedPresets = rulePresets
        var refreshedAppRules = appRules
        for plugin in plugins {
            let rules = (try? loadRules(plugin)) ?? []
            refreshedPresets[plugin.id] = rules
                .filter { $0.provider == plugin.id && $0.scope == .plugin && $0.accountID == nil }
                .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            refreshedAppRules[plugin.id] = rules
                .filter { $0.provider == plugin.id && $0.scope == .app }
                .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
        }
        rulePresets = refreshedPresets
        appRules = refreshedAppRules
    }

    private func refreshDashboardTileFields(for plugins: [InstalledPlugin]) {
        var refreshedFields = dashboardTileFields
        for plugin in plugins {
            for account in configuredAccounts[plugin.id, default: []] {
                let key = setupKey(pluginID: plugin.id, accountID: account.id)
                refreshedFields[key] = (try? loadDashboardTileFields(plugin, account.id)) ?? []
            }
        }
        dashboardTileFields = refreshedFields
    }

    private func defaultSetupValues(for plugin: InstalledPlugin) -> [String: String] {
        Dictionary(uniqueKeysWithValues: plugin.configurationFields.map { field in
            (field.id, field.defaultValue ?? "")
        })
    }

    private func permissionChangeID(plugin: InstalledPlugin, permission: PluginPermission) -> String {
        "\(plugin.id):\(permission.rawValue)"
    }

    private func appScopedRuleID(pluginID: String, accountID: String, presetID: String) -> String {
        let rawID = "rule_app_\(pluginID)_\(accountID)_\(presetID)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return rawID
            .lowercased()
            .map { character in
                String(character).rangeOfCharacter(from: allowed) == nil ? "_" : String(character)
            }
            .joined()
    }

    private func customAppRuleID(pluginID: String, accountID: String, name: String) -> String {
        let rawID = "rule_custom_\(pluginID)_\(accountID)_\(name)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return rawID
            .lowercased()
            .map { character in
                String(character).rangeOfCharacter(from: allowed) == nil ? "_" : String(character)
            }
            .joined()
    }

    private func requiresWritePermission(_ actions: [RuleActionDefinition], for plugin: InstalledPlugin) -> Bool {
        actions.contains { actionSafetyLevel(for: $0, plugin: plugin) == .reviewRequired }
    }

    private func actionSafetyLevel(for action: RuleActionDefinition, plugin: InstalledPlugin) -> ActionSafetyLevel {
        ActionRunner.safetyLevel(for: action.action, declaredActions: pluginActions[plugin.id, default: []])
    }

    private func declaredAction(_ actionID: String, for plugin: InstalledPlugin) -> PackagedPluginAction? {
        pluginActions[plugin.id, default: []].first { $0.id == actionID }
    }

    private func hasGrantedPermission(_ permission: PluginPermission, for plugin: InstalledPlugin) -> Bool {
        installedPermissions[plugin.id, default: []].contains {
            $0.permission == permission && $0.granted
        }
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

    public func testRequestKey(plugin: InstalledPlugin, requestID: String) -> String? {
        guard let account = selectedAccount(for: plugin) else {
            return nil
        }
        return testRequestKey(pluginID: plugin.id, accountID: account.id, requestID: requestID)
    }

    public func testRequestKey(pluginID: String, accountID: String, requestID: String) -> String {
        "\(pluginID):\(accountID):\(requestID)"
    }

    private func pluginID(fromSetupKey key: String) -> String? {
        key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    private func accountID(fromSetupKey key: String) -> String? {
        let parts = key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        return String(parts[1])
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

    static let newAccountPrefix = PluginStoreAccountSelection.newAccountPrefix
}

private enum PluginRulePreviewError: Error, LocalizedError {
    case accountRequired
    case eventTypeRequired
    case noProviderActions

    var errorDescription: String? {
        switch self {
        case .accountRequired:
            return "Save an app before previewing provider actions."
        case .eventTypeRequired:
            return "Event type is required before previewing provider actions."
        case .noProviderActions:
            return "This rule has no provider-backed write actions to preview."
        }
    }
}

public struct PluginStoreContainerView: View {
    @StateObject private var viewModel: PluginStoreViewModel
    @StateObject private var notificationPreferencesViewModel: NotificationPreferencesViewModel
    private let notificationPreferenceGroups: (InstalledPlugin, String?) -> [NotificationPreferencePluginGroup]
    private let openSettings: ((InstalledPlugin) -> Void)?
    private let onAppsChanged: (() -> Void)?
    private let installLocalPlugin: (() async throws -> String)?
    private let previewPluginFixture: ((InstalledPlugin, String?) async throws -> String)?
    @State private var isInstallingLocalPlugin = false
    @State private var localPluginInstallResult: String?
    @State private var localPluginInstallError: String?
    @State private var previewingPluginID: String?
    @State private var previewResults: [String: String] = [:]
    @State private var previewErrors: [String: String] = [:]

    public init(
        viewModel: @autoclosure @escaping () -> PluginStoreViewModel,
        notificationPreferencesViewModel: @autoclosure @escaping () -> NotificationPreferencesViewModel = NotificationPreferencesViewModel(
            loadPluginGroups: { [] },
            loadPreferences: { [] },
            setPreference: { _, _, _, _ in }
        ),
        notificationPreferenceGroups: @escaping (InstalledPlugin, String?) -> [NotificationPreferencePluginGroup] = { _, _ in [] },
        openSettings: ((InstalledPlugin) -> Void)? = nil,
        onAppsChanged: (() -> Void)? = nil,
        installLocalPlugin: (() async throws -> String)? = nil,
        previewPluginFixture: ((InstalledPlugin, String?) async throws -> String)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _notificationPreferencesViewModel = StateObject(wrappedValue: notificationPreferencesViewModel())
        self.notificationPreferenceGroups = notificationPreferenceGroups
        self.openSettings = openSettings
        self.onAppsChanged = onAppsChanged
        self.installLocalPlugin = installLocalPlugin
        self.previewPluginFixture = previewPluginFixture
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
            removingAccountID: viewModel.removingAccountID,
            setupResults: viewModel.setupResults,
            setupErrors: viewModel.setupErrors,
            installedPermissions: viewModel.installedPermissions,
            savingPermissionID: viewModel.savingPermissionID,
            installedTriggers: viewModel.installedTriggers,
            savingTriggerID: viewModel.savingTriggerID,
            runtimeStatuses: viewModel.runtimeStatuses,
            pluginResources: viewModel.pluginResources,
            rulePresets: viewModel.rulePresets,
            appRules: viewModel.appRules,
            pluginActions: viewModel.pluginActions,
            savingRuleID: viewModel.savingRuleID,
            dashboardTileFields: viewModel.dashboardTileFields,
            savingDashboardTileFieldKey: viewModel.savingDashboardTileFieldKey,
            oauthConnectionURLs: viewModel.oauthConnectionURLs,
            oauthConnectionErrors: viewModel.oauthConnectionErrors,
            testingRequestKey: viewModel.testingRequestKey,
            testRequestResults: viewModel.testRequestResults,
            testRequestErrors: viewModel.testRequestErrors,
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
                    onAppsChanged?()
                }
            },
            removeSelectedAccount: { plugin in
                Task {
                    await viewModel.removeSelectedAccount(for: plugin)
                    onAppsChanged?()
                }
            },
            beginOAuthConnection: { plugin in
                viewModel.beginOAuthConnection(plugin)
            },
            testRequest: { plugin, requestID in
                Task {
                    await viewModel.testRequest(requestID, for: plugin)
                }
            },
            canRun: { plugin in
                viewModel.canRun(plugin)
            },
            run: { plugin in
                Task {
                    await viewModel.run(plugin)
                    NotificationCenter.default.post(name: .statusAppDataDidChange, object: nil)
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
                    onAppsChanged?()
                }
            },
            setPermissionGrant: { plugin, permission, granted in
                Task {
                    await viewModel.setPermission(permission, granted: granted, for: plugin)
                    onAppsChanged?()
                }
            },
            setTriggerEnabled: { plugin, trigger, enabled in
                Task {
                    await viewModel.setTrigger(trigger, enabled: enabled, for: plugin)
                    onAppsChanged?()
                }
            },
            setRulePresetEnabled: { plugin, preset, enabled in
                Task {
                    await viewModel.setRulePreset(preset, enabled: enabled, for: plugin)
                }
            },
            saveCustomAppRule: { plugin, ruleID, name, eventType, conditions, actions in
                Task {
                    await viewModel.saveCustomAppRule(
                        for: plugin,
                        ruleID: ruleID,
                        name: name,
                        eventType: eventType,
                        conditions: conditions,
                        actions: actions
                    )
                }
            },
            setAppRuleEnabled: { plugin, rule, enabled in
                Task {
                    await viewModel.setAppRule(rule, enabled: enabled, for: plugin)
                }
            },
            deleteAppRule: { plugin, rule in
                Task {
                    await viewModel.deleteAppRule(rule, for: plugin)
                }
            },
            setDashboardTileField: { plugin, field, enabled in
                Task {
                    await viewModel.setDashboardTileField(field, enabled: enabled, for: plugin)
                    onAppsChanged?()
                }
            },
            openSettings: openSettings,
            isInstallingLocalPlugin: isInstallingLocalPlugin,
            localPluginInstallResult: localPluginInstallResult,
            localPluginInstallError: localPluginInstallError,
            installLocalPlugin: localPluginInstallAction,
            previewingPluginID: previewingPluginID,
            previewResults: previewResults,
            previewErrors: previewErrors,
            previewPluginFixture: pluginFixturePreviewAction,
            notificationPreferencesViewModel: notificationPreferencesViewModel,
            notificationPreferenceGroups: notificationPreferenceGroups,
            previewRuleActions: { plugin, eventType, actions in
                try await viewModel.previewProviderActionRequests(for: plugin, eventType: eventType, actions: actions)
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
            notificationPreferencesViewModel.reload()
        }
        .refreshable {
            await viewModel.reload()
            notificationPreferencesViewModel.reload()
        }
        .onOpenURL { url in
            Task {
                if await viewModel.handleOAuthCallbackIfPending(callbackURL: url) {
                    onAppsChanged?()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StatusOAuthCallbackRouter.notificationName)) { notification in
            guard let url = notification.object as? URL else { return }
            Task {
                if await viewModel.handleOAuthCallbackIfPending(callbackURL: url) {
                    onAppsChanged?()
                }
            }
        }
    }

    private func runLocalPluginInstall() {
        guard isInstallingLocalPlugin == false, let installLocalPlugin else {
            return
        }
        isInstallingLocalPlugin = true
        localPluginInstallResult = nil
        localPluginInstallError = nil

        Task { @MainActor in
            defer { isInstallingLocalPlugin = false }
            do {
                localPluginInstallResult = try await installLocalPlugin()
                await viewModel.reload()
            } catch {
                localPluginInstallError = error.localizedDescription
            }
        }
    }

    private var localPluginInstallAction: (() -> Void)? {
        guard installLocalPlugin != nil else {
            return nil
        }
        return { runLocalPluginInstall() }
    }

    private func runPluginFixturePreview(_ plugin: InstalledPlugin, _ accountID: String?) {
        guard previewingPluginID == nil, let previewPluginFixture else {
            return
        }
        previewingPluginID = plugin.id
        previewResults[plugin.id] = nil
        previewErrors[plugin.id] = nil

        Task { @MainActor in
            defer { previewingPluginID = nil }
            do {
                previewResults[plugin.id] = try await previewPluginFixture(plugin, accountID)
            } catch {
                previewErrors[plugin.id] = error.localizedDescription
            }
        }
    }

    private var pluginFixturePreviewAction: ((InstalledPlugin, String?) -> Void)? {
        guard previewPluginFixture != nil else {
            return nil
        }
        return { plugin, accountID in
            runPluginFixturePreview(plugin, accountID)
        }
    }
}

public struct PluginSettingsContainerView: View {
    @StateObject private var viewModel: PluginStoreViewModel
    private let pluginID: String
    private let initialAccountID: String?
    private let onAppsChanged: (() -> Void)?
    @StateObject private var notificationPreferencesViewModel: NotificationPreferencesViewModel
    private let notificationPreferenceGroups: (InstalledPlugin, String?) -> [NotificationPreferencePluginGroup]
    @State private var appliedInitialAccountSelection = false

    public init(
        viewModel: @autoclosure @escaping () -> PluginStoreViewModel,
        pluginID: String,
        initialAccountID: String? = nil,
        onAppsChanged: (() -> Void)? = nil,
        notificationPreferencesViewModel: @autoclosure @escaping () -> NotificationPreferencesViewModel = NotificationPreferencesViewModel(
            loadPluginGroups: { [] },
            loadPreferences: { [] },
            setPreference: { _, _, _, _ in }
        ),
        notificationPreferenceGroups: @escaping (InstalledPlugin, String?) -> [NotificationPreferencePluginGroup] = { _, _ in [] }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.pluginID = pluginID
        self.initialAccountID = initialAccountID
        self.onAppsChanged = onAppsChanged
        _notificationPreferencesViewModel = StateObject(wrappedValue: notificationPreferencesViewModel())
        self.notificationPreferenceGroups = notificationPreferenceGroups
    }

    public var body: some View {
        ScrollView {
            if let plugin = viewModel.catalog.installed.first(where: { $0.id == pluginID }) {
                settingsPanel(for: plugin)
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
            } else {
                EmptyPluginState(
                    title: "App unavailable",
                    detail: "This plugin is not installed on this device."
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
            notificationPreferencesViewModel.reload()
            applyInitialAccountSelectionIfNeeded()
        }
        .refreshable {
            await viewModel.reload()
            notificationPreferencesViewModel.reload()
            applyInitialAccountSelectionIfNeeded()
        }
        .onOpenURL { url in
            Task {
                if await viewModel.handleOAuthCallbackIfPending(callbackURL: url) {
                    onAppsChanged?()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StatusOAuthCallbackRouter.notificationName)) { notification in
            guard let url = notification.object as? URL else { return }
            Task {
                if await viewModel.handleOAuthCallbackIfPending(callbackURL: url) {
                    onAppsChanged?()
                }
            }
        }
    }

    private func applyInitialAccountSelectionIfNeeded() {
        guard appliedInitialAccountSelection == false,
              let initialAccountID,
              let plugin = viewModel.catalog.installed.first(where: { $0.id == pluginID }),
              viewModel.configuredAccounts[pluginID, default: []].contains(where: { $0.id == initialAccountID }) else {
            return
        }
        viewModel.selectAccount(initialAccountID, for: plugin)
        appliedInitialAccountSelection = true
    }

    @ViewBuilder
    private func settingsPanel(for plugin: InstalledPlugin) -> some View {
        let selectedAccountID = viewModel.selectedAccountIDs[plugin.id]
        let key = "\(plugin.id):\(selectedAccountID ?? "__new__:")"
        let selectedResources = PluginSettingsResourceScope.resources(
            viewModel.pluginResources[plugin.id, default: []],
            selectedAccountID: selectedAccountID
        )
        PluginSettingsPanel(
            plugin: plugin,
            canConfigure: viewModel.canConfigure(plugin),
            accounts: viewModel.configuredAccounts[plugin.id, default: []],
            selectedAccountID: selectedAccountID,
            accountDisplayName: viewModel.accountDisplayNames[key, default: ""],
            setupValues: viewModel.setupValues[key, default: [:]],
            isSavingSetup: viewModel.savingSetupPluginID == plugin.id,
            isRemovingAccount: viewModel.removingAccountID == selectedAccountID,
            setupResult: viewModel.setupResults[key],
            setupError: viewModel.setupErrors[key],
            permissions: viewModel.installedPermissions[plugin.id, default: []],
            savingPermissionID: viewModel.savingPermissionID,
            triggers: viewModel.installedTriggers[plugin.id, default: []],
            savingTriggerID: viewModel.savingTriggerID,
            runtimeStatus: viewModel.runtimeStatuses[key] ?? viewModel.runtimeStatuses[plugin.id],
            resources: selectedResources,
            rulePresets: viewModel.rulePresets[plugin.id, default: []],
            appRules: viewModel.appRules[plugin.id, default: []],
            actions: viewModel.pluginActions[plugin.id, default: []],
            savingRuleID: viewModel.savingRuleID,
            selectedDashboardTileFields: viewModel.dashboardTileFields[key, default: []],
            savingDashboardTileFieldKey: viewModel.savingDashboardTileFieldKey,
            notificationPreferencesViewModel: notificationPreferencesViewModel,
            notificationPreferenceGroups: notificationPreferenceGroups(plugin, selectedAccountID),
            oauthConnectionURL: viewModel.oauthConnectionURLs[key],
            oauthConnectionError: viewModel.oauthConnectionErrors[key],
            testingRequestKey: viewModel.testingRequestKey,
            testRequestResults: viewModel.testRequestResults,
            testRequestErrors: viewModel.testRequestErrors,
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
                    onAppsChanged?()
                }
            },
            removeSelectedAccount: { plugin in
                Task {
                    await viewModel.removeSelectedAccount(for: plugin)
                    onAppsChanged?()
                }
            },
            beginOAuthConnection: { plugin in
                viewModel.beginOAuthConnection(plugin)
            },
            testRequest: { plugin, requestID in
                Task { await viewModel.testRequest(requestID, for: plugin) }
            },
            canRun: viewModel.canRun(plugin),
            isRunning: viewModel.runningPluginID == plugin.id,
            runResult: viewModel.runResults[key],
            runError: viewModel.runErrors[key],
            run: { plugin in
                Task {
                    await viewModel.run(plugin)
                    NotificationCenter.default.post(name: .statusAppDataDidChange, object: nil)
                }
            },
            isPreviewing: false,
            previewResult: nil,
            previewError: nil,
            previewFixture: nil,
            setPermissionGrant: { plugin, permission, granted in
                Task {
                    await viewModel.setPermission(permission, granted: granted, for: plugin)
                    onAppsChanged?()
                }
            },
            setTriggerEnabled: { plugin, trigger, enabled in
                Task {
                    await viewModel.setTrigger(trigger, enabled: enabled, for: plugin)
                    onAppsChanged?()
                }
            },
            setRulePresetEnabled: { plugin, preset, enabled in
                Task { await viewModel.setRulePreset(preset, enabled: enabled, for: plugin) }
            },
            saveCustomAppRule: { plugin, ruleID, name, eventType, conditions, actions in
                Task {
                    await viewModel.saveCustomAppRule(
                        for: plugin,
                        ruleID: ruleID,
                        name: name,
                        eventType: eventType,
                        conditions: conditions,
                        actions: actions
                    )
                }
            },
            setAppRuleEnabled: { plugin, rule, enabled in
                Task { await viewModel.setAppRule(rule, enabled: enabled, for: plugin) }
            },
            deleteAppRule: { plugin, rule in
                Task { await viewModel.deleteAppRule(rule, for: plugin) }
            },
            setDashboardTileField: { plugin, field, enabled in
                Task {
                    await viewModel.setDashboardTileField(field, enabled: enabled, for: plugin)
                    onAppsChanged?()
                }
            },
            previewRuleActions: { plugin, eventType, actions in
                try await viewModel.previewProviderActionRequests(for: plugin, eventType: eventType, actions: actions)
            }
        )
    }
}

public struct PluginAppDetailView: View {
    private let plugin: InstalledPlugin
    private let app: PluginAccountConfiguration?
    private let runtimeStatus: PluginRuntimeStatus?
    private let resources: [Resource]
    private let runUnavailableReason: String?
    private let openSettings: (() -> Void)?
    private let run: (() -> Void)?

    public init(
        plugin: InstalledPlugin,
        app: PluginAccountConfiguration?,
        runtimeStatus: PluginRuntimeStatus?,
        resources: [Resource],
        runUnavailableReason: String? = nil,
        openSettings: (() -> Void)? = nil,
        run: (() -> Void)? = nil
    ) {
        self.plugin = plugin
        self.app = app
        self.runtimeStatus = runtimeStatus
        self.resources = resources
        self.runUnavailableReason = runUnavailableReason
        self.openSettings = openSettings
        self.run = run
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                PluginAppDetailSummaryStrip(
                    runtimeStatus: runtimeStatus,
                    resources: resources
                )
                if let runtimeStatus {
                    PluginRuntimeStatusView(status: runtimeStatus)
                }
                if let runUnavailableReason {
                    RunUnavailableView(reason: runUnavailableReason)
                }
                if resources.isEmpty || plugin.views.isEmpty {
                    PluginFallbackAppDataPanel(plugin: plugin, resources: resources)
                } else {
                    PluginDeclaredViewsPanel(plugin: plugin, resources: resources)
                }
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .background(Color.statusBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            IntegrationIcon(provider: plugin.id, icon: plugin.iconPath, iconAsset: plugin.iconAsset, accentColor: plugin.accentColor, size: 42)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(app?.accountName ?? plugin.name)
                    .font(.system(size: 34, weight: .semibold, design: .default))
                Text("\(plugin.name) app")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("\(resources.count) stored resource\(resources.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if let run {
                    Button {
                        run()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Refresh \(app?.accountName ?? plugin.name)"))
                }
                if let openSettings {
                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Open settings for \(app?.accountName ?? plugin.name)"))
                }
            }
        }
    }
}

private struct PluginAppDetailSummaryStrip: View {
    let runtimeStatus: PluginRuntimeStatus?
    let resources: [Resource]

    private var facts: PluginAppDetailSummaryFacts {
        PluginAppDetailSummaryFacts(runtimeStatus: runtimeStatus, resources: resources)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            PluginAppDetailSummaryTile(
                title: "Status",
                value: facts.statusValue,
                detail: facts.statusTimestamp.map { Text($0, style: .relative) } ?? Text("Run a refresh to collect data"),
                systemImage: facts.statusIcon,
                tint: runtimeStatus?.status.statusColor ?? .secondary
            )
            PluginAppDetailSummaryTile(
                title: "Resources",
                value: "\(facts.resourceCount)",
                detail: Text(facts.resourceTypeDetail),
                systemImage: "square.stack.3d.up",
                tint: .blue
            )
            PluginAppDetailSummaryTile(
                title: "Events",
                value: "\(facts.emittedEventCount)",
                detail: Text("Emitted by last refresh"),
                systemImage: "waveform.path.ecg",
                tint: .purple
            )
            PluginAppDetailSummaryTile(
                title: "Source Data",
                value: facts.latestResourceName,
                detail: Text(facts.latestResourceDetail),
                systemImage: "link",
                tint: .green
            )
        }
    }
}

struct PluginAppDetailSummaryFacts: Equatable {
    var statusValue: String
    var statusTimestamp: Date?
    var statusIcon: String
    var resourceCount: Int
    var resourceTypeDetail: String
    var emittedEventCount: Int
    var latestResourceName: String
    var latestResourceDetail: String

    init(runtimeStatus: PluginRuntimeStatus?, resources: [Resource]) {
        self.statusValue = runtimeStatus?.status.displayName ?? "Not checked yet"
        self.statusTimestamp = runtimeStatus?.timestamp
        self.statusIcon = Self.statusIcon(for: runtimeStatus?.status)
        self.resourceCount = resources.count
        let resourceTypes = Set(resources.map(\.type)).count
        self.resourceTypeDetail = resourceTypes == 1 ? "1 resource type" : "\(resourceTypes) resource types"
        self.emittedEventCount = runtimeStatus?.emittedEventCount ?? 0
        self.latestResourceName = resources.first?.name ?? "Waiting"
        self.latestResourceDetail = resources.isEmpty ? "No stored resource" : "Latest stored resource"
    }

    private static func statusIcon(for status: JobStatus?) -> String {
        switch status {
        case .success:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .running:
            "arrow.clockwise.circle.fill"
        case .queued:
            "clock.fill"
        case .cancelled, .skipped:
            "minus.circle.fill"
        case nil:
            "circle.dashed"
        }
    }
}

private struct PluginAppDetailSummaryTile: View {
    let title: String
    let value: String
    let detail: Text
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.middle)
                detail
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(12)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RunUnavailableView: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 12)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh unavailable")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PluginFallbackAppDataPanel: View {
    let plugin: InstalledPlugin
    let resources: [Resource]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if resources.isEmpty {
                EmptyPluginState(
                    title: "No data stored yet",
                    detail: "Refresh this app after setup to fetch \(plugin.name) resources and events."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(resources.prefix(12)) { resource in
                        PluginResourceSummaryRow(resource: resource)
                    }
                }
            }
        }
    }
}

private struct PluginResourceSummaryRow: View {
    let resource: Resource

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(resource.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(resource.type)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if visibleFields.isEmpty == false {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 6) {
                        ForEach(visibleFields, id: \.key) { field in
                            ResourceFieldValue(field: field.key, value: field.value)
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            if let actionURL = resource.actionURL {
                Link(destination: actionURL) {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.bordered)
                .help("Open source")
                .accessibilityLabel(Text("Open \(resource.name)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var visibleFields: [(key: String, value: String)] {
        resource.fields
            .filter { $0.value.isEmpty == false }
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
            .prefix(6)
            .map { (key: $0.key, value: $0.value) }
    }
}

private struct ResourceFieldValue: View {
    let field: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayLabel(for: field))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if let url = URL(string: value), url.scheme?.hasPrefix("http") == true {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(url.host() ?? value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .font(.caption.weight(.semibold))
            } else {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueColor: Color {
        let normalizedField = field.lowercased()
        let normalizedValue = value.lowercased()
        guard normalizedField.contains("status") ||
            normalizedField.contains("state") ||
            normalizedField.contains("result") ||
            normalizedField.contains("severity") else {
            return .secondary
        }
        if normalizedValue.contains("fail") ||
            normalizedValue.contains("reject") ||
            normalizedValue.contains("critical") ||
            normalizedValue.contains("down") {
            return .red
        }
        if normalizedValue.contains("review") ||
            normalizedValue.contains("pending") ||
            normalizedValue.contains("warning") ||
            normalizedValue.contains("slow") {
            return .orange
        }
        if normalizedValue.contains("ok") ||
            normalizedValue.contains("success") ||
            normalizedValue.contains("ready") ||
            normalizedValue.contains("up") {
            return .green
        }
        return .secondary
    }

    private func displayLabel(for field: String) -> String {
        StatusFieldLabelFormatter.label(for: field)
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
    private let removingAccountID: String?
    private let setupResults: [String: String]
    private let setupErrors: [String: String]
    private let installedPermissions: [String: [InstalledPluginPermission]]
    private let savingPermissionID: String?
    private let installedTriggers: [String: [TriggerDefinition]]
    private let savingTriggerID: String?
    private let runtimeStatuses: [String: PluginRuntimeStatus]
    private let pluginResources: [String: [Resource]]
    private let rulePresets: [String: [Rule]]
    private let appRules: [String: [Rule]]
    private let pluginActions: [String: [PackagedPluginAction]]
    private let savingRuleID: String?
    private let dashboardTileFields: [String: [String]]
    private let savingDashboardTileFieldKey: String?
    private let oauthConnectionURLs: [String: URL]
    private let oauthConnectionErrors: [String: String]
    private let testingRequestKey: String?
    private let testRequestResults: [String: String]
    private let testRequestErrors: [String: String]
    private let canConfigure: (InstalledPlugin) -> Bool
    private let updateSetupValue: (InstalledPlugin, String, String) -> Void
    private let updateAccountDisplayName: (InstalledPlugin, String) -> Void
    private let selectAccount: (InstalledPlugin, String) -> Void
    private let addAccount: (InstalledPlugin) -> Void
    private let saveSetup: (InstalledPlugin) -> Void
    private let removeSelectedAccount: (InstalledPlugin) -> Void
    private let beginOAuthConnection: (InstalledPlugin) -> URL?
    private let testRequest: (InstalledPlugin, String) -> Void
    private let canRun: (InstalledPlugin) -> Bool
    private let run: (InstalledPlugin) -> Void
    private let install: (RegistryPluginSummary) -> Void
    private let remove: (InstalledPlugin) -> Void
    private let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) -> Void
    private let setTriggerEnabled: (InstalledPlugin, TriggerDefinition, Bool) -> Void
    private let setRulePresetEnabled: (InstalledPlugin, Rule, Bool) -> Void
    private let saveCustomAppRule: (InstalledPlugin, String?, String, String, [RuleCondition], [RuleActionDefinition]) -> Void
    private let setAppRuleEnabled: (InstalledPlugin, Rule, Bool) -> Void
    private let deleteAppRule: (InstalledPlugin, Rule) -> Void
    private let setDashboardTileField: (InstalledPlugin, String, Bool) -> Void
    private let openSettings: ((InstalledPlugin) -> Void)?
    private let isInstallingLocalPlugin: Bool
    private let localPluginInstallResult: String?
    private let localPluginInstallError: String?
    private let installLocalPlugin: (() -> Void)?
    private let previewingPluginID: String?
    private let previewResults: [String: String]
    private let previewErrors: [String: String]
    private let previewPluginFixture: ((InstalledPlugin, String?) -> Void)?
    @ObservedObject private var notificationPreferencesViewModel: NotificationPreferencesViewModel
    private let notificationPreferenceGroups: (InstalledPlugin, String?) -> [NotificationPreferencePluginGroup]
    private let previewRuleActions: (InstalledPlugin, String, [RuleActionDefinition]) async throws -> String
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
        removingAccountID: String? = nil,
        setupResults: [String: String] = [:],
        setupErrors: [String: String] = [:],
        installedPermissions: [String: [InstalledPluginPermission]] = [:],
        savingPermissionID: String? = nil,
        installedTriggers: [String: [TriggerDefinition]] = [:],
        savingTriggerID: String? = nil,
        runtimeStatuses: [String: PluginRuntimeStatus] = [:],
        pluginResources: [String: [Resource]] = [:],
        rulePresets: [String: [Rule]] = [:],
        appRules: [String: [Rule]] = [:],
        pluginActions: [String: [PackagedPluginAction]] = [:],
        savingRuleID: String? = nil,
        dashboardTileFields: [String: [String]] = [:],
        savingDashboardTileFieldKey: String? = nil,
        oauthConnectionURLs: [String: URL] = [:],
        oauthConnectionErrors: [String: String] = [:],
        testingRequestKey: String? = nil,
        testRequestResults: [String: String] = [:],
        testRequestErrors: [String: String] = [:],
        canConfigure: @escaping (InstalledPlugin) -> Bool = { _ in false },
        updateSetupValue: @escaping (InstalledPlugin, String, String) -> Void = { _, _, _ in },
        updateAccountDisplayName: @escaping (InstalledPlugin, String) -> Void = { _, _ in },
        selectAccount: @escaping (InstalledPlugin, String) -> Void = { _, _ in },
        addAccount: @escaping (InstalledPlugin) -> Void = { _ in },
        saveSetup: @escaping (InstalledPlugin) -> Void = { _ in },
        removeSelectedAccount: @escaping (InstalledPlugin) -> Void = { _ in },
        beginOAuthConnection: @escaping (InstalledPlugin) -> URL? = { _ in nil },
        testRequest: @escaping (InstalledPlugin, String) -> Void = { _, _ in },
        canRun: @escaping (InstalledPlugin) -> Bool = { _ in false },
        run: @escaping (InstalledPlugin) -> Void = { _ in },
        install: @escaping (RegistryPluginSummary) -> Void = { _ in },
        remove: @escaping (InstalledPlugin) -> Void = { _ in },
        setPermissionGrant: @escaping (InstalledPlugin, PluginPermission, Bool) -> Void = { _, _, _ in },
        setTriggerEnabled: @escaping (InstalledPlugin, TriggerDefinition, Bool) -> Void = { _, _, _ in },
        setRulePresetEnabled: @escaping (InstalledPlugin, Rule, Bool) -> Void = { _, _, _ in },
        saveCustomAppRule: @escaping (InstalledPlugin, String?, String, String, [RuleCondition], [RuleActionDefinition]) -> Void = { _, _, _, _, _, _ in },
        setAppRuleEnabled: @escaping (InstalledPlugin, Rule, Bool) -> Void = { _, _, _ in },
        deleteAppRule: @escaping (InstalledPlugin, Rule) -> Void = { _, _ in },
        setDashboardTileField: @escaping (InstalledPlugin, String, Bool) -> Void = { _, _, _ in },
        openSettings: ((InstalledPlugin) -> Void)? = nil,
        isInstallingLocalPlugin: Bool = false,
        localPluginInstallResult: String? = nil,
        localPluginInstallError: String? = nil,
        installLocalPlugin: (() -> Void)? = nil,
        previewingPluginID: String? = nil,
        previewResults: [String: String] = [:],
        previewErrors: [String: String] = [:],
        previewPluginFixture: ((InstalledPlugin, String?) -> Void)? = nil,
        notificationPreferencesViewModel: NotificationPreferencesViewModel = NotificationPreferencesViewModel(
            loadPluginGroups: { [] },
            loadPreferences: { [] },
            setPreference: { _, _, _, _ in }
        ),
        notificationPreferenceGroups: @escaping (InstalledPlugin, String?) -> [NotificationPreferencePluginGroup] = { _, _ in [] },
        previewRuleActions: @escaping (InstalledPlugin, String, [RuleActionDefinition]) async throws -> String = { _, _, _ in "" }
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
        self.removingAccountID = removingAccountID
        self.setupResults = setupResults
        self.setupErrors = setupErrors
        self.installedPermissions = installedPermissions
        self.savingPermissionID = savingPermissionID
        self.installedTriggers = installedTriggers
        self.savingTriggerID = savingTriggerID
        self.runtimeStatuses = runtimeStatuses
        self.pluginResources = pluginResources
        self.rulePresets = rulePresets
        self.appRules = appRules
        self.pluginActions = pluginActions
        self.savingRuleID = savingRuleID
        self.dashboardTileFields = dashboardTileFields
        self.savingDashboardTileFieldKey = savingDashboardTileFieldKey
        self.oauthConnectionURLs = oauthConnectionURLs
        self.oauthConnectionErrors = oauthConnectionErrors
        self.testingRequestKey = testingRequestKey
        self.testRequestResults = testRequestResults
        self.testRequestErrors = testRequestErrors
        self.canConfigure = canConfigure
        self.updateSetupValue = updateSetupValue
        self.updateAccountDisplayName = updateAccountDisplayName
        self.selectAccount = selectAccount
        self.addAccount = addAccount
        self.saveSetup = saveSetup
        self.removeSelectedAccount = removeSelectedAccount
        self.beginOAuthConnection = beginOAuthConnection
        self.testRequest = testRequest
        self.canRun = canRun
        self.run = run
        self.install = install
        self.remove = remove
        self.setPermissionGrant = setPermissionGrant
        self.setTriggerEnabled = setTriggerEnabled
        self.setRulePresetEnabled = setRulePresetEnabled
        self.saveCustomAppRule = saveCustomAppRule
        self.setAppRuleEnabled = setAppRuleEnabled
        self.deleteAppRule = deleteAppRule
        self.setDashboardTileField = setDashboardTileField
        self.openSettings = openSettings
        self.isInstallingLocalPlugin = isInstallingLocalPlugin
        self.localPluginInstallResult = localPluginInstallResult
        self.localPluginInstallError = localPluginInstallError
        self.installLocalPlugin = installLocalPlugin
        self.previewingPluginID = previewingPluginID
        self.previewResults = previewResults
        self.previewErrors = previewErrors
        self.previewPluginFixture = previewPluginFixture
        _notificationPreferencesViewModel = ObservedObject(wrappedValue: notificationPreferencesViewModel)
        self.notificationPreferenceGroups = notificationPreferenceGroups
        self.previewRuleActions = previewRuleActions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PluginStoreHeader(
                    installedCount: catalog.installed.count,
                    availableCount: catalog.available.count,
                    isInstallingLocalPlugin: isInstallingLocalPlugin,
                    localPluginInstallResult: localPluginInstallResult,
                    localPluginInstallError: localPluginInstallError,
                    installLocalPlugin: installLocalPlugin
                )
                InstalledPluginSection(
                    plugins: catalog.installed,
                    availableUpdates: Dictionary(uniqueKeysWithValues: catalog.installed.compactMap { plugin in
                        catalog.availableUpdate(for: plugin).map { (plugin.id, $0) }
                    }),
                    configuredAccounts: configuredAccounts,
                    selectedAccountIDs: selectedAccountIDs,
                    installedPermissions: installedPermissions,
                    runtimeStatuses: runtimeStatuses,
                    canRun: canRun,
                    run: run,
                    installingPluginID: installingPluginID,
                    install: install,
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
        let selectedResources = PluginSettingsResourceScope.resources(
            pluginResources[plugin.id, default: []],
            selectedAccountID: selectedAccountID
        )
        PluginSettingsPanel(
            plugin: plugin,
            canConfigure: canConfigure(plugin),
            accounts: configuredAccounts[plugin.id, default: []],
            selectedAccountID: selectedAccountID,
            accountDisplayName: accountDisplayNames[setupKey(pluginID: plugin.id, accountID: selectedAccountID), default: ""],
            setupValues: setupValues[setupKey(pluginID: plugin.id, accountID: selectedAccountID), default: [:]],
            isSavingSetup: savingSetupPluginID == plugin.id,
            isRemovingAccount: removingAccountID == selectedAccountID,
            setupResult: setupResults[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            setupError: setupErrors[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            permissions: installedPermissions[plugin.id, default: []],
            savingPermissionID: savingPermissionID,
            triggers: installedTriggers[plugin.id, default: []],
            savingTriggerID: savingTriggerID,
            runtimeStatus: runtimeStatuses[setupKey(pluginID: plugin.id, accountID: selectedAccountID)] ?? runtimeStatuses[plugin.id],
            resources: selectedResources,
            rulePresets: rulePresets[plugin.id, default: []],
            appRules: appRules[plugin.id, default: []],
            actions: pluginActions[plugin.id, default: []],
            savingRuleID: savingRuleID,
            selectedDashboardTileFields: dashboardTileFields[setupKey(pluginID: plugin.id, accountID: selectedAccountID), default: []],
            savingDashboardTileFieldKey: savingDashboardTileFieldKey,
            notificationPreferencesViewModel: notificationPreferencesViewModel,
            notificationPreferenceGroups: notificationPreferenceGroups(plugin, selectedAccountID),
            oauthConnectionURL: oauthConnectionURLs[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            oauthConnectionError: oauthConnectionErrors[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            testingRequestKey: testingRequestKey,
            testRequestResults: testRequestResults,
            testRequestErrors: testRequestErrors,
            updateSetupValue: updateSetupValue,
            updateAccountDisplayName: updateAccountDisplayName,
            selectAccount: selectAccount,
            addAccount: addAccount,
            saveSetup: saveSetup,
            removeSelectedAccount: removeSelectedAccount,
            beginOAuthConnection: beginOAuthConnection,
            testRequest: testRequest,
            canRun: canRun(plugin),
            isRunning: runningPluginID == plugin.id,
            runResult: runResults[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            runError: runErrors[setupKey(pluginID: plugin.id, accountID: selectedAccountID)],
            run: run,
            isPreviewing: previewingPluginID == plugin.id,
            previewResult: previewResults[plugin.id],
            previewError: previewErrors[plugin.id],
            previewFixture: previewPluginFixture.map { preview in
                { plugin in preview(plugin, selectedAccountID) }
            },
            setPermissionGrant: setPermissionGrant,
            setTriggerEnabled: setTriggerEnabled,
            setRulePresetEnabled: setRulePresetEnabled,
            saveCustomAppRule: saveCustomAppRule,
            setAppRuleEnabled: setAppRuleEnabled,
            deleteAppRule: deleteAppRule,
            setDashboardTileField: setDashboardTileField,
            previewRuleActions: previewRuleActions
        )
    }

    private func setupKey(pluginID: String, accountID: String?) -> String {
        "\(pluginID):\(accountID ?? "__new__:")"
    }
}

private struct PluginStoreHeader: View {
    let installedCount: Int
    let availableCount: Int
    let isInstallingLocalPlugin: Bool
    let localPluginInstallResult: String?
    let localPluginInstallError: String?
    let installLocalPlugin: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Plugins")
                    .font(.system(size: 42, weight: .semibold, design: .default))
                Spacer(minLength: 12)
                if let installLocalPlugin {
                    Button {
                        installLocalPlugin()
                    } label: {
                        if isInstallingLocalPlugin {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Install Local", systemImage: "folder.badge.plus")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstallingLocalPlugin)
                }
            }
            Text("\(installedCount) installed, \(availableCount) available from the Status registry. Create one or more apps from each plugin.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let localPluginInstallResult {
                Text(localPluginInstallResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let localPluginInstallError {
                Text(localPluginInstallError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InstalledPluginSection: View {
    let plugins: [InstalledPlugin]
    let availableUpdates: [String: RegistryPluginSummary]
    let configuredAccounts: [String: [PluginAccountConfiguration]]
    let selectedAccountIDs: [String: String]
    let installedPermissions: [String: [InstalledPluginPermission]]
    let runtimeStatuses: [String: PluginRuntimeStatus]
    let canRun: (InstalledPlugin) -> Bool
    let run: (InstalledPlugin) -> Void
    let installingPluginID: String?
    let install: (RegistryPluginSummary) -> Void
    let removingPluginID: String?
    let openSettings: (InstalledPlugin) -> Void
    let requestRemoval: (InstalledPlugin) -> Void

    var body: some View {
        PluginSection(title: "Installed Plugins") {
            if plugins.isEmpty {
                EmptyPluginState(
                    title: "No plugins installed",
                    detail: "Install a bundled, local, or registry plugin, then create one or more apps from it."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(plugins) { plugin in
                        InstalledPluginRow(
                            plugin: plugin,
                            availableUpdate: availableUpdates[plugin.id],
                            accounts: configuredAccounts[plugin.id, default: []],
                            selectedAccountID: selectedAccountIDs[plugin.id],
                            runtimeStatus: runtimeStatus(for: plugin),
                            canRun: canRun(plugin),
                            runUnavailableReason: runUnavailableReason(for: plugin),
                            run: run,
                            isUpdating: installingPluginID == plugin.id,
                            update: { summary in install(summary) },
                            isRemoving: removingPluginID == plugin.id,
                            openSettings: openSettings,
                            requestRemoval: requestRemoval
                        )
                    }
                }
            }
        }
    }

    private func runUnavailableReason(for plugin: InstalledPlugin) -> String? {
        guard canRun(plugin) else {
            return nil
        }
        let accounts = configuredAccounts[plugin.id, default: []]
        guard let selectedAccount = selectedAccount(for: plugin, accounts: accounts) else {
            return "Save an app before refreshing it."
        }
        let missing = missingRuntimePermissions(
            selectedAccount: selectedAccount,
            permissions: installedPermissions[plugin.id, default: []]
        )
        guard missing.isEmpty == false else {
            return nil
        }
        return "Grant \(permissionList(missing)) permission before refreshing this app."
    }

    private func selectedAccount(for plugin: InstalledPlugin, accounts: [PluginAccountConfiguration]) -> PluginAccountConfiguration? {
        if let selectedAccountID = selectedAccountIDs[plugin.id],
           selectedAccountID.hasPrefix("__new__:") == false,
           let account = accounts.first(where: { $0.id == selectedAccountID }) {
            return account
        }
        return accounts.first
    }

    private func runtimeStatus(for plugin: InstalledPlugin) -> PluginRuntimeStatus? {
        let accounts = configuredAccounts[plugin.id, default: []]
        if let account = selectedAccount(for: plugin, accounts: accounts),
           let status = runtimeStatuses["\(plugin.id):\(account.id)"] {
            return status
        }
        return runtimeStatuses[plugin.id]
    }

    private func missingRuntimePermissions(
        selectedAccount: PluginAccountConfiguration,
        permissions: [InstalledPluginPermission]
    ) -> [PluginPermission] {
        let declared = Set(permissions.map(\.permission))
        let granted = Set(permissions.filter(\.granted).map(\.permission))
        var required: [PluginPermission] = []
        if declared.contains(.network) {
            required.append(.network)
        }
        if declared.contains(.userConfiguredDomains) {
            required.append(.userConfiguredDomains)
        }
        if selectedAccount.credentialRef != nil, declared.contains(.keychain) {
            required.append(.keychain)
        }
        if selectedAccount.credentialRef != nil,
           declared.contains(.privateKey),
           selectedAccount.authType == AuthKind.jwtAPIKey.rawValue || selectedAccount.authType == AuthKind.privateKeyJWT.rawValue {
            required.append(.privateKey)
        }
        return required.filter { granted.contains($0) == false }
    }

    private func permissionList(_ permissions: [PluginPermission]) -> String {
        permissions.map(\.label).joined(separator: ", ")
    }
}

private struct AvailablePluginSection: View {
    let plugins: [RegistryPluginSummary]
    let installedPluginIDs: Set<String>
    let installingPluginID: String?
    let install: (RegistryPluginSummary) -> Void

    var body: some View {
        PluginSection(title: "Available Plugins") {
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
    let availableUpdate: RegistryPluginSummary?
    let accounts: [PluginAccountConfiguration]
    let selectedAccountID: String?
    let runtimeStatus: PluginRuntimeStatus?
    let canRun: Bool
    let runUnavailableReason: String?
    let run: (InstalledPlugin) -> Void
    let isUpdating: Bool
    let update: (RegistryPluginSummary) -> Void
    let isRemoving: Bool
    let openSettings: (InstalledPlugin) -> Void
    let requestRemoval: (InstalledPlugin) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IntegrationIcon(provider: plugin.id, icon: plugin.iconPath, iconAsset: plugin.iconAsset, accentColor: plugin.accentColor, size: 32)
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
                Text("By \(plugin.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appSummary.primary)
                    if let secondary = appSummary.secondary {
                        Text(secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let runtimeStatus {
                        Text(runtimeStatus.status.displayName)
                            .foregroundStyle(runtimeStatus.status.statusColor)
                        Text(runtimeStatus.timestamp, style: .relative)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Not checked yet")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                PluginTrustLabel(trustLevel: plugin.trustLevel)
                HStack(spacing: 8) {
                    Button {
                        openSettings(plugin)
                    } label: {
                        Label(settingsActionTitle, systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    if canRun {
                        Button {
                            run(plugin)
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(runUnavailableReason != nil)
                    }
                    if let availableUpdate {
                        Button {
                            update(availableUpdate)
                        } label: {
                            if isUpdating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Update", systemImage: "arrow.down.circle")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isUpdating || isRemoving)
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
                if let runUnavailableReason {
                    Label(runUnavailableReason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var appSummary: PluginCatalogAppSummaryText {
        PluginCatalogAppSummaryText(accounts: accounts, selectedAccountID: selectedAccountID)
    }

    private var settingsActionTitle: String {
        accounts.isEmpty ? "Set Up App" : "Manage Apps"
    }
}

struct PluginCatalogAppSummaryText: Equatable, Sendable {
    var primary: String
    var secondary: String?

    init(accounts: [PluginAccountConfiguration], selectedAccountID: String?) {
        if accounts.isEmpty {
            self.primary = "No apps configured"
            self.secondary = "Set up an app from this plugin."
            return
        }

        if accounts.count == 1, let account = accounts.first {
            self.primary = "1 app configured"
            self.secondary = account.accountName
            return
        }

        self.primary = "\(accounts.count) apps configured"
        if let selectedAccount = Self.selectedAccount(accounts: accounts, selectedAccountID: selectedAccountID) {
            self.secondary = "Selected for refresh: \(selectedAccount.accountName)"
        } else {
            let visibleNames = accounts.prefix(2).map(\.accountName).joined(separator: ", ")
            let remainingCount = accounts.count - 2
            self.secondary = remainingCount > 0 ? "\(visibleNames) + \(remainingCount) more" : visibleNames
        }
    }

    private static func selectedAccount(
        accounts: [PluginAccountConfiguration],
        selectedAccountID: String?
    ) -> PluginAccountConfiguration? {
        guard let selectedAccountID,
              selectedAccountID.hasPrefix(PluginStoreAccountSelection.newAccountPrefix) == false else {
            return nil
        }
        return accounts.first { $0.id == selectedAccountID }
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
    let isRemovingAccount: Bool
    let setupResult: String?
    let setupError: String?
    let permissions: [InstalledPluginPermission]
    let savingPermissionID: String?
    let triggers: [TriggerDefinition]
    let savingTriggerID: String?
    let runtimeStatus: PluginRuntimeStatus?
    let resources: [Resource]
    let rulePresets: [Rule]
    let appRules: [Rule]
    let actions: [PackagedPluginAction]
    let savingRuleID: String?
    let selectedDashboardTileFields: [String]
    let savingDashboardTileFieldKey: String?
    @ObservedObject var notificationPreferencesViewModel: NotificationPreferencesViewModel
    let notificationPreferenceGroups: [NotificationPreferencePluginGroup]
    let oauthConnectionURL: URL?
    let oauthConnectionError: String?
    let testingRequestKey: String?
    let testRequestResults: [String: String]
    let testRequestErrors: [String: String]
    let updateSetupValue: (InstalledPlugin, String, String) -> Void
    let updateAccountDisplayName: (InstalledPlugin, String) -> Void
    let selectAccount: (InstalledPlugin, String) -> Void
    let addAccount: (InstalledPlugin) -> Void
    let saveSetup: (InstalledPlugin) -> Void
    let removeSelectedAccount: (InstalledPlugin) -> Void
    let beginOAuthConnection: (InstalledPlugin) -> URL?
    let testRequest: (InstalledPlugin, String) -> Void
    let canRun: Bool
    let isRunning: Bool
    let runResult: String?
    let runError: String?
    let run: (InstalledPlugin) -> Void
    let isPreviewing: Bool
    let previewResult: String?
    let previewError: String?
    let previewFixture: ((InstalledPlugin) -> Void)?
    let setPermissionGrant: (InstalledPlugin, PluginPermission, Bool) -> Void
    let setTriggerEnabled: (InstalledPlugin, TriggerDefinition, Bool) -> Void
    let setRulePresetEnabled: (InstalledPlugin, Rule, Bool) -> Void
    let saveCustomAppRule: (InstalledPlugin, String?, String, String, [RuleCondition], [RuleActionDefinition]) -> Void
    let setAppRuleEnabled: (InstalledPlugin, Rule, Bool) -> Void
    let deleteAppRule: (InstalledPlugin, Rule) -> Void
    let setDashboardTileField: (InstalledPlugin, String, Bool) -> Void
    let previewRuleActions: (InstalledPlugin, String, [RuleActionDefinition]) async throws -> String
    @State private var confirmsAppRemoval = false

    var body: some View {
        let headerText = PluginSettingsHeaderText(
            pluginName: plugin.name,
            pluginVersion: plugin.installedVersion,
            appName: selectedAccount?.accountName
        )
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IntegrationIcon(provider: plugin.id, icon: plugin.iconPath, iconAsset: plugin.iconAsset, accentColor: plugin.accentColor, size: 32)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(headerText.title)
                            .font(.headline)
                        Text(headerText.metadata)
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
                                Text("Refresh")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || settingsRunUnavailableReason != nil)
                    }
                    if let previewFixture {
                        Button {
                            previewFixture(plugin)
                        } label: {
                            if isPreviewing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Preview Fixture", systemImage: "doc.text.magnifyingglass")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreviewing)
                    }
                }
            }
            if let settingsRunUnavailableReason {
                SettingsRunUnavailableView(reason: settingsRunUnavailableReason)
            }
            if canConfigure {
                VStack(alignment: .leading, spacing: 10) {
                    Text("App configuration")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    PluginAccountPicker(
                        accounts: accounts,
                        selectedAccountID: selectedAccountID,
                        select: { selectAccount(plugin, $0) },
                        addAccount: { addAccount(plugin) }
                    )
                    Text("App name")
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
                    VStack(spacing: 10) {
                        ForEach(setupFields, id: \.id) { field in
                            PluginSetupFieldRow(
                                field: field,
                                value: setupValues[field.id, default: field.defaultValue ?? ""],
                                updateValue: { updateSetupValue(plugin, field.id, $0) }
                            )
                        }
                    }
                    if plugin.usesOAuth {
                        PluginOAuthConnectionPanel(
                            plugin: plugin,
                            authorizationURL: oauthConnectionURL,
                            error: oauthConnectionError,
                            connect: { beginOAuthConnection(plugin) }
                        )
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
            if permissions.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(sortedPermissions) { permission in
                            PluginPermissionToggle(
                                permission: permission,
                                isRequiredForRefresh: runtimeRequiredPermissions.contains(permission.permission),
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("App behavior")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    PluginRequestTestPanel(
                        plugin: plugin,
                        requestIDs: requestIDs,
                        selectedAccountID: selectedPersistedAccountID,
                        testingRequestKey: testingRequestKey,
                        results: testRequestResults,
                        errors: testRequestErrors,
                        test: { requestID in
                            testRequest(plugin, requestID)
                        }
                    )
                    DashboardTileFieldsPanel(
                        selectedAccountID: selectedPersistedAccountID,
                        availableFields: availableDashboardTileFields,
                        recommendedFields: recommendedDashboardTileFields,
                        selectedFields: selectedDashboardTileFields,
                        savingFieldKey: savingDashboardTileFieldKey,
                        setupKey: selectedPersistedAccountID.map { "\(plugin.id):\($0)" },
                        setField: { field, enabled in
                            setDashboardTileField(plugin, field, enabled)
                        }
                    )
                    if selectedPersistedAccountID != nil {
                        NotificationPreferencesPanel(
                            viewModel: notificationPreferencesViewModel,
                            groups: notificationPreferenceGroups,
                            title: "Notifications",
                            detail: "Choose how this app handles plugin-declared events. Event overrides stay scoped to this app.",
                            emptyTitle: "This plugin does not declare notification-worthy events yet."
                        )
                    }
                    AppRulePresetsPanel(
                        plugin: plugin,
                        selectedAccountID: selectedPersistedAccountID,
                        permissions: permissions,
                        availableActions: actions,
                        presets: rulePresets,
                        appRules: appRules,
                        savingRuleID: savingRuleID,
                        setEnabled: { preset, enabled in
                            setRulePresetEnabled(plugin, preset, enabled)
                        }
                    )
                    CustomAppRulesPanel(
                        plugin: plugin,
                        selectedAccountID: selectedPersistedAccountID,
                        permissions: permissions,
                        availableActions: actions,
                        presets: rulePresets,
                        appRules: appRules,
                        savingRuleID: savingRuleID,
                        saveRule: { ruleID, name, eventType, conditions, actions in
                            saveCustomAppRule(plugin, ruleID, name, eventType, conditions, actions)
                        },
                        setRuleEnabled: { rule, enabled in
                            setAppRuleEnabled(plugin, rule, enabled)
                        },
                        deleteRule: { rule in
                            deleteAppRule(plugin, rule)
                        },
                        previewRuleActions: { eventType, actions in
                            try await previewRuleActions(plugin, eventType, actions)
                        }
                    )
                    if selectedPersistedAccountID != nil {
                        Divider()
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remove app")
                                    .font(.caption.weight(.semibold))
                                Text("Deletes this app's local configuration and active data. Historical events and audit entries stay in place.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 12)
                            Button(role: .destructive) {
                                confirmsAppRemoval = true
                            } label: {
                                if isRemovingAccount {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Remove App", systemImage: "trash")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRemovingAccount)
                        }
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
            if let previewResult {
                Text(previewResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let previewError {
                Text(previewError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Remove app?",
            isPresented: $confirmsAppRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove \(accountDisplayName.isEmpty ? plugin.name : accountDisplayName)", role: .destructive) {
                removeSelectedAccount(plugin)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Status will delete this app's local configuration, schedules, app-scoped rules, notification overrides, credential reference, stored credential material, and active resources. Historical events and audit entries stay in place.")
        }
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

    private var selectedAccount: PluginAccountConfiguration? {
        guard let selectedPersistedAccountID else {
            return nil
        }
        return accounts.first { $0.id == selectedPersistedAccountID }
    }

    private var settingsRunUnavailableReason: String? {
        guard canRun else {
            return nil
        }
        guard selectedPersistedAccountID != nil else {
            return "Save an app before refreshing it."
        }
        let missing = missingRuntimePermissions
        guard missing.isEmpty == false else {
            return nil
        }
        return "Grant \(permissionList(missing)) permission before refreshing this app."
    }

    private var sortedPermissions: [InstalledPluginPermission] {
        permissions.sorted { lhs, rhs in
            let lhsRank = permissionSortRank(lhs)
            let rhsRank = permissionSortRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.permission.label.localizedCaseInsensitiveCompare(rhs.permission.label) == .orderedAscending
        }
    }

    private func permissionSortRank(_ permission: InstalledPluginPermission) -> Int {
        if runtimeRequiredPermissions.contains(permission.permission) {
            return 0
        }
        if permission.granted == false {
            return 1
        }
        return 2
    }

    private var missingRuntimePermissions: [PluginPermission] {
        let granted = Set(permissions.filter(\.granted).map(\.permission))
        return runtimeRequiredPermissions.filter { granted.contains($0) == false }
    }

    private var runtimeRequiredPermissions: [PluginPermission] {
        let declared = Set(permissions.map(\.permission))
        var required: [PluginPermission] = []
        if declared.contains(.network) {
            required.append(.network)
        }
        if declared.contains(.userConfiguredDomains) {
            required.append(.userConfiguredDomains)
        }
        if selectedAccount?.credentialRef != nil, declared.contains(.keychain) {
            required.append(.keychain)
        }
        if let selectedAccount,
           selectedAccount.credentialRef != nil,
           declared.contains(.privateKey),
           selectedAccount.authType == AuthKind.jwtAPIKey.rawValue || selectedAccount.authType == AuthKind.privateKeyJWT.rawValue {
            required.append(.privateKey)
        }
        return required
    }

    private func permissionList(_ permissions: [PluginPermission]) -> String {
        permissions.map(\.label).joined(separator: ", ")
    }

    private var availableDashboardTileFields: [String] {
        let recommendedFields = recommendedDashboardTileFields
        let viewFields = plugin.views.flatMap(\.fields)
        let resourceFields = resources.flatMap { Array($0.fields.keys) }
        let sortedFields = Array(Set(viewFields + resourceFields)).sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return uniqueFields(recommendedFields + sortedFields)
    }

    private var recommendedDashboardTileFields: [String] {
        Array(plugin.dashboardTile?.defaultFields.prefix(4) ?? [])
    }

    private func uniqueFields(_ fields: [String]) -> [String] {
        var seen: Set<String> = []
        return fields.filter { field in
            guard seen.contains(field) == false else { return false }
            seen.insert(field)
            return true
        }
    }

    private var selectedPersistedAccountID: String? {
        guard let selectedAccountID, selectedAccountID.hasPrefix("__new__:") == false else {
            return nil
        }
        return selectedAccountID
    }

    private var requestIDs: [String] {
        Array(Set(triggers.compactMap(\.requestID))).sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}

struct PluginSettingsHeaderText: Equatable, Sendable {
    var title: String
    var metadata: String

    init(pluginName: String, pluginVersion: String, appName: String?) {
        if let appName, appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            self.title = appName
            self.metadata = "\(pluginName) \(pluginVersion)"
        } else {
            self.title = pluginName
            self.metadata = pluginVersion
        }
    }
}

private struct PluginRequestTestPanel: View {
    let plugin: InstalledPlugin
    let requestIDs: [String]
    let selectedAccountID: String?
    let testingRequestKey: String?
    let results: [String: String]
    let errors: [String: String]
    let test: (String) -> Void

    var body: some View {
        if requestIDs.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text("Test Requests")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if selectedAccountID == nil {
                    Text("Save an app before testing requests for it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(requestIDs, id: \.self) { requestID in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(requestID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button {
                                test(requestID)
                            } label: {
                                if testingRequestKey == key(for: requestID) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Test", systemImage: "network")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedAccountID == nil || testingRequestKey != nil)
                        }
                        if let result = results[key(for: requestID)] {
                            Text(result)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let error = errors[key(for: requestID)] {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .background(Color.statusBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func key(for requestID: String) -> String {
        "\(plugin.id):\(selectedAccountID ?? "__new__:"):\(requestID)"
    }
}

private struct SettingsRunUnavailableView: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 12)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh unavailable")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DashboardTileFieldsPanel: View {
    let selectedAccountID: String?
    let availableFields: [String]
    let recommendedFields: [String]
    let selectedFields: [String]
    let savingFieldKey: String?
    let setupKey: String?
    let setField: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dashboard tile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if selectedAccountID == nil {
                Text("Save an app before choosing dashboard tile fields.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if availableFields.isEmpty {
                Text("Refresh this app once to collect fields that can be shown on the tile.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(availableFields, id: \.self) { field in
                        Toggle(
                            isOn: Binding(
                                get: { selectedFields.contains(field) },
                                set: { setField(field, $0) }
                            )
                        ) {
                            HStack(spacing: 6) {
                                Text(displayLabel(for: field))
                                    .font(.caption)
                                if recommendedFields.contains(field) {
                                    Text("Default")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(isDisabled(field))
                    }
                }
            }
        }
    }

    private func isDisabled(_ field: String) -> Bool {
        guard let setupKey else { return true }
        return savingFieldKey == "\(setupKey):\(field)" || (selectedFields.count >= 4 && selectedFields.contains(field) == false)
    }

    private func displayLabel(for field: String) -> String {
        StatusFieldLabelFormatter.label(for: field)
    }
}

private struct AppRulePresetsPanel: View {
    let plugin: InstalledPlugin
    let selectedAccountID: String?
    let permissions: [InstalledPluginPermission]
    let availableActions: [PackagedPluginAction]
    let presets: [Rule]
    let appRules: [Rule]
    let savingRuleID: String?
    let setEnabled: (Rule, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested rules")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if presets.isEmpty {
                Text("This plugin does not ship suggested rules yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(presets) { preset in
                        AppRulePresetToggle(
                            preset: preset,
                            appRule: appRule(for: preset),
                            expectedRuleID: selectedAccountID.map {
                                appScopedRuleID(accountID: $0, presetID: preset.id)
                            },
                            selectedAccountID: selectedAccountID,
                            hasWritePermission: hasWritePermission,
                            savingRuleID: savingRuleID,
                            actionSafetyLevel: actionSafetyLevel,
                            update: { enabled in
                                setEnabled(preset, enabled)
                            }
                        )
                    }
                }
            }
        }
    }

    private var hasWritePermission: Bool {
        permissions.contains { $0.permission == .writeActions && $0.granted }
    }

    private func appRule(for preset: Rule) -> Rule? {
        guard let selectedAccountID else { return nil }
        return appRules.first { rule in
            rule.accountID == selectedAccountID && rule.id == appScopedRuleID(accountID: selectedAccountID, presetID: preset.id)
        }
    }

    private func actionSafetyLevel(for action: RuleActionDefinition) -> ActionSafetyLevel {
        ActionRunner.safetyLevel(for: action.action, declaredActions: availableActions)
    }

    private func appScopedRuleID(accountID: String, presetID: String) -> String {
        let rawID = "rule_app_\(plugin.id)_\(accountID)_\(presetID)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return rawID
            .lowercased()
            .map { character in
                String(character).rangeOfCharacter(from: allowed) == nil ? "_" : String(character)
            }
            .joined()
    }
}

private struct AppRulePresetToggle: View {
    let preset: Rule
    let appRule: Rule?
    let expectedRuleID: String?
    let selectedAccountID: String?
    let hasWritePermission: Bool
    let savingRuleID: String?
    let actionSafetyLevel: (RuleActionDefinition) -> ActionSafetyLevel
    let update: (Bool) -> Void
    @State private var confirmsReviewRequiredRule = false

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { appRule?.enabled == true },
                set: { enabled in
                    if enabled, requiresWritePermission {
                        confirmsReviewRequiredRule = true
                    } else {
                        update(enabled)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.caption)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if selectedAccountID == nil {
                    Text("Save an app before enabling this rule.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                RuleReviewPreview(
                    ruleName: preset.name,
                    actions: preset.actions,
                    hasWritePermission: hasWritePermission,
                    actionSafetyLevel: actionSafetyLevel
                )
            }
        }
        .disabled(selectedAccountID == nil || savingRuleID == expectedRuleID || (appRule?.enabled != true && requiresWritePermission && hasWritePermission == false))
        .confirmationDialog(
            "Enable write-action rule?",
            isPresented: $confirmsReviewRequiredRule,
            titleVisibility: .visible
        ) {
            Button("Enable \(preset.name)") {
                update(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(reviewConfirmationText)
        }
    }

    private var detail: String {
        let conditionCount = preset.conditions.count
        let actionCount = preset.actions.count
        return "\(preset.eventType) · \(conditionCount) condition\(conditionCount == 1 ? "" : "s") · \(actionCount) action\(actionCount == 1 ? "" : "s")"
    }

    private var requiresWritePermission: Bool {
        preset.actions.contains { actionSafetyLevel($0) == .reviewRequired }
    }

    private var reviewRequiredActionNames: String {
        preset.actions
            .filter { actionSafetyLevel($0) == .reviewRequired }
            .map(\.action)
            .joined(separator: ", ")
    }

    private var reviewConfirmationText: String {
        "This app has Write actions permission. When \(preset.name) matches \(preset.eventType), Status may run \(reviewRequiredActionNames). Every action run will create an audit entry with the triggering event, rule, action, result, and error if it fails."
    }
}

private struct CustomAppRulesPanel: View {
    let plugin: InstalledPlugin
    let selectedAccountID: String?
    let permissions: [InstalledPluginPermission]
    let availableActions: [PackagedPluginAction]
    let presets: [Rule]
    let appRules: [Rule]
    let savingRuleID: String?
    let saveRule: (String?, String, String, [RuleCondition], [RuleActionDefinition]) -> Void
    let setRuleEnabled: (Rule, Bool) -> Void
    let deleteRule: (Rule) -> Void
    let previewRuleActions: (String, [RuleActionDefinition]) async throws -> String
    @State private var editingRuleID: String?
    @State private var draftName = ""
    @State private var draftEventType = ""
    @State private var draftConditions = [CustomRuleConditionDraft(field: "severity", operation: .matchesSeverity, value: Severity.warning.rawValue)]
    @State private var draftActions = [
        CustomRuleActionDraft(action: "status.inbox.add"),
        CustomRuleActionDraft(action: "notification.show", value: "{{event.title}}")
    ]
    @State private var requestPreviewResult: String?
    @State private var requestPreviewError: String?
    @State private var requestPreviewSignature: String?
    @State private var isPreviewingRequest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom rules")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if selectedAccountID == nil {
                Text("Save an app before creating app-specific rules.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(customRules) { rule in
                        CustomAppRuleRow(
                            rule: rule,
                            isSaving: savingRuleID == rule.id,
                            setEnabled: { setRuleEnabled(rule, $0) },
                            edit: { load(rule) },
                            delete: { deleteRule(rule) }
                        )
                    }
                    if customRules.isEmpty {
                        Text("No custom rules for this app yet.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(editingRuleID == nil ? "New notification rule" : "Edit notification rule")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Rule name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Event type", text: $draftEventType)
                        .textFieldStyle(.roundedBorder)
                    if eventTypeSuggestions.isEmpty == false {
                        Picker("Known event", selection: $draftEventType) {
                            if eventTypeSuggestions.contains(draftEventType) == false {
                                Text(draftEventType.isEmpty ? "Custom" : "Custom: \(draftEventType)").tag(draftEventType)
                            }
                            ForEach(eventTypeSuggestions, id: \.self) { eventType in
                                Text(eventType).tag(eventType)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Conditions")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        ForEach($draftConditions) { $condition in
                            CustomRuleConditionDraftRow(
                                condition: $condition,
                                canDelete: draftConditions.count > 1,
                                delete: {
                                    draftConditions.removeAll { $0.id == condition.id }
                                }
                            )
                        }
                        Button {
                            draftConditions.append(CustomRuleConditionDraft())
                        } label: {
                            Label("Add Condition", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Actions")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        ForEach($draftActions) { $action in
                            CustomRuleActionDraftRow(
                                action: $action,
                                availableActions: availableActions,
                                canDelete: draftActions.count > 1,
                                delete: {
                                    draftActions.removeAll { $0.id == action.id }
                                }
                            )
                        }
                        Button {
                            draftActions.append(CustomRuleActionDraft())
                        } label: {
                            Label("Add Action", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    RuleReviewPreview(
                        ruleName: draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "this rule" : draftName,
                        actions: draftRuleActions,
                        hasWritePermission: hasWritePermission,
                        actionSafetyLevel: actionSafetyLevel
                    )
                    if canPreviewProviderActions {
                        ProviderActionRequestPreviewPanel(
                            isPreviewing: isPreviewingRequest,
                            result: requestPreviewResult,
                            error: requestPreviewError,
                            requiresCurrentPreview: requestPreviewIsCurrent == false,
                            preview: runRequestPreview
                        )
                    }
                    HStack {
                        if editingRuleID != nil {
                            Button("Cancel") {
                                resetDraft()
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button {
                            saveRule(
                                editingRuleID,
                                draftName,
                                draftEventType,
                                conditions,
                                draftRuleActions
                            )
                            resetDraft()
                        } label: {
                            if let editingRuleID, savingRuleID == editingRuleID {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(editingRuleID == nil ? "Add Rule" : "Update Rule", systemImage: "checkmark.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            isDraftValid == false ||
                                savingRuleID != nil ||
                                (requiresWritePermission && hasWritePermission == false) ||
                                (requiresProviderActionPreview && requestPreviewIsCurrent == false)
                        )
                    }
                }
                .padding(10)
                .background(Color.statusBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            if draftEventType.isEmpty {
                draftEventType = eventTypeSuggestions.first ?? ""
            }
        }
    }

    private var conditions: [RuleCondition] {
        draftConditions.compactMap(\.ruleCondition)
    }

    private var draftRuleActions: [RuleActionDefinition] {
        draftActions.compactMap { draft in
            draft.ruleAction(actionDefinition: actionDefinition(for: draft.action))
        }
    }

    private var isDraftValid: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            draftEventType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            draftConditions.allSatisfy(\.isValid) &&
            draftActions.allSatisfy { $0.isValid(actionDefinition: actionDefinition(for: $0.action)) } &&
            draftRuleActions.isEmpty == false
    }

    private var requiresWritePermission: Bool {
        draftRuleActions.contains { actionSafetyLevel(for: $0) == .reviewRequired }
    }

    private var canPreviewProviderActions: Bool {
        draftRuleActions.contains { action in
            actionSafetyLevel(for: action) == .reviewRequired &&
                actionDefinition(for: action.action) != nil
        }
    }

    private var requiresProviderActionPreview: Bool {
        canPreviewProviderActions
    }

    private var requestPreviewIsCurrent: Bool {
        requestPreviewSignature == currentRequestPreviewSignature
    }

    private var currentRequestPreviewSignature: String {
        let actionSignature = draftRuleActions
            .filter { action in
                actionSafetyLevel(for: action) == .reviewRequired &&
                    actionDefinition(for: action.action) != nil
            }
            .map { action in
                let parameterSignature = action.parameters
                    .sorted { lhs, rhs in lhs.key < rhs.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "&")
                return "\(action.action){\(parameterSignature)}"
            }
            .joined(separator: "|")
        return [
            selectedAccountID ?? "",
            draftEventType.trimmingCharacters(in: .whitespacesAndNewlines),
            actionSignature
        ].joined(separator: "::")
    }

    private var hasWritePermission: Bool {
        permissions.contains { $0.permission == .writeActions && $0.granted }
    }

    private var customRules: [Rule] {
        guard let selectedAccountID else { return [] }
        let presetIDs = Set(presets.map { appScopedRuleID(accountID: selectedAccountID, presetID: $0.id) })
        return appRules
            .filter { $0.accountID == selectedAccountID && presetIDs.contains($0.id) == false }
            .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
    }

    private var eventTypeSuggestions: [String] {
        Array(Set((presets + appRules).map(\.eventType))).sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func actionDefinition(for actionID: String) -> PackagedPluginAction? {
        availableActions.first { $0.id == actionID }
    }

    private func actionSafetyLevel(for action: RuleActionDefinition) -> ActionSafetyLevel {
        ActionRunner.safetyLevel(for: action.action, declaredActions: availableActions)
    }

    private func load(_ rule: Rule) {
        editingRuleID = rule.id
        draftName = rule.name
        draftEventType = rule.eventType
        draftConditions = rule.conditions.isEmpty ? [CustomRuleConditionDraft()] : rule.conditions.map(CustomRuleConditionDraft.init)
        draftActions = rule.actions.isEmpty ? [CustomRuleActionDraft()] : rule.actions.map(CustomRuleActionDraft.init)
        requestPreviewResult = nil
        requestPreviewError = nil
        requestPreviewSignature = nil
    }

    private func resetDraft() {
        editingRuleID = nil
        draftName = ""
        draftEventType = eventTypeSuggestions.first ?? ""
        draftConditions = [CustomRuleConditionDraft(field: "severity", operation: .matchesSeverity, value: Severity.warning.rawValue)]
        draftActions = [
            CustomRuleActionDraft(action: "status.inbox.add"),
            CustomRuleActionDraft(action: "notification.show", value: "{{event.title}}")
        ]
        requestPreviewResult = nil
        requestPreviewError = nil
        requestPreviewSignature = nil
    }

    private func runRequestPreview() {
        guard isPreviewingRequest == false else { return }
        isPreviewingRequest = true
        requestPreviewResult = nil
        requestPreviewError = nil
        requestPreviewSignature = nil
        let eventType = draftEventType
        let actions = draftRuleActions
        let signature = currentRequestPreviewSignature

        Task { @MainActor in
            defer { isPreviewingRequest = false }
            do {
                requestPreviewResult = try await previewRuleActions(eventType, actions)
                requestPreviewSignature = signature
            } catch {
                requestPreviewError = error.localizedDescription
            }
        }
    }

    private func appScopedRuleID(accountID: String, presetID: String) -> String {
        let rawID = "rule_app_\(plugin.id)_\(accountID)_\(presetID)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return rawID
            .lowercased()
            .map { character in
                String(character).rangeOfCharacter(from: allowed) == nil ? "_" : String(character)
            }
            .joined()
    }
}

private struct ProviderActionRequestPreviewPanel: View {
    let isPreviewing: Bool
    let result: String?
    let error: String?
    let requiresCurrentPreview: Bool
    let preview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Request preview", systemImage: "doc.text.magnifyingglass")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    preview()
                } label: {
                    if isPreviewing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Preview", systemImage: "eye")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isPreviewing)
            }
            if requiresCurrentPreview {
                Text("Preview the current provider request before saving this rule.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let result, result.isEmpty == false {
                Text(result)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CustomRuleConditionDraft: Identifiable, Equatable {
    var id = UUID()
    var field: String = "severity"
    var operation: RuleOperator = .matchesSeverity
    var value: String = Severity.warning.rawValue

    init() {}

    init(field: String, operation: RuleOperator, value: String) {
        self.field = field
        self.operation = operation
        self.value = value
    }

    init(condition: RuleCondition) {
        field = condition.field
        operation = condition.operation
        switch condition.value {
        case .string(let value):
            self.value = value
        case .number(let value):
            self.value = String(value)
        case .bool(let value):
            self.value = value ? "true" : "false"
        case .null, nil:
            self.value = ""
        }
    }

    var isValid: Bool {
        let trimmedField = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedField.isEmpty == false else { return false }
        guard requiresValue else { return true }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else { return false }
        if operation == .greaterThan || operation == .lessThan {
            return Double(trimmedValue) != nil
        }
        if operation == .matchesSeverity {
            return Severity(rawValue: trimmedValue) != nil
        }
        return true
    }

    var ruleCondition: RuleCondition? {
        guard isValid else { return nil }
        let trimmedField = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requiresValue else {
            return RuleCondition(field: trimmedField, operation: operation)
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if operation == .greaterThan || operation == .lessThan, let number = Double(trimmedValue) {
            return RuleCondition(field: trimmedField, operation: operation, value: .number(number))
        }
        return RuleCondition(field: trimmedField, operation: operation, value: .string(trimmedValue))
    }

    var requiresValue: Bool {
        operation != .isEmpty && operation != .isNotEmpty
    }
}

private struct CustomRuleActionDraft: Identifiable, Equatable {
    var id = UUID()
    var action: String = "notification.show"
    var value: String = ""
    var parameters: [String: String] = [:]

    init() {}

    init(action: String, value: String = "") {
        self.action = action
        self.value = value
    }

    init(action definition: RuleActionDefinition) {
        action = definition.action
        parameters = definition.parameters
        switch definition.action {
        case "notification.show":
            value = definition.parameters["title"] ?? ""
        case "status.open_url":
            value = definition.parameters["url"] ?? ""
        case "audit.note":
            value = definition.parameters["note"] ?? ""
        case "webhook.post":
            value = definition.parameters["url"] ?? ""
        default:
            value = ""
        }
    }

    func isValid(actionDefinition: PackagedPluginAction?) -> Bool {
        if let actionDefinition {
            return actionDefinition.inputSchema?.fields.allSatisfy { field in
                guard field.required else { return true }
                return parameters[field.key, default: field.defaultValue ?? ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            } ?? true
        }
        guard Self.builtInActions.contains(action) else { return false }
        if requiresValue {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return true
    }

    func ruleAction(actionDefinition: PackagedPluginAction?) -> RuleActionDefinition? {
        guard isValid(actionDefinition: actionDefinition) else { return nil }
        if let actionDefinition {
            let schemaFields = actionDefinition.inputSchema?.fields ?? []
            var actionParameters: [String: String] = [:]
            for field in schemaFields {
                let value = parameters[field.key, default: field.defaultValue ?? ""].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty == false {
                    actionParameters[field.key] = value
                }
            }
            return RuleActionDefinition(action: actionDefinition.id, parameters: actionParameters)
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case "notification.show":
            return RuleActionDefinition(action: action, parameters: trimmedValue.isEmpty ? [:] : ["title": trimmedValue])
        case "status.open_url":
            return RuleActionDefinition(action: action, parameters: ["url": trimmedValue])
        case "audit.note":
            return RuleActionDefinition(action: action, parameters: ["note": trimmedValue])
        case "webhook.post":
            return RuleActionDefinition(action: action, parameters: ["url": trimmedValue])
        case "status.inbox.add":
            return RuleActionDefinition(action: action)
        default:
            return nil
        }
    }

    var requiresValue: Bool {
        action == "status.open_url" || action == "audit.note" || action == "webhook.post"
    }

    var parameterLabel: String {
        switch action {
        case "notification.show":
            "Notification title"
        case "status.open_url":
            "URL"
        case "audit.note":
            "Note"
        case "webhook.post":
            "Webhook URL"
        default:
            "Parameter"
        }
    }

    static let builtInActions = [
        "status.inbox.add",
        "notification.show",
        "status.open_url",
        "audit.note",
        "webhook.post"
    ]
}

private struct CustomRuleConditionDraftRow: View {
    @Binding var condition: CustomRuleConditionDraft
    let canDelete: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Field", selection: $condition.field) {
                    if Self.fields.contains(condition.field) == false {
                        Text(condition.field).tag(condition.field)
                    }
                    ForEach(Self.fields, id: \.self) { field in
                        Text(field).tag(field)
                    }
                }
                .pickerStyle(.menu)
                Picker("Operator", selection: $condition.operation) {
                    ForEach(RuleOperator.allCases, id: \.rawValue) { operation in
                        Text(operation.rawValue).tag(operation)
                    }
                }
                .pickerStyle(.menu)
                if canDelete {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            if condition.requiresValue {
                if condition.operation == .matchesSeverity {
                    Picker("Value", selection: $condition.value) {
                        ForEach(Severity.allCases, id: \.rawValue) { severity in
                            Text(severity.rawValue.capitalized).tag(severity.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    TextField("Value", text: $condition.value)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(8)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static let fields = [
        "severity",
        "title",
        "summary",
        "resourceName",
        "resourceID",
        "fingerprint",
        "actionURL"
    ]
}

private struct CustomRuleActionDraftRow: View {
    @Binding var action: CustomRuleActionDraft
    let availableActions: [PackagedPluginAction]
    let canDelete: Bool
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Action", selection: $action.action) {
                    ForEach(CustomRuleActionDraft.builtInActions, id: \.self) { action in
                        Text(action).tag(action)
                    }
                    ForEach(availableActions, id: \.id) { definition in
                        Text(definition.label).tag(definition.id)
                    }
                }
                .pickerStyle(.menu)
                if canDelete {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let definition = actionDefinition {
                if let description = definition.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(definition.inputSchema?.fields ?? [], id: \.key) { field in
                    PluginActionInputFieldRow(
                        field: field,
                        value: Binding(
                            get: { action.parameters[field.key, default: field.defaultValue ?? ""] },
                            set: { action.parameters[field.key] = $0 }
                        )
                    )
                }
            } else if action.action == "notification.show" || action.requiresValue {
                TextField(action.parameterLabel, text: $action.value)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(8)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionDefinition: PackagedPluginAction? {
        availableActions.first { $0.id == action.action }
    }
}

private struct PluginActionInputFieldRow: View {
    let field: PackagedPluginActionInputField
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if field.type == .select, field.options.isEmpty == false {
                Picker(field.label, selection: $value) {
                    ForEach(field.options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
            } else if field.type == .toggle {
                Toggle(field.label, isOn: Binding(
                    get: { value == "true" },
                    set: { value = $0 ? "true" : "false" }
                ))
            } else {
                TextField(field.placeholder ?? field.label, text: $value)
                    .textFieldStyle(.roundedBorder)
            }
            if let help = field.help {
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RuleReviewPreview: View {
    let ruleName: String
    let actions: [RuleActionDefinition]
    let hasWritePermission: Bool
    var actionSafetyLevel: (RuleActionDefinition) -> ActionSafetyLevel = {
        ActionRunner.safetyLevel(for: $0.action)
    }

    var body: some View {
        if reviewRequiredActions.isEmpty == false {
            VStack(alignment: .leading, spacing: 4) {
                Label("Review required", systemImage: "exclamationmark.triangle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(hasWritePermission ? Color.secondary : Color.orange)
                Text(permissionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(auditPreview)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.statusSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var reviewRequiredActions: [RuleActionDefinition] {
        actions.filter { actionSafetyLevel($0) == .reviewRequired }
    }

    private var permissionText: String {
        let actionList = reviewRequiredActions.map(\.action).joined(separator: ", ")
        if hasWritePermission {
            return "Write actions permission is granted for \(actionList)."
        }
        return "Grant Write actions permission before enabling \(actionList)."
    }

    private var auditPreview: String {
        let actionList = reviewRequiredActions.map(\.action).joined(separator: ", ")
        return "Audit preview: Status records action runs and audit entries when \(ruleName) runs \(actionList) for a matching event."
    }
}

private struct CustomAppRuleRow: View {
    let rule: Rule
    let isSaving: Bool
    let setEnabled: (Bool) -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                isOn: Binding(
                    get: { rule.enabled },
                    set: { setEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name)
                        .font(.caption)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button {
                    edit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    delete()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)
            }
        }
        .padding(10)
        .background(Color.statusBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var detail: String {
        let actionNames = rule.actions.map(\.action).joined(separator: ", ")
        return "\(rule.eventType) - \(rule.conditions.count) condition\(rule.conditions.count == 1 ? "" : "s") - \(actionNames)"
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
                            Link(destination: actionURL) {
                                Image(systemName: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)
                            .help("Open source")
                            .accessibilityLabel(Text("Open \(resource.name)"))
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
                Link(destination: actionURL) {
                    Label("Open source", systemImage: "arrow.up.right")
                }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 6) {
                ForEach(fields, id: \.key) { field in
                    ResourceFieldValue(field: field.key, value: field.value)
                }
            }
        }
    }

    private var resolvedFields: [(key: String, value: String)] {
        PluginResourceFieldResolver.resolvedFields(for: view, resource: resource)
    }
}

enum PluginResourceFieldResolver {
    static func resolvedFields(for view: PackagedPluginView, resource: Resource) -> [(key: String, value: String)] {
        let keys = view.fields.isEmpty ? Array(resource.fields.keys).sorted() : view.fields
        return keys.compactMap { key in
            guard let value = fieldValue(for: key, resource: resource), value.isEmpty == false else {
                return nil
            }
            return (key, value)
        }
    }

    private static func fieldValue(for key: String, resource: Resource) -> String? {
        if let value = resource.fields[key] {
            return value
        }
        switch key {
        case "name":
            return resource.name
        case "type", "resourceType":
            return resource.type
        case "actionUrl":
            return resource.actionURL?.absoluteString
        default:
            return nil
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
                Text("New app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "App",
                    selection: Binding(
                        get: { selectedAccountID ?? accounts.first?.id ?? "" },
                        set: { select($0) }
                    )
                ) {
                    ForEach(accounts) { account in
                        Text(account.accountName).tag(account.id)
                    }
                    if let selectedAccountID, selectedAccountID.hasPrefix("__new__:") {
                        Text("New app").tag(selectedAccountID)
                    }
                }
                .pickerStyle(.menu)
            }
            Button {
                addAccount()
            } label: {
                Label("Add app", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct PluginPermissionToggle: View {
    let permission: InstalledPluginPermission
    let isRequiredForRefresh: Bool
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(permission.permission.label)
                        .font(.caption)
                    if isRequiredForRefresh {
                        Text("Required to refresh")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(permission.permission.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(isSaving)
    }
}

private struct PluginOAuthConnectionPanel: View {
    @Environment(\.openURL) private var openURL

    let plugin: InstalledPlugin
    let authorizationURL: URL?
    let error: String?
    let connect: () -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OAuth")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                if let url = connect() {
                    openURL(url)
                }
            } label: {
                Label("Connect account", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.bordered)
            if let authorizationURL {
                Link("Open authorization page", destination: authorizationURL)
                    .font(.caption)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(plugin.name) OAuth connection")
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

    var usesOAuth: Bool {
        auth?.type == .oauth2
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

private extension URL {
    func queryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
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
    public var brand: IntegrationBrand?

    public init(systemImage: String, color: Color, brand: IntegrationBrand? = nil) {
        self.systemImage = systemImage
        self.color = color
        self.brand = brand
    }

    public static func visual(for provider: String, icon: String? = nil, accentColor: String? = nil) -> IntegrationVisual {
        let fallback = fallbackVisual(for: provider)
        return IntegrationVisual(
            systemImage: normalizedSystemImage(icon) ?? fallback.systemImage,
            color: Color.statusHex(accentColor) ?? fallback.color,
            brand: fallback.brand
        )
    }

    private static func fallbackVisual(for provider: String) -> IntegrationVisual {
        let key = provider.lowercased()
        if key.contains("github") {
            return IntegrationVisual(systemImage: "chevron.left.forwardslash.chevron.right", color: .primary, brand: .github)
        }
        if key.contains("gitlab") {
            return IntegrationVisual(systemImage: "shippingbox", color: Color(red: 0.99, green: 0.43, blue: 0.15))
        }
        if key.contains("appstore") {
            return IntegrationVisual(systemImage: "app.badge", color: .blue, brand: .appStoreConnect)
        }
        if key.contains("website") || key.contains("uptime") {
            return IntegrationVisual(systemImage: "globe", color: .green)
        }
        if key.contains("jira") || key.contains("atlassian") {
            return IntegrationVisual(systemImage: "diamond", color: .cyan)
        }
        return IntegrationVisual(systemImage: "puzzlepiece.extension", color: .orange)
    }

    private static func normalizedSystemImage(_ icon: String?) -> String? {
        guard let icon = icon?.trimmingCharacters(in: .whitespacesAndNewlines), icon.isEmpty == false else {
            return nil
        }
        if icon.hasPrefix("sf:") {
            return String(icon.dropFirst(3))
        }
        if icon.contains("/") {
            return nil
        }
        return icon
    }
}

#if canImport(WebKit)
private struct PackagedSVGIcon: View {
    let asset: PackagedPluginIconAsset

    var body: some View {
        PackagedSVGWebView(svgText: asset.svgText)
    }
}

#if os(macOS)
private struct PackagedSVGWebView: NSViewRepresentable {
    let svgText: String

    @MainActor
    func makeNSView(context: Context) -> WKWebView {
        let view = macOSWebView()
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    @MainActor
    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html(svgText), baseURL: nil)
    }
}

@MainActor
private func macOSWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.suppressesIncrementalRendering = true
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.setValue(false, forKey: "drawsBackground")
    return view
}
#else
private struct PackagedSVGWebView: UIViewRepresentable {
    let svgText: String

    @MainActor
    func makeUIView(context: Context) -> WKWebView {
        iOSWebView()
    }

    @MainActor
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html(svgText), baseURL: nil)
    }
}

@MainActor
private func iOSWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.suppressesIncrementalRendering = true
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.isOpaque = false
    view.scrollView.isScrollEnabled = false
    view.scrollView.backgroundColor = .clear
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    return view
}
#endif

private func html(_ svgText: String) -> String {
    """
    <!doctype html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
    body { display: flex; align-items: center; justify-content: center; }
    svg { display: block; max-width: 100%; max-height: 100%; }
    </style>
    </head>
    <body>\(svgText)</body>
    </html>
    """
}
#else
private struct PackagedSVGIcon: View {
    let asset: PackagedPluginIconAsset

    var body: some View {
        Image(systemName: "puzzlepiece.extension")
    }
}
#endif

public enum IntegrationBrand: Equatable {
    case github
    case appStoreConnect
}

public struct IntegrationIcon: View {
    private let visual: IntegrationVisual
    private let iconAsset: PackagedPluginIconAsset?
    private let size: CGFloat

    public init(
        provider: String,
        icon: String? = nil,
        iconAsset: PackagedPluginIconAsset? = nil,
        accentColor: String? = nil,
        size: CGFloat = 28
    ) {
        self.visual = IntegrationVisual.visual(for: provider, icon: icon, accentColor: accentColor)
        self.iconAsset = iconAsset
        self.size = size
    }

    public var body: some View {
        iconContent
            .frame(width: size, height: size)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: min(8, size * 0.25)))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let iconAsset {
            PackagedSVGIcon(asset: iconAsset)
                .padding(size * 0.16)
        } else {
            switch visual.brand {
            case .github:
                GitHubBrandMark()
                    .foregroundStyle(Color.white)
                    .padding(size * 0.18)
            case .appStoreConnect:
                AppStoreConnectBrandMark()
                    .foregroundStyle(Color.white)
                    .padding(size * 0.17)
            case nil:
                Image(systemName: visual.systemImage)
                    .font(.system(size: max(12, size * 0.48), weight: .semibold))
                    .foregroundStyle(visual.color)
            }
        }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        switch visual.brand {
        case .github:
            RoundedRectangle(cornerRadius: min(8, size * 0.25))
                .fill(Color(red: 0.09, green: 0.10, blue: 0.12))
        case .appStoreConnect:
            RoundedRectangle(cornerRadius: min(8, size * 0.25))
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.48, blue: 1.0),
                            Color(red: 0.32, green: 0.73, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case nil:
            RoundedRectangle(cornerRadius: min(8, size * 0.25))
                .fill(visual.color.opacity(0.12))
        }
    }
}

private extension Color {
    static func statusHex(_ value: String?) -> Color? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, let integer = Int(hex, radix: 16) else {
            return nil
        }
        let red = Double((integer >> 16) & 0xff) / 255
        let green = Double((integer >> 8) & 0xff) / 255
        let blue = Double(integer & 0xff) / 255
        return Color(red: red, green: green, blue: blue)
    }
}

private struct GitHubBrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                GitHubEarShape()
                    .frame(width: side * 0.28, height: side * 0.25)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -side * 0.22, y: -side * 0.22)
                GitHubEarShape()
                    .frame(width: side * 0.28, height: side * 0.25)
                    .rotationEffect(.degrees(18))
                    .offset(x: side * 0.22, y: -side * 0.22)
                Circle()
                    .frame(width: side * 0.74, height: side * 0.74)
                    .offset(y: -side * 0.04)
                RoundedRectangle(cornerRadius: side * 0.12)
                    .frame(width: side * 0.46, height: side * 0.24)
                    .offset(y: side * 0.30)
                Circle()
                    .fill(Color(red: 0.09, green: 0.10, blue: 0.12))
                    .frame(width: side * 0.08, height: side * 0.08)
                    .offset(x: -side * 0.15, y: -side * 0.05)
                Circle()
                    .fill(Color(red: 0.09, green: 0.10, blue: 0.12))
                    .frame(width: side * 0.08, height: side * 0.08)
                    .offset(x: side * 0.15, y: -side * 0.05)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct GitHubEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.82))
        path.closeSubpath()
        return path
    }
}

private struct AppStoreConnectBrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Capsule()
                    .frame(width: side * 0.18, height: side * 0.78)
                    .rotationEffect(.degrees(28))
                    .offset(x: -side * 0.12)
                Capsule()
                    .frame(width: side * 0.18, height: side * 0.78)
                    .rotationEffect(.degrees(-28))
                    .offset(x: side * 0.12)
                Capsule()
                    .frame(width: side * 0.70, height: side * 0.16)
                    .offset(y: side * 0.20)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
                IntegrationIcon(provider: plugin.id, icon: plugin.icon, accentColor: plugin.accentColor, size: 32)
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
                    if let externalURL = plugin.author.externalUrl {
                        Link("By \(plugin.author.name)", destination: externalURL)
                            .font(.caption)
                    } else {
                        Text("By \(plugin.author.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
