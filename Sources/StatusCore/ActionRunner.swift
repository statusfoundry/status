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

    public init() {}

    fileprivate mutating func recordNotification(title: String, body: String) {
        notifications.append(ActionRuntimeNotification(title: title, body: body))
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
}

public struct ActionRuntimeNotification: Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public final class ActionRunner {
    public private(set) var effects: ActionRuntimeEffects
    private let now: () -> Date

    public init(effects: ActionRuntimeEffects = ActionRuntimeEffects(), now: @escaping () -> Date = Date.init) {
        self.effects = effects
        self.now = now
    }

    public func run(_ match: RuleMatch) -> [ActionExecutionResult] {
        match.actions.enumerated().map { index, action in
            run(action, at: index, rule: match.rule, event: match.event)
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

    private func run(_ definition: RuleActionDefinition, at index: Int, rule: Rule, event: Event) -> ActionExecutionResult {
        let startedAt = now()
        let runID = "run_\(rule.id)_\(event.id)_\(index)"
        var status: ActionRunStatus = .success
        var result: [String: String] = [:]
        var error: String?

        switch Self.safetyLevel(for: definition.action) {
        case .safe:
            do {
                result = try performSafeAction(definition, event: event)
            } catch let actionError as ActionRunnerError {
                status = .failed
                error = actionError.errorDescription
            } catch let caughtError {
                status = .failed
                error = String(describing: caughtError)
            }
        case .reviewRequired:
            status = .denied
            error = "\(definition.action) requires explicit write permission before it can run."
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

    private func performSafeAction(_ definition: RuleActionDefinition, event: Event) throws -> [String: String] {
        switch definition.action {
        case "notification.show":
            let title = definition.parameters["title"] ?? event.title
            let body = definition.parameters["body"] ?? event.summary
            effects.recordNotification(title: title, body: body)
            return ["title": title, "body": body]
        case "status.inbox.add":
            effects.recordInbox(eventID: event.id)
            return ["event_id": event.id]
        case "status.open_url":
            let urlString = definition.parameters["url"] ?? event.actionURL?.absoluteString
            guard let urlString, let url = URL(string: urlString) else {
                throw ActionRunnerError.missingURL
            }
            effects.recordOpenedURL(url)
            return ["url": url.absoluteString]
        case "audit.note":
            let note = definition.parameters["note"] ?? event.summary
            effects.recordAuditNote(note)
            return ["note": note]
        default:
            throw ActionRunnerError.unsupportedSafeAction(definition.action)
        }
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

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            return "status.open_url requires a URL parameter or event action URL."
        case .unsupportedSafeAction(let action):
            return "\(action) is not a safe built-in action."
        }
    }
}
