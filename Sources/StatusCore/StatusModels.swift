import Foundation

public enum Severity: String, Codable, CaseIterable, Sendable, Comparable {
    case ok
    case notice
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .ok: 0
        case .notice: 1
        case .warning: 2
        case .critical: 3
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum StatusItemState: String, Codable, CaseIterable, Sendable {
    case open
    case snoozed
    case resolved
    case dismissed
}

public enum NotificationMode: String, Codable, CaseIterable, Sendable {
    case immediate
    case digest
    case dashboardOnly
    case silentAutomation
    case disabled
}

public struct NotificationRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var eventID: String?
    public var statusItemID: String?
    public var mode: NotificationMode
    public var title: String
    public var body: String
    public var deliveredAt: Date?
    public var createdAt: Date

    public init(
        id: String,
        eventID: String? = nil,
        statusItemID: String? = nil,
        mode: NotificationMode,
        title: String,
        body: String,
        deliveredAt: Date? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.eventID = eventID
        self.statusItemID = statusItemID
        self.mode = mode
        self.title = title
        self.body = body
        self.deliveredAt = deliveredAt
        self.createdAt = createdAt
    }
}

public enum NotificationPreferenceScope: String, Codable, Equatable, Sendable {
    case plugin
    case app
    case event
}

public struct NotificationPreference: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var scope: NotificationPreferenceScope
    public var pluginID: String
    public var accountID: String?
    public var eventType: String?
    public var mode: NotificationMode
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        scope: NotificationPreferenceScope,
        pluginID: String,
        accountID: String? = nil,
        eventType: String? = nil,
        mode: NotificationMode,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.scope = scope
        self.pluginID = pluginID
        self.accountID = accountID
        self.eventType = eventType
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Account: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var pluginID: String
    public var provider: String
    public var displayName: String
    public var authType: String
    public var credentialRef: String?

    public init(
        id: String,
        pluginID: String,
        provider: String,
        displayName: String,
        authType: String = "none",
        credentialRef: String? = nil
    ) {
        self.id = id
        self.pluginID = pluginID
        self.provider = provider
        self.displayName = displayName
        self.authType = authType
        self.credentialRef = credentialRef
    }
}

public struct PluginAccountConfiguration: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var pluginID: String
    public var accountName: String
    public var variables: [String: String]
    public var authType: String
    public var credentialRef: String?

    public init(
        id: String,
        pluginID: String,
        accountName: String,
        variables: [String: String],
        authType: String = "none",
        credentialRef: String? = nil
    ) {
        self.id = id
        self.pluginID = pluginID
        self.accountName = accountName
        self.variables = variables
        self.authType = authType
        self.credentialRef = credentialRef
    }
}

public struct Resource: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var accountID: String
    public var pluginID: String
    public var type: String
    public var name: String
    public var fields: [String: String]
    public var actionURL: URL?

    public init(
        id: String,
        accountID: String,
        pluginID: String,
        type: String,
        name: String,
        fields: [String: String] = [:],
        actionURL: URL? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.pluginID = pluginID
        self.type = type
        self.name = name
        self.fields = fields
        self.actionURL = actionURL
    }
}

public struct ResourceStateSnapshot: Codable, Equatable, Sendable {
    public var resourceID: String
    public var state: [String: String]
    public var stateHash: String
    public var jobID: String?
    public var capturedAt: Date

    public init(resourceID: String, state: [String: String], stateHash: String, jobID: String? = nil, capturedAt: Date) {
        self.resourceID = resourceID
        self.state = state
        self.stateHash = stateHash
        self.jobID = jobID
        self.capturedAt = capturedAt
    }
}

public struct ActionLink: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var url: URL

    public init(id: String, label: String, url: URL) {
        self.id = id
        self.label = label
        self.url = url
    }
}

public struct Event: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var provider: String
    public var type: String
    public var resourceID: String
    public var resourceName: String
    public var severity: Severity
    public var title: String
    public var summary: String
    public var timestamp: Date
    public var actionURL: URL?
    public var fingerprint: String

    public init(
        id: String,
        provider: String,
        type: String,
        resourceID: String,
        resourceName: String,
        severity: Severity,
        title: String,
        summary: String,
        timestamp: Date,
        actionURL: URL? = nil,
        fingerprint: String
    ) {
        self.id = id
        self.provider = provider
        self.type = type
        self.resourceID = resourceID
        self.resourceName = resourceName
        self.severity = severity
        self.title = title
        self.summary = summary
        self.timestamp = timestamp
        self.actionURL = actionURL
        self.fingerprint = fingerprint
    }
}

