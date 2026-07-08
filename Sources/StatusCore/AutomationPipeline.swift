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
    private let providerActionExecutor: ProviderActionExecutor?
    public let actionRunner: ActionRunner

    public init(
        store: StatusPersistenceStore,
        actionRunner: ActionRunner = ActionRunner(),
        effectDispatcher: ActionEffectDispatcher = NoopActionEffectDispatcher(),
        providerActionExecutor: ProviderActionExecutor? = nil
    ) {
        self.store = store
        self.actionRunner = actionRunner
        self.effectDispatcher = effectDispatcher
        self.providerActionExecutor = providerActionExecutor
    }

    public func process(event: Event, rules: [Rule]) async throws -> AutomationPipelineResult {
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
        let effects = actionRunner.effects.effects(since: cursor)
        try persistNotifications(effects.notifications)
        do {
            try await executeProviderActions(effects.providerActions)
            try await effectDispatcher.dispatch(effects)
            try markNotificationsDelivered(effects.notifications)
        } catch let failure as ActionEffectDispatchFailure {
            try recordDispatchFailure(failure)
            throw failure
        }

        return AutomationPipelineResult(
            eventID: event.id,
            matches: matches,
            actionResults: actionResults
        )
    }

    public func processStoredRules(for event: Event) async throws -> AutomationPipelineResult {
        try await process(event: event, rules: store.rules(eventType: event.type))
    }

    private func recordDispatchFailure(_ failure: ActionEffectDispatchFailure) throws {
        guard var actionRun = try store.actionRun(id: failure.actionRunID) else {
            return
        }
        let finishedAt = Date()
        actionRun.status = .failed
        actionRun.error = failure.message
        actionRun.finishedAt = finishedAt
        try store.upsertActionRun(actionRun)
        try store.insertAuditEntry(
            AuditEntry(
                id: "aud_\(actionRun.id)",
                title: "Action failed",
                detail: "Runtime effect dispatch failed for \(actionRun.action). \(failure.message)",
                timestamp: finishedAt,
                status: "failed",
                eventID: actionRun.eventID,
                actionRunID: actionRun.id
            )
        )
    }

    private func persistNotifications(_ notifications: [ActionRuntimeNotification]) throws {
        for notification in notifications {
            try store.upsertNotification(
                NotificationRecord(
                    id: notificationRecordID(for: notification),
                    eventID: notification.eventID,
                    statusItemID: notification.eventID.map(statusItemID(for:)),
                    mode: notification.mode,
                    title: notification.title,
                    body: notification.body,
                    createdAt: Date()
                )
            )
        }
    }

    private func markNotificationsDelivered(_ notifications: [ActionRuntimeNotification]) throws {
        let deliveredAt = Date()
        for notification in notifications where notification.mode == .immediate {
            try store.markNotificationDelivered(id: notificationRecordID(for: notification), deliveredAt: deliveredAt)
        }
    }

    private func executeProviderActions(_ actions: [ActionRuntimeProviderAction]) async throws {
        for action in actions {
            guard let providerActionExecutor else {
                throw ActionEffectDispatchFailure(
                    actionRunID: action.actionRunID,
                    message: "\(action.action) is not wired to a provider executor yet."
                )
            }
            do {
                let result = try await providerActionExecutor.execute(action)
                try recordProviderActionSuccess(actionRunID: action.actionRunID, result: result)
            } catch let failure as ActionEffectDispatchFailure {
                throw failure
            } catch {
                throw ActionEffectDispatchFailure(actionRunID: action.actionRunID, message: error.localizedDescription)
            }
        }
    }

    private func recordProviderActionSuccess(actionRunID: String, result: [String: String]) throws {
        guard var actionRun = try store.actionRun(id: actionRunID) else {
            return
        }
        actionRun.status = .success
        actionRun.result = result
        actionRun.error = nil
        actionRun.finishedAt = Date()
        try store.upsertActionRun(actionRun)
    }

    private func notificationRecordID(for notification: ActionRuntimeNotification) -> String {
        if let actionRunID = notification.actionRunID {
            return "ntf_\(actionRunID)"
        }
        return "ntf_\(UUID().uuidString.lowercased())"
    }

    private func statusItemID(for eventID: String) -> String {
        if eventID.hasPrefix("evt_") {
            return "sti_" + eventID.dropFirst(4)
        }
        return "sti_\(eventID)"
    }

    private func reviewPermissionGranted(rule: Rule, action: RuleActionDefinition) -> Bool {
        guard ActionRunner.safetyLevel(for: action.action) == .reviewRequired else {
            return false
        }
        let provider: String?
        if action.action == "webhook.post" {
            provider = rule.provider
        } else {
            provider = providerDeclaringAction(action.action) ?? rule.provider
        }
        guard let provider else { return false }
        return ((try? store.pluginPermissions(pluginID: provider)) ?? []).contains { permission in
            permission.permission == .writeActions && permission.granted
        }
    }

    private func providerDeclaringAction(_ action: String) -> String? {
        guard let plugins = try? store.installedPlugins() else {
            return nil
        }
        for plugin in plugins where plugin.enabled {
            guard let definition = try? store.installedPluginDefinition(pluginID: plugin.id),
                  definition.actions.contains(where: { $0.id == action }) else {
                continue
            }
            return plugin.id
        }
        return nil
    }
}
