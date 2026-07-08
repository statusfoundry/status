import Foundation

public enum ActionSafetyLevel: String, Codable, Equatable, Sendable {
    case safe
    case reviewRequired = "review-required"
    case dangerous
    case unsupported
}

public enum ActionRunStatus: String, Codable, Equatable, Sendable {
    case success
    case failed
    case denied
    case unsupported
}

public struct ActionRunRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var ruleID: String
    public var eventID: String
    public var action: String
    public var status: ActionRunStatus
    public var input: [String: String]
    public var result: [String: String]
    public var error: String?
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String,
        ruleID: String,
        eventID: String,
        action: String,
        status: ActionRunStatus,
        input: [String: String],
        result: [String: String] = [:],
        error: String? = nil,
        startedAt: Date,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.ruleID = ruleID
        self.eventID = eventID
        self.action = action
        self.status = status
        self.input = input
        self.result = result
        self.error = error
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct ActionExecutionResult: Equatable, Sendable {
    public var actionRun: ActionRunRecord
    public var auditEntry: AuditEntry

    public init(actionRun: ActionRunRecord, auditEntry: AuditEntry) {
        self.actionRun = actionRun
        self.auditEntry = auditEntry
    }
}

public struct ActionRuntimeEffects: Equatable, Sendable {
    public private(set) var notifications: [ActionRuntimeNotification] = []
    public private(set) var inboxEventIDs: [String] = []
    public private(set) var openedURLs: [URL] = []
    public private(set) var auditNotes: [String] = []
    public private(set) var webhooks: [ActionRuntimeWebhook] = []
    public private(set) var providerActions: [ActionRuntimeProviderAction] = []

    public init(
        notifications: [ActionRuntimeNotification] = [],
        inboxEventIDs: [String] = [],
        openedURLs: [URL] = [],
        auditNotes: [String] = [],
        webhooks: [ActionRuntimeWebhook] = [],
        providerActions: [ActionRuntimeProviderAction] = []
    ) {
        self.notifications = notifications
        self.inboxEventIDs = inboxEventIDs
        self.openedURLs = openedURLs
        self.auditNotes = auditNotes
        self.webhooks = webhooks
        self.providerActions = providerActions
    }

    public func cursor() -> ActionRuntimeEffectCursor {
        ActionRuntimeEffectCursor(
            notificationCount: notifications.count,
            inboxEventIDCount: inboxEventIDs.count,
            openedURLCount: openedURLs.count,
            auditNoteCount: auditNotes.count,
            webhookCount: webhooks.count,
            providerActionCount: providerActions.count
        )
    }

    public func effects(since cursor: ActionRuntimeEffectCursor) -> ActionRuntimeEffects {
        var effects = ActionRuntimeEffects()
        effects.notifications = Array(notifications.dropFirst(cursor.notificationCount))
        effects.inboxEventIDs = Array(inboxEventIDs.dropFirst(cursor.inboxEventIDCount))
        effects.openedURLs = Array(openedURLs.dropFirst(cursor.openedURLCount))
        effects.auditNotes = Array(auditNotes.dropFirst(cursor.auditNoteCount))
        effects.webhooks = Array(webhooks.dropFirst(cursor.webhookCount))
        effects.providerActions = Array(providerActions.dropFirst(cursor.providerActionCount))
        return effects
    }

    fileprivate mutating func recordNotification(
        title: String,
        body: String,
        eventID: String,
        actionRunID: String,
        mode: NotificationMode = .immediate
    ) {
        notifications.append(ActionRuntimeNotification(
            title: title,
            body: body,
            eventID: eventID,
            actionRunID: actionRunID,
            mode: mode
        ))
    }

    fileprivate mutating func recordInbox(eventID: String) {
        inboxEventIDs.append(eventID)
    }

    fileprivate mutating func recordOpenedURL(_ url: URL) {
        openedURLs.append(url)
    }

    fileprivate mutating func recordAuditNote(_ note: String) {
        auditNotes.append(note)
    }

    fileprivate mutating func recordWebhook(url: URL, payload: [String: String], actionRunID: String) {
        webhooks.append(ActionRuntimeWebhook(url: url, payload: payload, actionRunID: actionRunID))
    }

    fileprivate mutating func recordProviderAction(
        actionRunID: String,
        action: String,
        provider: String?,
        parameters: [String: String],
        event: Event
    ) {
        providerActions.append(ActionRuntimeProviderAction(
            actionRunID: actionRunID,
            action: action,
            provider: provider,
            parameters: parameters,
            event: event
        ))
    }
}

