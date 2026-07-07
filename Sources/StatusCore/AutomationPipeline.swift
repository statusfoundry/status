import Foundation

public struct AutomationPipelineResult: Equatable, Sendable {
    public var eventID: String
    public var matches: [RuleMatch]
    public var actionResults: [ActionExecutionResult]

    public init(eventID: String, matches: [RuleMatch], actionResults: [ActionExecutionResult]) {
        self.eventID = eventID
        self.matches = matches
        self.actionResults = actionResults
    }
}

public final class AutomationPipeline {
    private let store: StatusPersistenceStore
    public let actionRunner: ActionRunner

    public init(store: StatusPersistenceStore, actionRunner: ActionRunner = ActionRunner()) {
        self.store = store
        self.actionRunner = actionRunner
    }

    public func process(event: Event, rules: [Rule]) throws -> AutomationPipelineResult {
        let matches = RuleEngine.matchingRules(for: event, rules: rules)
        var actionResults: [ActionExecutionResult] = []

        for match in matches {
            for result in actionRunner.run(match) {
                try store.upsertActionRun(result.actionRun)
                try store.insertAuditEntry(result.auditEntry)
                actionResults.append(result)
            }
        }

        return AutomationPipelineResult(
            eventID: event.id,
            matches: matches,
            actionResults: actionResults
        )
    }
}