extension Event {
    var mappingValue: MappingJSONValue {
        var fields: [String: MappingJSONValue] = [
            "id": .string(id),
            "provider": .string(provider),
            "type": .string(type),
            "resourceID": .string(resourceID),
            "resourceId": .string(resourceID),
            "resourceName": .string(resourceName),
            "severity": .string(severity.rawValue),
            "title": .string(title),
            "summary": .string(summary),
            "timestamp": .string(Self.iso8601String(from: timestamp)),
            "fingerprint": .string(fingerprint)
        ]
        if let actionURL {
            fields["actionURL"] = .string(actionURL.absoluteString)
            fields["actionUrl"] = .string(actionURL.absoluteString)
        }
        return .object(fields)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

public struct StatusItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var resourceID: String
    public var severity: Severity
    public var title: String
    public var summary: String
    public var state: StatusItemState
    public var updatedAt: Date
    public var resolvedAt: Date?
    public var snoozeUntil: Date?
    public var dismissedReason: String?
    public var stuck: Bool
    public var actionLink: ActionLink?

    public init(
        id: String,
        resourceID: String,
        severity: Severity,
        title: String,
        summary: String,
        state: StatusItemState,
        updatedAt: Date,
        resolvedAt: Date? = nil,
        snoozeUntil: Date? = nil,
        dismissedReason: String? = nil,
        stuck: Bool = false,
        actionLink: ActionLink? = nil
    ) {
        self.id = id
        self.resourceID = resourceID
        self.severity = severity
        self.title = title
        self.summary = summary
        self.state = state
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.snoozeUntil = snoozeUntil
        self.dismissedReason = dismissedReason
        self.stuck = stuck
        self.actionLink = actionLink
    }
}

public struct Metric: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var resourceID: String
    public var label: String
    public var value: String
    public var delta: String?
    public var severity: Severity

    public init(id: String, resourceID: String, label: String, value: String, delta: String? = nil, severity: Severity) {
        self.id = id
        self.resourceID = resourceID
        self.label = label
        self.value = value
        self.delta = delta
        self.severity = severity
    }
}

public struct AuditEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var timestamp: Date
    public var status: String
    public var jobID: String?
    public var eventID: String?
    public var actionRunID: String?

    public init(
        id: String,
        title: String,
        detail: String,
        timestamp: Date,
        status: String,
        jobID: String? = nil,
        eventID: String? = nil,
        actionRunID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.status = status
        self.jobID = jobID
        self.eventID = eventID
        self.actionRunID = actionRunID
    }
}

public struct IntegrationSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var provider: String
    public var state: String
    public var severity: Severity
    public var lastSyncDescription: String

    public init(id: String, name: String, provider: String, state: String, severity: Severity, lastSyncDescription: String) {
        self.id = id
        self.name = name
        self.provider = provider
        self.state = state
        self.severity = severity
        self.lastSyncDescription = lastSyncDescription
    }
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public var headline: String
    public var summary: String
    public var statusItems: [StatusItem]
    public var recentEvents: [Event]
    public var metrics: [Metric]
    public var integrations: [IntegrationSummary]
    public var auditEntries: [AuditEntry]

    public init(
        headline: String,
        summary: String,
        statusItems: [StatusItem],
        recentEvents: [Event],
        metrics: [Metric],
        integrations: [IntegrationSummary],
        auditEntries: [AuditEntry]
    ) {
        self.headline = headline
        self.summary = summary
        self.statusItems = statusItems
        self.recentEvents = recentEvents
        self.metrics = metrics
        self.integrations = integrations
        self.auditEntries = auditEntries
    }

    public static let empty = DashboardSnapshot(
        headline: "All clear",
        summary: "No tracked events or apps are stored on this device yet.",
        statusItems: [],
        recentEvents: [],
        metrics: [],
        integrations: [],
        auditEntries: []
    )
}
