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
    private let effectDispatcher: ActionEffectDispatcher
    public let actionRunner: ActionRunner

    public init(
        store: StatusPersistenceStore,
        actionRunner: ActionRunner = ActionRunner(),
        effectDispatcher: ActionEffectDispatcher = NoopActionEffectDispatcher()
    ) {
        self.store = store
        self.actionRunner = actionRunner
        self.effectDispatcher = effectDispatcher
    }

    public func process(event: Event, rules: [Rule]) throws -> AutomationPipelineResult {
        let matches = RuleEngine.matchingRules(for: event, rules: rules)
        var actionResults: [ActionExecutionResult] = []
        let cursor = actionRunner.effects.cursor()

        for match in matches {
            for result in actionRunner.run(match, reviewPermissionGranted: reviewPermissionGranted) {
                try store.upsertActionRun(result.actionRun)
                try store.insertAuditEntry(result.auditEntry)
                actionResults.append(result)
            }
        }
        try effectDispatcher.dispatch(actionRunner.effects.effects(since: cursor))

        return AutomationPipelineResult(
            eventID: event.id,
            matches: matches,
            actionResults: actionResults
        )
    }

    public func processStoredRules(for event: Event) throws -> AutomationPipelineResult {
        try process(event: event, rules: store.rules(eventType: event.type))
    }

    private func reviewPermissionGranted(rule: Rule, action: RuleActionDefinition) -> Bool {
        guard ActionRunner.safetyLevel(for: action.action) == .reviewRequired,
              let provider = rule.provider else {
            return false
        }
        return ((try? store.pluginPermissions(pluginID: provider)) ?? []).contains { permission in
            permission.permission == .writeActions && permission.granted
        }
    }
}
