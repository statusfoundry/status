import StatusCore
import SwiftUI

public struct DashboardView: View {
    private let snapshot: DashboardSnapshot

    public init(snapshot: DashboardSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHeader(snapshot: snapshot)
                AttentionSection(items: snapshot.statusItems)
                MetricGrid(metrics: snapshot.metrics)
                IntegrationSection(integrations: snapshot.integrations)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.headline)
                .font(.system(size: 42, weight: .semibold, design: .default))
                .foregroundStyle(Color.primary)
            Text(snapshot.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AttentionSection: View {
    let items: [StatusItem]

    var body: some View {
        SectionBlock(title: "Needs attention") {
            VStack(spacing: 10) {
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

private struct IntegrationSection: View {
    let integrations: [IntegrationSummary]

    var body: some View {
        SectionBlock(title: "Integrations") {
            VStack(spacing: 10) {
                ForEach(integrations) { integration in
                    HStack(spacing: 12) {
                        SeverityDot(severity: integration.severity)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(integration.name)
                                .font(.headline)
                            Text(integration.lastSyncDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(integration.state)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.statusSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct EventSection: View {
    let events: [Event]

    var body: some View {
        SectionBlock(title: "Recent events") {
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

private struct AuditSection: View {
    let entries: [AuditEntry]

    var body: some View {
        SectionBlock(title: "Audit log") {
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

private extension Color {
    static let statusBackground = Color(red: 0.965, green: 0.965, blue: 0.945)
    static let statusSurface = Color.white.opacity(0.92)
}

#Preview {
    DashboardView(snapshot: MockDashboard.snapshot)
}
