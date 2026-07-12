import StatusCore
import SwiftUI

public struct DashboardView: View {
    private let snapshot: DashboardSnapshot
    private let isRefreshingApps: Bool
    private let refreshResult: String?
    private let refreshError: String?
    private let refreshApps: (() async -> Void)?
    private let openApp: ((IntegrationSummary) -> Void)?

    public init(
        snapshot: DashboardSnapshot,
        isRefreshingApps: Bool = false,
        refreshResult: String? = nil,
        refreshError: String? = nil,
        refreshApps: (() async -> Void)? = nil,
        openApp: ((IntegrationSummary) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.isRefreshingApps = isRefreshingApps
        self.refreshResult = refreshResult
        self.refreshError = refreshError
        self.refreshApps = refreshApps
        self.openApp = openApp
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHeader(
                    snapshot: snapshot,
                    isRefreshingApps: isRefreshingApps,
                    refreshResult: refreshResult,
                    refreshError: refreshError,
                    refreshApps: refreshApps
                )
                AttentionSection(
                    items: snapshot.statusItems,
                    apps: snapshot.integrations,
                    openApp: openApp
                )
                MetricGrid(metrics: snapshot.metrics)
                AppSection(apps: snapshot.integrations, openApp: openApp)
                EventSection(events: snapshot.recentEvents)
                AuditSection(entries: snapshot.auditEntries)
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(Color.statusBackground)
    }
}

private struct DashboardHeader: View {
    let snapshot: DashboardSnapshot
    let isRefreshingApps: Bool
    let refreshResult: String?
    let refreshError: String?
    let refreshApps: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(snapshot.headline)
                    .font(.system(size: 42, weight: .semibold, design: .default))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 12)
                if let refreshApps {
                    Button {
                        Task {
                            await refreshApps()
                        }
                    } label: {
                        if isRefreshingApps {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh Apps", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRefreshingApps || snapshot.integrations.isEmpty)
                    .help(snapshot.integrations.isEmpty ? "Set up an app before refreshing." : "Run manual checks for configured apps.")
                }
            }
            Text(snapshot.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let refreshResult {
                Text(refreshResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let refreshError {
                Text(refreshError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttentionSection: View {
    let items: [StatusItem]
    let apps: [IntegrationSummary]
    let openApp: ((IntegrationSummary) -> Void)?

    private var attentionApps: [IntegrationSummary] {
        apps.filter { $0.severity >= .warning }
    }

    var body: some View {
        SectionBlock(title: "Needs attention") {
            if items.isEmpty, attentionApps.isEmpty {
                DashboardEmptyRow(
                    title: "No open attention items",
                    detail: "Status will show important changes here when connected apps report something that needs action."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(attentionApps) { app in
                        attentionAppRow(app)
                    }
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            SeverityDot(severity: item.severity)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.summary)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if let link = item.actionLink {
                                Link(link.label, destination: link.url)
                                    .font(.callout.weight(.semibold))
                            }
                        }
                        .padding(16)
                        .background(Color.statusSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attentionAppRow(_ app: IntegrationSummary) -> some View {
        let row = HStack(alignment: .top, spacing: 12) {
            IntegrationIcon(provider: app.provider, iconAsset: app.iconAsset, accentColor: app.accentColor, size: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                Text("\(app.state) - \(providerLabel(for: app))")
                    .font(.callout)
                    .foregroundStyle(statusColor(for: app.severity))
                Text(app.lastSyncDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if openApp != nil {
                HStack(spacing: 5) {
                    Text("Open app")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        if let openApp {
            Button {
                openApp(app)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Open \(app.name)"))
        } else {
            row
        }
    }

    private func statusColor(for severity: Severity) -> Color {
        switch severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .notice:
            .blue
        case .ok:
            .green
        }
    }

    private func providerLabel(for app: IntegrationSummary) -> String {
        if let providerName = app.providerName, providerName.isEmpty == false {
            return providerName
        }
        return app.provider
            .replacingOccurrences(of: "com.status.", with: "")
            .split(separator: ".")
            .map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
            .joined(separator: " ")
    }
}

private struct MetricGrid: View {
    let metrics: [Metric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.system(size: 30, weight: .semibold))
                    if let delta = metric.delta {
                        Text(delta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.statusSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct AppSection: View {
    let apps: [IntegrationSummary]
    let openApp: ((IntegrationSummary) -> Void)?

    var body: some View {
        SectionBlock(title: "Apps") {
            if apps.isEmpty {
                DashboardEmptyRow(
                    title: "No apps configured",
                    detail: "Set up an app from the Plugins catalog to start tracking resources, events, and dashboard tiles."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(apps) { app in
                        AppDashboardTile(app: app, openApp: openApp)
                    }
                }
            }
        }
    }
}

private struct AppDashboardTile: View {
    let app: IntegrationSummary
    let openApp: ((IntegrationSummary) -> Void)?

    @State private var isHovering = false

    @ViewBuilder
    var body: some View {
        let primaryItem = app.tileItems.first
        let secondaryItems = Array(app.tileItems.dropFirst().prefix(4))
        let accent = IntegrationVisual.visual(for: app.provider, accentColor: app.accentColor).color
        let tile = VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                IntegrationIcon(provider: app.provider, iconAsset: app.iconAsset, accentColor: app.accentColor, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(providerLabel(for: app))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(app.state)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(for: app.severity))
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                SeverityDot(severity: app.severity)
                    .padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(app.lastSyncDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let primaryItem {
                DashboardPrimaryTileItem(item: primaryItem)
            } else {
                DashboardTileEmptyHint()
            }
            if secondaryItems.isEmpty == false {
                DashboardSecondaryTileItems(items: secondaryItems)
            }
            if let resourceName = primaryItem?.resourceName {
                Text(resourceName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if openApp != nil {
                HStack(spacing: 5) {
                    Text("Open app")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: primaryItem == nil ? 150 : 210, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.statusSurface)
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(isHovering && openApp != nil ? 0.11 : 0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(isHovering && openApp != nil ? 0.42 : 0), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(0.72))
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))

        if let openApp {
            Button {
                openApp(app)
            } label: {
                tile
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel(Text("Open \(app.name)"))
            .accessibilityHint(Text("Shows the configured app details and settings."))
        } else {
            tile
        }
    }

    private func statusColor(for severity: Severity) -> Color {
        switch severity {
        case .critical:
            .red
        case .warning:
            .orange
        case .notice:
            .blue
        case .ok:
            .green
        }
    }

    private func providerLabel(for app: IntegrationSummary) -> String {
        if let providerName = app.providerName, providerName.isEmpty == false {
            return providerName
        }
        return app.provider
            .replacingOccurrences(of: "com.status.", with: "")
            .split(separator: ".")
            .map { $0.replacingOccurrences(of: "-", with: " ").capitalized }
            .joined(separator: " ")
    }
}

private struct DashboardPrimaryTileItem: View {
    let item: DashboardTileItem

    var body: some View {
        let displayValue = DashboardTileDisplayValue(item: item)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if item.kind == .link {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(displayValue.text)
                .font(primaryFont)
                .foregroundStyle(primaryColor)
                .lineLimit(item.kind == .text || item.kind == .placeholder ? 2 : 1)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(primaryColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryFont: Font {
        switch item.kind {
        case .count, .percent:
            .system(size: 32, weight: .semibold)
        case .status:
            .callout.weight(.semibold)
        case .link, .text:
            .callout.weight(.medium)
        case .placeholder:
            .callout.weight(.regular)
        }
    }

    private var primaryColor: Color {
        switch item.kind {
        case .status:
            statusColor
        case .count, .percent:
            .primary
        case .link:
            .blue
        case .text:
            .secondary
        case .placeholder:
            Color.secondary.opacity(0.72)
        }
    }

    private var statusColor: Color {
        let value = DashboardTileDisplayValue(item: item).text.lowercased()
        if value.contains("fail") || value.contains("reject") || value.contains("down") || value.contains("critical") {
            return .red
        }
        if value.contains("warn") || value.contains("review") || value.contains("pending") || value.contains("slow") {
            return .orange
        }
        if value.contains("ok") || value.contains("success") || value.contains("ready") || value.contains("up") {
            return .green
        }
        return .blue
    }
}

private struct DashboardTileEmptyHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting for dashboard data")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Refresh this app after setup to fill this tile.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DashboardSecondaryTileItems: View {
    let items: [DashboardTileItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(items) { item in
                let displayValue = DashboardTileDisplayValue(item: item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Text(displayValue.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryColor(for: item))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func secondaryColor(for item: DashboardTileItem) -> Color {
        switch item.kind {
        case .link:
            .blue
        case .placeholder:
            Color.secondary.opacity(0.72)
        default:
            .secondary
        }
    }
}

struct DashboardTileDisplayValue: Equatable {
    var text: String

    init(item: DashboardTileItem) {
        self.text = Self.format(item: item)
    }

    private static func format(item: DashboardTileItem) -> String {
        let trimmed = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("true") == .orderedSame {
            return "Yes"
        }
        if trimmed.caseInsensitiveCompare("false") == .orderedSame {
            return "No"
        }
        if item.kind == .link, let url = item.actionURL ?? URL(string: trimmed) {
            return formattedURL(url)
        }
        if isMillisecondsField(item.id) || isMillisecondsField(item.label),
           Double(trimmed) != nil,
           trimmed.lowercased().hasSuffix("ms") == false {
            return "\(trimmed) ms"
        }
        return trimmed
    }

    private static func isMillisecondsField(_ value: String) -> Bool {
        let normalized = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return normalized.hasSuffix("ms") ||
            normalized.contains("milliseconds") ||
            normalized.contains("responsetime")
    }

    private static func formattedURL(_ url: URL) -> String {
        guard let host = url.host(percentEncoded: false), host.isEmpty == false else {
            return url.absoluteString
        }
        let path = url.path(percentEncoded: false)
        return path == "/" || path.isEmpty ? host : "\(host)\(path)"
    }
}

private struct EventSection: View {
    let events: [Event]

    var body: some View {
        SectionBlock(title: "Recent events") {
            if events.isEmpty {
                DashboardEmptyRow(
                    title: "No recent events",
                    detail: "Manual refreshes and background checks will appear here once an app emits normalized events."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 12) {
                            SeverityDot(severity: event.severity)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                Text(event.summary)
                                    .foregroundStyle(.secondary)
                                Text(event.type)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.statusSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private struct AuditSection: View {
    let entries: [AuditEntry]

    var body: some View {
        SectionBlock(title: "Audit log") {
            if entries.isEmpty {
                DashboardEmptyRow(
                    title: "No recent audit entries",
                    detail: "Status records refreshes, automations, notifications, and actions here when they run."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                            AuditProvenance(entry: entry)
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

private struct AuditProvenance: View {
    let entry: AuditEntry

    var body: some View {
        let references = entry.provenanceReferences
        if references.isEmpty == false {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(references, id: \.self) { reference in
                    Text(reference)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

private struct SectionBlock<Content: View>: View {
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

private struct DashboardEmptyRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.statusSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SeverityDot: View {
    let severity: Severity

    var body: some View {
        Circle()
            .fill(severity.color)
            .frame(width: 10, height: 10)
            .accessibilityLabel(Text(severity.rawValue))
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

#Preview {
    DashboardView(snapshot: MockDashboard.snapshot)
}
