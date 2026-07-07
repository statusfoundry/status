import StatusCore
import SwiftUI

public struct AlertsView: View {
    private let items: [StatusItem]

    public init(items: [StatusItem]) {
        self.items = items
    }

    public var body: some View {
        StatusListPage(title: "Alerts", subtitle: "\(items.count) open attention item\(items.count == 1 ? "" : "s").") {
            if items.isEmpty {
                EmptyState(title: "No alerts", detail: "Status has no open warning or critical items on this device.")
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        StatusRow(severity: item.severity, title: item.title, detail: item.summary) {
                            if let link = item.actionLink {
                                Link(link.label, destination: link.url)
                                    .font(.callout.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
    }
}

public struct RulesListView: View {
    private let rules: [Rule]

    public init(rules: [Rule]) {
        self.rules = rules
    }

    public var body: some View {
        StatusListPage(title: "Rules", subtitle: "\(rules.count) local automation rule\(rules.count == 1 ? "" : "s").") {
            if rules.isEmpty {
                EmptyState(title: "No rules", detail: "Suggested plugin rules appear here after plugin install and stay disabled until the user enables them.")
            } else {
                VStack(spacing: 10) {
                    ForEach(rules) { rule in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(rule.name)
                                    .font(.headline)
                                Spacer(minLength: 12)
                                Text(rule.enabled ? "Enabled" : "Disabled")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .foregroundStyle(rule.enabled ? .green : .orange)
                                    .background((rule.enabled ? Color.green : Color.orange).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text(rule.eventType)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            RuleDetailLine(label: "Conditions", value: "\(rule.conditions.count)")
                            RuleDetailLine(label: "Actions", value: rule.actions.map(\.action).joined(separator: ", "))
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

public struct StatusSettingsView: View {
    private let registryURL: URL
    private let databasePath: String
    private let pluginInstallPath: String
    private let runtimeAction: RuntimeAction?

    public init(registryURL: URL, databasePath: String, pluginInstallPath: String, runtimeAction: RuntimeAction? = nil) {
        self.registryURL = registryURL
        self.databasePath = databasePath
        self.pluginInstallPath = pluginInstallPath
        self.runtimeAction = runtimeAction
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
        }
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

private extension Color {
    static let statusBackground = Color(red: 0.965, green: 0.965, blue: 0.945)
    static let statusSurface = Color.white.opacity(0.92)
}
