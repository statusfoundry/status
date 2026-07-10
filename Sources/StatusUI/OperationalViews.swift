import StatusCore
import SwiftUI

@MainActor
public final class RulesViewModel: ObservableObject {
    @Published public private(set) var rules: [Rule]
    @Published public private(set) var actionOptions: [CrossAppRuleActionOption]
    @Published public private(set) var loadError: String?

    private let loadRules: () throws -> [Rule]
    private let loadActionOptions: () throws -> [CrossAppRuleActionOption]
    private let saveRule: (Rule) throws -> Void
    private let deleteRule: (Rule) throws -> Void

    public init(
        initialRules: [Rule] = [],
        initialActionOptions: [CrossAppRuleActionOption] = CrossAppRuleActionOption.builtIn,
        loadRules: @escaping () throws -> [Rule],
        loadActionOptions: @escaping () throws -> [CrossAppRuleActionOption] = { CrossAppRuleActionOption.builtIn },
        saveRule: @escaping (Rule) throws -> Void,
        deleteRule: @escaping (Rule) throws -> Void = { _ in }
    ) {
        self.rules = initialRules
        self.actionOptions = initialActionOptions
        self.loadRules = loadRules
        self.loadActionOptions = loadActionOptions
        self.saveRule = saveRule
        self.deleteRule = deleteRule
    }

    public func reload() {
        do {
            rules = try loadRules()
            actionOptions = try loadActionOptions()
            loadError = nil
        } catch {
            rules = []
            actionOptions = CrossAppRuleActionOption.builtIn
            loadError = error.localizedDescription
        }
    }