public struct ActionRuntimeEffectCursor: Equatable, Sendable {
    public var notificationCount: Int
    public var inboxEventIDCount: Int
    public var openedURLCount: Int
    public var auditNoteCount: Int
    public var webhookCount: Int
    public var providerActionCount: Int

    public init(
        notificationCount: Int,
        inboxEventIDCount: Int,
        openedURLCount: Int,
        auditNoteCount: Int,
        webhookCount: Int,
        providerActionCount: Int = 0
    ) {
        self.notificationCount = notificationCount
        self.inboxEventIDCount = inboxEventIDCount
        self.openedURLCount = openedURLCount
        self.auditNoteCount = auditNoteCount
        self.webhookCount = webhookCount
        self.providerActionCount = providerActionCount
    }
}

public struct ActionRuntimeNotification: Equatable, Sendable {
    public var title: String
    public var body: String
    public var eventID: String?
    public var actionRunID: String?
    public var mode: NotificationMode

    public init(
        title: String,
        body: String,
        eventID: String? = nil,
        actionRunID: String? = nil,
        mode: NotificationMode = .immediate
    ) {
        self.title = title
        self.body = body
        self.eventID = eventID
        self.actionRunID = actionRunID
        self.mode = mode
    }
}

public struct ActionRuntimeWebhook: Equatable, Sendable {
    public var url: URL
    public var payload: [String: String]
    public var actionRunID: String?

    public init(url: URL, payload: [String: String], actionRunID: String? = nil) {
        self.url = url
        self.payload = payload
        self.actionRunID = actionRunID
    }
}

public struct ActionRuntimeProviderAction: Equatable, Sendable {
    public var actionRunID: String
    public var action: String
    public var provider: String?
    public var parameters: [String: String]
    public var event: Event

    public init(
        actionRunID: String,
        action: String,
        provider: String? = nil,
        parameters: [String: String],
        event: Event
    ) {
        self.actionRunID = actionRunID
        self.action = action
        self.provider = provider
        self.parameters = parameters
        self.event = event
    }
}

public final class ActionRunner {
    public private(set) var effects: ActionRuntimeEffects
    private let now: () -> Date

    public init(effects: ActionRuntimeEffects = ActionRuntimeEffects(), now: @escaping () -> Date = Date.init) {
        self.effects = effects
        self.now = now
    }

    public func run(
        _ match: RuleMatch,
        reviewPermissionGranted: (Rule, RuleActionDefinition) -> Bool = { _, _ in false }
    ) -> [ActionExecutionResult] {
        match.actions.enumerated().map { index, action in
            run(action, at: index, rule: match.rule, event: match.event, reviewPermissionGranted: reviewPermissionGranted)
        }
    }

    public static func safetyLevel(for action: String) -> ActionSafetyLevel {
        switch action {
        case "notification.show", "status.inbox.add", "status.open_url", "audit.note":
            return .safe
        case "webhook.post", "jira.createIssue", "github.createIssue", "github.comment", "email.createDraft":
            return .reviewRequired
        default:
            return .unsupported
        }
    }