    public func setEnabled(_ enabled: Bool, for rule: Rule) {
        var updated = rule
        updated.enabled = enabled
        do {
            try saveRule(updated)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func saveCrossAppRule(
        existingRuleID: String?,
        name: String,
        provider: String?,
        eventType: String,
        conditions: [RuleCondition],
        actions: [RuleActionDefinition],
        enabled: Bool
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEventType = eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProvider = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else {
            loadError = "Rule name is required."
            return
        }
        guard trimmedEventType.isEmpty == false else {
            loadError = "Event type is required."
            return
        }
        guard actions.isEmpty == false else {
            loadError = "Add at least one action."
            return
        }

        let rule = Rule(
            id: existingRuleID ?? Self.crossAppRuleID(name: trimmedName),
            name: trimmedName,
            enabled: enabled,
            scope: .crossApp,
            accountID: nil,
            provider: trimmedProvider?.isEmpty == false ? trimmedProvider : nil,
            eventType: trimmedEventType,
            conditions: conditions,
            actions: actions
        )
        do {
            try saveRule(rule)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    public func delete(_ rule: Rule) {
        do {
            try deleteRule(rule)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private static func crossAppRuleID(name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "rule_cross_app_\(slug.isEmpty ? UUID().uuidString.lowercased() : slug)"
    }
}

public struct RulesContainerView: View {
    @StateObject private var viewModel: RulesViewModel

    public init(viewModel: @autoclosure @escaping () -> RulesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        RulesListView(
            rules: viewModel.rules,
            setRuleEnabled: { rule, enabled in
                viewModel.setEnabled(enabled, for: rule)
            },
            saveRule: { existingRuleID, name, provider, eventType, conditions, actions, enabled in
                viewModel.saveCrossAppRule(
                    existingRuleID: existingRuleID,
                    name: name,
                    provider: provider,
                    eventType: eventType,
                    conditions: conditions,
                    actions: actions,
                    enabled: enabled
                )
            },
            deleteRule: { rule in
                viewModel.delete(rule)
            },
            actionOptions: viewModel.actionOptions
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
            viewModel.reload()
        }
        .refreshable {
            viewModel.reload()
        }
    }
}

public struct CrossAppRuleActionOption: Identifiable, Equatable, Sendable {
    public var id: String { action }
    public var action: String
    public var label: String
    public var provider: String?
    public var inputFields: [PackagedPluginActionInputField]
    public var safety: ActionSafetyLevel

    public init(
        action: String,
        label: String,
        provider: String? = nil,
        inputFields: [PackagedPluginActionInputField] = [],
        safety: ActionSafetyLevel = .safe
    ) {
        self.action = action
        self.label = label
        self.provider = provider
        self.inputFields = inputFields
        self.safety = safety
    }

    public static let builtIn = [
        CrossAppRuleActionOption(action: "status.inbox.add", label: "Add to Status inbox"),
        CrossAppRuleActionOption(action: "notification.show", label: "Show notification", inputFields: [
            PackagedPluginActionInputField(key: "title", label: "Title", type: .template, defaultValue: "{{event.title}}")
        ]),
        CrossAppRuleActionOption(action: "status.open_url", label: "Open URL", inputFields: [
            PackagedPluginActionInputField(key: "url", label: "URL", type: .template, required: true, defaultValue: "{{event.actionUrl}}")
        ]),
        CrossAppRuleActionOption(action: "audit.note", label: "Record audit note", inputFields: [
            PackagedPluginActionInputField(key: "note", label: "Note", type: .template, defaultValue: "{{event.summary}}")
        ]),
        CrossAppRuleActionOption(action: "webhook.post", label: "Send webhook", inputFields: [
            PackagedPluginActionInputField(key: "url", label: "Webhook URL", type: .template, required: true, defaultValue: "https://example.com/hooks/status"),
            PackagedPluginActionInputField(key: "summary", label: "Summary", type: .template, defaultValue: "{{event.summary}}")
        ], safety: .reviewRequired)
    ]
}

public struct AlertsView: View {
    private let items: [StatusItem]
    private let resolve: (StatusItem) -> Void
    private let snooze: (StatusItem) -> Void
    private let dismiss: (StatusItem) -> Void

    public init(
        items: [StatusItem],
        resolve: @escaping (StatusItem) -> Void = { _ in },
        snooze: @escaping (StatusItem) -> Void = { _ in },
        dismiss: @escaping (StatusItem) -> Void = { _ in }
    ) {
        self.items = items
        self.resolve = resolve
        self.snooze = snooze
        self.dismiss = dismiss
    }

    public var body: some View {
        StatusListPage(title: "Alerts", subtitle: "\(items.count) active attention item\(items.count == 1 ? "" : "s").") {
            if items.isEmpty {
                EmptyState(title: "No alerts", detail: "Status has no open warning or critical items on this device.")
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        StatusRow(severity: item.severity, title: item.title, detail: item.summary) {
                            AlertRowActions(
                                item: item,
                                resolve: resolve,
                                snooze: snooze,
                                dismiss: dismiss
                            )
                        }
                    }
                }
            }
        }
    }
}

@MainActor
public final class AlertsViewModel: ObservableObject {
    @Published public private(set) var items: [StatusItem]
    @Published public private(set) var loadError: String?

    private let loadItems: () throws -> [StatusItem]
    private let resolveItem: (StatusItem) throws -> Void
    private let snoozeItem: (StatusItem) throws -> Void
    private let dismissItem: (StatusItem) throws -> Void

    public init(
        initialItems: [StatusItem] = [],
        loadItems: @escaping () throws -> [StatusItem],
        resolveItem: @escaping (StatusItem) throws -> Void = { _ in },
        snoozeItem: @escaping (StatusItem) throws -> Void = { _ in },
        dismissItem: @escaping (StatusItem) throws -> Void = { _ in }
    ) {
        self.items = initialItems
        self.loadItems = loadItems
        self.resolveItem = resolveItem
        self.snoozeItem = snoozeItem
        self.dismissItem = dismissItem
    }

    public func reload() {
        do {
            items = try loadItems()
            loadError = nil
        } catch {
            items = []
            loadError = error.localizedDescription
        }
    }

    public func resolve(_ item: StatusItem) {
        mutate(item, action: resolveItem)
    }

    public func snooze(_ item: StatusItem) {
        mutate(item, action: snoozeItem)
    }

    public func dismiss(_ item: StatusItem) {
        mutate(item, action: dismissItem)
    }

    private func mutate(_ item: StatusItem, action: (StatusItem) throws -> Void) {
        do {
            try action(item)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

public struct AlertsContainerView: View {
    @StateObject private var viewModel: AlertsViewModel

    public init(viewModel: @autoclosure @escaping () -> AlertsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        AlertsView(
            items: viewModel.items,
            resolve: { item in viewModel.resolve(item) },
            snooze: { item in viewModel.snooze(item) },
            dismiss: { item in viewModel.dismiss(item) }
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
                viewModel.reload()
            }
            .refreshable {
                viewModel.reload()
            }
    }
}

private struct AlertRowActions: View {
    let item: StatusItem
    let resolve: (StatusItem) -> Void
    let snooze: (StatusItem) -> Void
    let dismiss: (StatusItem) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let link = item.actionLink {
                Link(link.label, destination: link.url)
                    .font(.callout.weight(.semibold))
            }
            if item.state == .snoozed, let snoozeUntil = item.snoozeUntil {
                Text("Snoozed until \(snoozeUntil.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                IconActionButton(
                    title: "Resolve",
                    systemImage: "checkmark.circle",
                    action: { resolve(item) }
                )
                IconActionButton(
                    title: "Snooze one hour",
                    systemImage: "clock",
                    action: { snooze(item) }
                )
                IconActionButton(
                    title: "Dismiss",
                    systemImage: "xmark.circle",
                    role: .destructive,
                    action: { dismiss(item) }
                )
            }
        }
    }
}

private struct IconActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(Text(title))
    }
}

public struct RulesListView: View {
    private let rules: [Rule]
    private let setRuleEnabled: ((Rule, Bool) -> Void)?
    private let saveRule: ((String?, String, String?, String, [RuleCondition], [RuleActionDefinition], Bool) -> Void)?
    private let deleteRule: ((Rule) -> Void)?
    private let actionOptions: [CrossAppRuleActionOption]
    @State private var editingRuleID: String?
    @State private var draftName = ""
    @State private var draftProvider = ""
    @State private var draftEventType = ""
    @State private var draftEnabled = false
    @State private var draftCondition = CrossAppRuleConditionDraft()
    @State private var draftActions = [
        CrossAppRuleActionDraft(action: "status.inbox.add"),
        CrossAppRuleActionDraft(action: "notification.show", value: "{{event.title}}")
    ]

    public init(
        rules: [Rule],
        setRuleEnabled: ((Rule, Bool) -> Void)? = nil,
        saveRule: ((String?, String, String?, String, [RuleCondition], [RuleActionDefinition], Bool) -> Void)? = nil,
        deleteRule: ((Rule) -> Void)? = nil,
        actionOptions: [CrossAppRuleActionOption] = CrossAppRuleActionOption.builtIn
    ) {
        self.rules = rules
        self.setRuleEnabled = setRuleEnabled
        self.saveRule = saveRule
        self.deleteRule = deleteRule
        self.actionOptions = actionOptions
    }

    public var body: some View {
        StatusListPage(title: "Cross-App Rules", subtitle: "\(rules.count) cross-app automation rule\(rules.count == 1 ? "" : "s").") {
            VStack(alignment: .leading, spacing: 14) {
                if rules.isEmpty {
                    EmptyState(title: "No cross-app rules", detail: "App-specific rules live in each app's settings. Only rules linking multiple apps appear here.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(rules) { rule in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(rule.name)
                                        .font(.headline)
                                    Spacer(minLength: 12)
                                    RuleEnabledControl(rule: rule, setRuleEnabled: setRuleEnabled)
                                }
                                Text(rule.eventType)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                RuleDetailLine(label: "Source", value: rule.provider ?? "Any app")
                                RuleDetailLine(label: "Conditions", value: rule.conditions.map(conditionSummary).joined(separator: ", "))
                                RuleDetailLine(label: "Actions", value: rule.actions.map(\.action).joined(separator: ", "))
                                if saveRule != nil || deleteRule != nil {
                                    HStack(spacing: 8) {
                                        if saveRule != nil {
                                            Button {
                                                load(rule)
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        if let deleteRule {
                                            Button(role: .destructive) {
                                                deleteRule(rule)
                                                if editingRuleID == rule.id {
                                                    resetDraft()
                                                }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.statusSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                if saveRule != nil {
                    CrossAppRuleEditor(
                        editingRuleID: editingRuleID,
                        draftName: $draftName,
                        draftProvider: $draftProvider,
                        draftEventType: $draftEventType,
                        draftEnabled: $draftEnabled,
                        draftCondition: $draftCondition,
                        draftActions: $draftActions,
                        actionOptions: actionOptions,
                        save: saveDraft,
                        cancel: resetDraft
                    )
                }
            }
        }
    }

    private var draftActionsForSave: [RuleActionDefinition] {
        draftActions.compactMap { $0.ruleAction(actionOptions: actionOptions) }
    }

    private var draftConditionsForSave: [RuleCondition] {
        draftCondition.ruleCondition.map { [$0] } ?? []
    }

    private func saveDraft() {
        saveRule?(
            editingRuleID,
            draftName,
            draftProvider,
            draftEventType,
            draftConditionsForSave,
            draftActionsForSave,
            draftEnabled
        )
        resetDraft()
    }

    private func load(_ rule: Rule) {
        editingRuleID = rule.id
        draftName = rule.name
        draftProvider = rule.provider ?? ""
        draftEventType = rule.eventType
        draftEnabled = rule.enabled
        draftCondition = rule.conditions.first.map(CrossAppRuleConditionDraft.init) ?? CrossAppRuleConditionDraft()
        draftActions = rule.actions.isEmpty ? [CrossAppRuleActionDraft()] : rule.actions.map(CrossAppRuleActionDraft.init)
    }

    private func resetDraft() {
        editingRuleID = nil
        draftName = ""
        draftProvider = ""
        draftEventType = ""
        draftEnabled = false
        draftCondition = CrossAppRuleConditionDraft()
        draftActions = [
            CrossAppRuleActionDraft(action: "status.inbox.add"),
            CrossAppRuleActionDraft(action: "notification.show", value: "{{event.title}}")
        ]
    }

    private func conditionSummary(_ condition: RuleCondition) -> String {
        guard let value = condition.value else {
            return "\(condition.field) \(condition.operation.rawValue)"
        }
        return "\(condition.field) \(condition.operation.rawValue) \(value.summary)"
    }
}

private struct RuleEnabledControl: View {
    let rule: Rule
    let setRuleEnabled: ((Rule, Bool) -> Void)?

    var body: some View {
        if let setRuleEnabled {
            Toggle(
                isOn: Binding(
                    get: { rule.enabled },
                    set: { setRuleEnabled(rule, $0) }
                )
            ) {
                Text(rule.enabled ? "Enabled" : "Disabled")
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(Text(rule.enabled ? "Enabled" : "Disabled"))
        } else {
            Text(rule.enabled ? "Enabled" : "Disabled")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(rule.enabled ? .green : .orange)
                .background((rule.enabled ? Color.green : Color.orange).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct CrossAppRuleEditor: View {
    let editingRuleID: String?
    @Binding var draftName: String
    @Binding var draftProvider: String
    @Binding var draftEventType: String
    @Binding var draftEnabled: Bool
    @Binding var draftCondition: CrossAppRuleConditionDraft
    @Binding var draftActions: [CrossAppRuleActionDraft]
    let actionOptions: [CrossAppRuleActionOption]
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(editingRuleID == nil ? "New cross-app rule" : "Edit cross-app rule")
                    .font(.headline)
                Spacer(minLength: 12)
                Toggle("Enabled", isOn: $draftEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Rule name", text: $draftName)
                TextField("Source app/plugin id, optional", text: $draftProvider)
                TextField("Event type, for example github.workflow.failed", text: $draftEventType)
            }
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Condition")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Picker("Field", selection: $draftCondition.field) {
                        ForEach(CrossAppRuleConditionDraft.fields, id: \.self) { field in
                            Text(field).tag(field)
                        }
                    }
                    Picker("Operation", selection: $draftCondition.operation) {
                        ForEach(CrossAppRuleConditionDraft.operators, id: \.self) { operation in
                            Text(operation.rawValue).tag(operation)
                        }
                    }
                    if draftCondition.requiresValue {
                        TextField("Value", text: $draftCondition.value)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button {
                        draftActions.append(CrossAppRuleActionDraft())
                    } label: {
                        Label("Add action", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                ForEach($draftActions) { $action in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Picker("Action", selection: $action.action) {
                                ForEach(actionOptions) { option in
                                    Text(option.provider.map { "\(option.label) (\($0))" } ?? option.label)
                                        .tag(option.action)
                                }
                            }
                            .onChange(of: action.action) { _, newAction in
                                action.applyDefaults(from: option(for: newAction))
                            }
                            Spacer(minLength: 8)
                            Button(role: .destructive) {
                                draftActions.removeAll { $0.id == action.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Remove action")
                            .accessibilityLabel(Text("Remove action"))
                        }
                        if let option = option(for: action.action) {
                            CrossAppRuleActionFields(action: $action, option: option)
                        }
                    }
                    .padding(10)
                    .background(Color.statusBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Audit preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("When this event matches, Status records the triggering event, rule id, action names, result, and any error in the local audit log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if draftActions.contains(where: { option(for: $0.action)?.safety == .reviewRequired }) {
                    Text("Review-required provider actions need the target plugin's write-actions permission before they can run.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    save()
                } label: {
                    Label(editingRuleID == nil ? "Add Rule" : "Update Rule", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)

                if editingRuleID != nil || draftName.isEmpty == false || draftEventType.isEmpty == false {
                    Button("Cancel", action: cancel)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var isSaveDisabled: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draftEventType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draftActions.compactMap { $0.ruleAction(actionOptions: actionOptions) }.isEmpty
    }

    private func option(for action: String) -> CrossAppRuleActionOption? {
        actionOptions.first { $0.action == action } ?? CrossAppRuleActionOption.builtIn.first { $0.action == action }
    }
}

private struct CrossAppRuleActionFields: View {
    @Binding var action: CrossAppRuleActionDraft
    let option: CrossAppRuleActionOption

    var body: some View {
        if option.inputFields.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(option.inputFields, id: \.key) { field in
                    TextField(field.placeholder ?? field.defaultValue ?? field.label, text: binding(for: field))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func binding(for field: PackagedPluginActionInputField) -> Binding<String> {
        Binding(
            get: { action.parameters[field.key] ?? field.defaultValue ?? "" },
            set: { action.parameters[field.key] = $0 }
        )
    }
}

private struct CrossAppRuleConditionDraft: Equatable {
    var field = "severity"
    var operation: RuleOperator = .matchesSeverity
    var value = Severity.warning.rawValue

    static let fields = ["severity", "provider", "resourceName", "title", "summary", "actionURL"]
    static let operators: [RuleOperator] = [.matchesSeverity, .equals, .contains, .startsWith, .endsWith, .isNotEmpty]

    init() {}

    init(condition: RuleCondition) {
        field = condition.field
        operation = condition.operation
        value = condition.value?.stringValue ?? ""
    }

    var requiresValue: Bool {
        operation != .isEmpty && operation != .isNotEmpty
    }

    var ruleCondition: RuleCondition? {
        let trimmedField = field.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedField.isEmpty == false else { return nil }
        if requiresValue == false {
            return RuleCondition(field: trimmedField, operation: operation)
        }
        guard trimmedValue.isEmpty == false else { return nil }
        return RuleCondition(field: trimmedField, operation: operation, value: .string(trimmedValue))
    }
}

private struct CrossAppRuleActionDraft: Identifiable, Equatable {
    let id: UUID
    var action: String
    var parameters: [String: String]

    init(id: UUID = UUID(), action: String = "notification.show", value: String = "{{event.title}}", parameters: [String: String]? = nil) {
        self.id = id
        self.action = action
        self.parameters = parameters ?? Self.defaultParameters(for: action, value: value)
    }

    init(action definition: RuleActionDefinition) {
        id = UUID()
        action = definition.action
        parameters = definition.parameters
    }

    mutating func applyDefaults(from option: CrossAppRuleActionOption?) {
        parameters = Dictionary(uniqueKeysWithValues: (option?.inputFields ?? [])
            .map { ($0.key, $0.defaultValue ?? "") })
    }

    func ruleAction(actionOptions: [CrossAppRuleActionOption]) -> RuleActionDefinition? {
        guard let option = actionOptions.first(where: { $0.action == action }) ?? CrossAppRuleActionOption.builtIn.first(where: { $0.action == action }) else {
            return nil
        }
        var cleaned = parameters
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.value.isEmpty == false }
        for field in option.inputFields where field.required {
            guard cleaned[field.key]?.isEmpty == false else { return nil }
        }
        if action == "status.inbox.add" {
            cleaned = [:]
        }
        return RuleActionDefinition(action: action, parameters: cleaned)
    }

    private static func defaultParameters(for action: String, value: String) -> [String: String] {
        switch action {
        case "status.inbox.add":
            return [:]
        case "notification.show":
            return ["title": value]
        case "status.open_url":
            return ["url": value]
        case "audit.note":
            return ["note": value]
        default:
            return [:]
        }
    }
}

private extension RuleValue {
    var summary: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value.formatted()
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            "null"
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value.formatted()
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            nil
        }
    }
}

public struct AuditLogView: View {
    private let entries: [AuditEntry]

    public init(entries: [AuditEntry]) {
        self.entries = entries
    }

    public var body: some View {
        StatusListPage(title: "Audit Log", subtitle: "\(entries.count) recent audit entr\(entries.count == 1 ? "y" : "ies").") {
            if entries.isEmpty {
                EmptyState(title: "No audit entries", detail: "Automation, action, and job decisions will be recorded here.")
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.title)
                                    .font(.headline)
                                Spacer(minLength: 12)
                                Text(entry.status)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .foregroundStyle(entry.statusColor)
                                    .background(entry.statusColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(entry.timestamp, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(entry.provenanceReferences, id: \.self) { reference in
                                Text(reference)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.statusSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

@MainActor
public final class AuditLogViewModel: ObservableObject {
    @Published public private(set) var entries: [AuditEntry]
    @Published public private(set) var loadError: String?

    private let loadEntries: () throws -> [AuditEntry]

    public init(initialEntries: [AuditEntry] = [], loadEntries: @escaping () throws -> [AuditEntry]) {
        self.entries = initialEntries
        self.loadEntries = loadEntries
    }

    public func reload() {
        do {
            entries = try loadEntries()
            loadError = nil
        } catch {
            entries = []
            loadError = error.localizedDescription
        }
    }
}

public struct AuditLogContainerView: View {
    @StateObject private var viewModel: AuditLogViewModel

    public init(viewModel: @autoclosure @escaping () -> AuditLogViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        AuditLogView(entries: viewModel.entries)
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
                viewModel.reload()
            }
            .refreshable {
                viewModel.reload()
            }
    }
}

public struct NotificationPreferencePluginGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var pluginID: String
    public var accountID: String?
    public var name: String
    public var events: [NotificationPreferenceEventRow]

    public init(id: String, pluginID: String? = nil, accountID: String? = nil, name: String, events: [NotificationPreferenceEventRow]) {
        self.id = id
        self.pluginID = pluginID ?? id
        self.accountID = accountID
        self.name = name
        self.events = events
    }
}

public struct NotificationPreferenceEventRow: Identifiable, Equatable, Sendable {
    public var id: String { type }
    public var type: String
    public var label: String
    public var defaultMode: NotificationMode

    public init(type: String, label: String, defaultMode: NotificationMode) {
        self.type = type
        self.label = label
        self.defaultMode = defaultMode
    }
}

@MainActor
public final class NotificationPreferencesViewModel: ObservableObject {
    @Published public private(set) var pluginGroups: [NotificationPreferencePluginGroup]
    @Published public private(set) var preferences: [NotificationPreference]
    @Published public private(set) var loadError: String?

    private let loadPluginGroups: () throws -> [NotificationPreferencePluginGroup]
    private let loadPreferences: () throws -> [NotificationPreference]
    private let setPreference: (String, String?, String?, NotificationMode?) throws -> Void

    public init(
        initialPluginGroups: [NotificationPreferencePluginGroup] = [],
        initialPreferences: [NotificationPreference] = [],
        loadPluginGroups: @escaping () throws -> [NotificationPreferencePluginGroup],
        loadPreferences: @escaping () throws -> [NotificationPreference],
        setPreference: @escaping (String, String?, String?, NotificationMode?) throws -> Void
    ) {
        self.pluginGroups = initialPluginGroups
        self.preferences = initialPreferences
        self.loadPluginGroups = loadPluginGroups
        self.loadPreferences = loadPreferences
        self.setPreference = setPreference
    }

    public func reload() {
        do {
            pluginGroups = try loadPluginGroups()
            preferences = try loadPreferences()
            loadError = nil
        } catch {
            pluginGroups = []
            preferences = []
            loadError = error.localizedDescription
        }
    }

    public func explicitMode(pluginID: String, accountID: String? = nil, eventType: String? = nil) -> NotificationMode? {
        preferences.first { preference in
            preference.pluginID == pluginID &&
            preference.accountID == accountID &&
            preference.eventType == eventType &&
            preference.scope == (eventType == nil ? (accountID == nil ? .plugin : .app) : .event)
        }?.mode
    }

    public func effectiveMode(pluginID: String, accountID: String? = nil, event: NotificationPreferenceEventRow) -> NotificationMode {
        explicitMode(pluginID: pluginID, accountID: accountID, eventType: event.type)
            ?? explicitMode(pluginID: pluginID, accountID: accountID)
            ?? explicitMode(pluginID: pluginID, eventType: event.type)
            ?? explicitMode(pluginID: pluginID)
            ?? event.defaultMode
    }

    public func setMode(_ mode: NotificationMode?, pluginID: String, accountID: String? = nil, eventType: String? = nil) {
        do {
            try setPreference(pluginID, accountID, eventType, mode)
            preferences = try loadPreferences()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

@MainActor
public final class NotificationHistoryViewModel: ObservableObject {
    @Published public private(set) var notifications: [NotificationRecord]
    @Published public private(set) var loadError: String?

    private let loadNotifications: () throws -> [NotificationRecord]

    public init(
        initialNotifications: [NotificationRecord] = [],
        loadNotifications: @escaping () throws -> [NotificationRecord]
    ) {
        self.notifications = initialNotifications
        self.loadNotifications = loadNotifications
    }

    public func reload() {
        do {
            notifications = try loadNotifications()
            loadError = nil
        } catch {
            notifications = []
            loadError = error.localizedDescription
        }
    }
}

public struct StatusSettingsView: View {
    private let registryURL: URL
    private let databasePath: String
    private let pluginInstallPath: String
    private let runtimeAction: RuntimeAction?
    @StateObject private var notificationPreferencesViewModel: NotificationPreferencesViewModel
    @StateObject private var notificationHistoryViewModel: NotificationHistoryViewModel

    public init(
        registryURL: URL,
        databasePath: String,
        pluginInstallPath: String,
        runtimeAction: RuntimeAction? = nil,
        notificationPreferencesViewModel: @autoclosure @escaping () -> NotificationPreferencesViewModel = NotificationPreferencesViewModel(
            loadPluginGroups: { [] },
            loadPreferences: { [] },
            setPreference: { _, _, _, _ in }
        ),
        notificationHistoryViewModel: @autoclosure @escaping () -> NotificationHistoryViewModel = NotificationHistoryViewModel(
            loadNotifications: { [] }
        )
    ) {
        self.registryURL = registryURL
        self.databasePath = databasePath
        self.pluginInstallPath = pluginInstallPath
        self.runtimeAction = runtimeAction
        _notificationPreferencesViewModel = StateObject(wrappedValue: notificationPreferencesViewModel())
        _notificationHistoryViewModel = StateObject(wrappedValue: notificationHistoryViewModel())
    }

    public var body: some View {
        StatusListPage(title: "Settings", subtitle: "Local-first runtime paths and hosted registry endpoints.") {
            VStack(spacing: 10) {
                SettingsRow(label: "Registry", value: registryURL.absoluteString)
                SettingsRow(label: "Database", value: databasePath)
                SettingsRow(label: "Plugin install root", value: pluginInstallPath)
                SettingsRow(label: "Automation default", value: "Suggested rules install disabled")
                SettingsRow(label: "Write actions", value: "Require explicit permission")
            }
            if let runtimeAction {
                RuntimeActionPanel(action: runtimeAction)
            }
            NotificationPreferencesPanel(viewModel: notificationPreferencesViewModel)
            NotificationHistoryPanel(viewModel: notificationHistoryViewModel)
        }
        .task {
            notificationPreferencesViewModel.reload()
            notificationHistoryViewModel.reload()
        }
        .refreshable {
            notificationPreferencesViewModel.reload()
            notificationHistoryViewModel.reload()
        }
    }
}

private struct NotificationPreferencesPanel: View {
    @ObservedObject var viewModel: NotificationPreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications")
                    .font(.headline)
                Text("App defaults and event overrides. Plugins suggest defaults; Status applies these choices before platform delivery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.pluginGroups.isEmpty {
                Text("No installed plugins expose notification-worthy events yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.pluginGroups) { group in
                        NotificationPreferencePluginCard(group: group, viewModel: viewModel)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotificationPreferencePluginCard: View {
    let group: NotificationPreferencePluginGroup
    @ObservedObject var viewModel: NotificationPreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                    Text(group.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                NotificationModeMenu(
                    title: viewModel.explicitMode(pluginID: group.pluginID, accountID: group.accountID)?.displayName ?? "Rule defaults",
                    inheritedTitle: "Use rule defaults",
                    selectedMode: viewModel.explicitMode(pluginID: group.pluginID, accountID: group.accountID),
                    setMode: { mode in
                        viewModel.setMode(mode, pluginID: group.pluginID, accountID: group.accountID)
                    }
                )
            }

            if group.events.isEmpty {
                Text("This plugin does not declare event-level notification defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(group.events) { event in
                        NotificationPreferenceEventControl(
                            pluginID: group.pluginID,
                            accountID: group.accountID,
                            event: event,
                            viewModel: viewModel
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct NotificationPreferenceEventControl: View {
    let pluginID: String
    let accountID: String?
    let event: NotificationPreferenceEventRow
    @ObservedObject var viewModel: NotificationPreferencesViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.label)
                    .font(.callout.weight(.semibold))
                Text("\(event.type) - effective \(viewModel.effectiveMode(pluginID: pluginID, accountID: accountID, event: event).displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            NotificationModeMenu(
                title: viewModel.explicitMode(pluginID: pluginID, accountID: accountID, eventType: event.type)?.displayName ?? "Inherit",
                inheritedTitle: accountID == nil ? "Inherit plugin/default" : "Inherit app/default",
                selectedMode: viewModel.explicitMode(pluginID: pluginID, accountID: accountID, eventType: event.type),
                setMode: { mode in
                    viewModel.setMode(mode, pluginID: pluginID, accountID: accountID, eventType: event.type)
                }
            )
        }
    }
}

private struct NotificationModeMenu: View {
    let title: String
    let inheritedTitle: String
    let selectedMode: NotificationMode?
    let setMode: (NotificationMode?) -> Void

    var body: some View {
        Menu {
            Button(inheritedTitle) {
                setMode(nil)
            }
            Divider()
            ForEach(NotificationMode.allCases, id: \.self) { mode in
                Button(mode.displayName) {
                    setMode(mode)
                }
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .help("Notification mode")
        .accessibilityLabel(Text(selectedMode?.displayName ?? title))
    }
}

private struct NotificationHistoryPanel: View {
    @ObservedObject var viewModel: NotificationHistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notification History")
                    .font(.headline)
                Text("Recent notification decisions stored by the automation pipeline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.notifications.isEmpty {
                Text("No notifications have been recorded on this device yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.notifications) { notification in
                        NotificationHistoryRow(notification: notification)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotificationHistoryRow: View {
    let notification: NotificationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(notification.title)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 12)
                Text(notification.mode.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(notification.mode.modeColor.opacity(0.12))
                    .foregroundStyle(notification.mode.modeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(notification.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(notification.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(notification.deliveryState)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                ForEach(notification.provenanceReferences, id: \.self) { reference in
                    Text(reference)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

public struct RuntimeAction: Sendable {
    public var title: String
    public var detail: String
    public var buttonTitle: String
    public var run: @Sendable () async throws -> String

    public init(
        title: String,
        detail: String,
        buttonTitle: String,
        run: @escaping @Sendable () async throws -> String
    ) {
        self.title = title
        self.detail = detail
        self.buttonTitle = buttonTitle
        self.run = run
    }
}

private struct RuntimeActionPanel: View {
    let action: RuntimeAction
    @State private var isRunning = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.title)
                        .font(.headline)
                    Text(action.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    Task {
                        await run()
                    }
                } label: {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(action.buttonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }

            if let result {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func run() async {
        isRunning = true
        result = nil
        error = nil
        defer { isRunning = false }

        do {
            result = try await action.run()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct StatusListPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 42, weight: .semibold))
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(Color.statusBackground)
    }
}

private struct StatusRow<Trailing: View>: View {
    let severity: Severity
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(severity.color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RuleDetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "None" : value)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }
}

private struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Severity {
    var color: Color {
        switch self {
        case .ok: .green
        case .notice: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

private extension AuditEntry {
    var statusColor: Color {
        switch status {
        case "success":
            .green
        case "failed", "denied":
            .red
        case "suppressed", "skipped", "unsupported":
            .orange
        default:
            .secondary
        }
    }

    var provenanceReferences: [String] {
        [
            jobID.map { "job \($0)" },
            eventID.map { "event \($0)" },
            actionRunID.map { "action \($0)" }
        ].compactMap { $0 }
    }
}

private extension NotificationMode {
    var displayName: String {
        switch self {
        case .immediate:
            "Immediate"
        case .digest:
            "Digest"
        case .dashboardOnly:
            "Dashboard only"
        case .silentAutomation:
            "Silent automation"
        case .disabled:
            "Disabled"
        }
    }

    var modeColor: Color {
        switch self {
        case .immediate:
            .blue
        case .digest:
            .purple
        case .dashboardOnly:
            .secondary
        case .silentAutomation:
            .orange
        case .disabled:
            .red
        }
    }
}

private extension NotificationRecord {
    var deliveryState: String {
        if let deliveredAt {
            return "Delivered \(deliveredAt.formatted(date: .omitted, time: .shortened))"
        }
        switch mode {
        case .immediate:
            return "Pending delivery"
        case .digest:
            return "Queued for digest"
        case .dashboardOnly:
            return "Dashboard only"
        case .silentAutomation:
            return "Silent"
        case .disabled:
            return "Suppressed"
        }
    }

    var provenanceReferences: [String] {
        [
            eventID.map { "event \($0)" },
            statusItemID.map { "item \($0)" }
        ].compactMap { $0 }
    }
}