    private func run(
        _ definition: RuleActionDefinition,
        at index: Int,
        rule: Rule,
        event: Event,
        reviewPermissionGranted: (Rule, RuleActionDefinition) -> Bool
    ) -> ActionExecutionResult {
        let startedAt = now()
        let runID = "run_\(rule.id)_\(event.id)_\(index)"
        var status: ActionRunStatus = .success
        var result: [String: String] = [:]
        var error: String?

        switch Self.safetyLevel(for: definition.action) {
        case .safe:
            do {
                result = try performSafeAction(definition, event: event, actionRunID: runID)
            } catch let actionError as ActionRunnerError {
                status = .failed
                error = actionError.errorDescription
            } catch let caughtError {
                status = .failed
                error = String(describing: caughtError)
            }
        case .reviewRequired:
            guard reviewPermissionGranted(rule, definition) else {
                status = .denied
                error = "\(definition.action) requires explicit write permission before it can run."
                break
            }
            do {
                result = try performReviewRequiredAction(definition, event: event, actionRunID: runID)
            } catch let actionError as ActionRunnerError {
                status = .unsupported
                error = actionError.errorDescription
            } catch let caughtError {
                status = .failed
                error = String(describing: caughtError)
            }
        case .dangerous:
            status = .denied
            error = "\(definition.action) is not allowed in v1."
        case .unsupported:
            status = .unsupported
            error = "\(definition.action) is not supported by the core action runner."
        }

        let finishedAt = now()
        let actionRun = ActionRunRecord(
            id: runID,
            ruleID: rule.id,
            eventID: event.id,
            action: definition.action,
            status: status,
            input: definition.parameters,
            result: result,
            error: error,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        return ActionExecutionResult(
            actionRun: actionRun,
            auditEntry: auditEntry(for: actionRun, rule: rule, event: event)
        )
    }

    private func performSafeAction(
        _ definition: RuleActionDefinition,
        event: Event,
        actionRunID: String
    ) throws -> [String: String] {
        switch definition.action {
        case "notification.show":
            let parameters = renderedParameters(definition.parameters, event: event)
            let title = parameters["title"] ?? event.title
            let body = parameters["body"] ?? event.summary
            effects.recordNotification(title: title, body: body, eventID: event.id, actionRunID: actionRunID)
            return ["title": title, "body": body]
        case "status.inbox.add":
            effects.recordInbox(eventID: event.id)
            return ["event_id": event.id]
        case "status.open_url":
            let parameters = renderedParameters(definition.parameters, event: event)
            let urlString = parameters["url"] ?? event.actionURL?.absoluteString
            guard let urlString, let url = URL(string: urlString) else {
                throw ActionRunnerError.missingURL
            }
            effects.recordOpenedURL(url)
            return ["url": url.absoluteString]
        case "audit.note":
            let parameters = renderedParameters(definition.parameters, event: event)
            let note = parameters["note"] ?? event.summary
            effects.recordAuditNote(note)
            return ["note": note]
        default:
            throw ActionRunnerError.unsupportedSafeAction(definition.action)
        }
    }

    private func performReviewRequiredAction(
        _ definition: RuleActionDefinition,
        event: Event,
        actionRunID: String
    ) throws -> [String: String] {
        switch definition.action {
        case "webhook.post":
            let parameters = renderedParameters(definition.parameters, event: event)
            let urlString = parameters["url"]
            guard let urlString, let url = URL(string: urlString) else {
                throw ActionRunnerError.missingURL
            }
            let payload = webhookPayload(parameters: parameters, event: event)
            effects.recordWebhook(url: url, payload: payload, actionRunID: actionRunID)
            return ["url": url.absoluteString]
        default:
            let parameters = renderedParameters(definition.parameters, event: event)
            effects.recordProviderAction(
                actionRunID: actionRunID,
                action: definition.action,
                provider: event.provider,
                parameters: parameters,
                event: event
            )
            return ["queued": "provider-action"]
        }
    }

    private func webhookPayload(parameters: [String: String], event: Event) -> [String: String] {
        var payload = parameters
        payload["event_id"] = event.id
        payload["event_type"] = event.type
        payload["event_title"] = event.title
        payload["event_summary"] = event.summary
        payload["resource_id"] = event.resourceID
        payload["resource_name"] = event.resourceName
        payload["severity"] = event.severity.rawValue
        payload["timestamp"] = iso8601String(from: event.timestamp)
        payload["url"] = nil
        return payload
    }

    private func renderedParameters(_ parameters: [String: String], event: Event) -> [String: String] {
        let context = MappingTemplateContext(scopes: ["event": event.mappingValue])
        return parameters.mapValues { MappingTemplateRenderer.render($0, context: context) }
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func auditEntry(for actionRun: ActionRunRecord, rule: Rule, event: Event) -> AuditEntry {
        let title: String
        switch actionRun.status {
        case .success:
            title = "Action completed"
        case .failed:
            title = "Action failed"
        case .denied:
            title = "Action denied"
        case .unsupported:
            title = "Action unsupported"
        }

        let detail: String
        if let error = actionRun.error {
            detail = "Rule \(rule.name) tried \(actionRun.action) for \(event.title). \(error)"
        } else {
            detail = "Rule \(rule.name) ran \(actionRun.action) for \(event.title)."
        }

        return AuditEntry(
            id: "aud_\(actionRun.id)",
            title: title,
            detail: detail,
            timestamp: actionRun.finishedAt ?? actionRun.startedAt,
            status: actionRun.status.rawValue,
            eventID: event.id,
            actionRunID: actionRun.id
        )
    }
}

public enum ActionRunnerError: Error, Equatable, LocalizedError, Sendable {
    case missingURL
    case unsupportedSafeAction(String)
    case unsupportedReviewRequiredAction(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            return "status.open_url requires a URL parameter or event action URL."
        case .unsupportedSafeAction(let action):
            return "\(action) is not a safe built-in action."
        case .unsupportedReviewRequiredAction(let action):
            return "\(action) is not wired to a provider executor yet."
        }
    }
}
