import Foundation
import Testing
@testable import StatusCore

@Test func automationPipelineRunsMatchingRuleAndPersistsActionAuditTrail() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_notify",
        name: "Notify workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [
            RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("warning"))
        ],
        actions: [
            RuleActionDefinition(action: "notification.show", parameters: ["title": "Build failed"])
        ]
    )
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    let runner = ActionRunner(now: { now })
    let dispatcher = RecordingActionEffectDispatcher()
    let pipeline = AutomationPipeline(store: store, actionRunner: runner, effectDispatcher: dispatcher)

    let result = try pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    let auditEntry = try #require(result.actionResults.first?.auditEntry)
    #expect(result.matches.count == 1)
    #expect(try store.actionRun(id: actionRun.id) == actionRun)
    #expect(try store.auditEntry(id: auditEntry.id) == auditEntry)
    #expect(runner.effects.notifications == [ActionRuntimeNotification(title: "Build failed", body: event.summary)])
    #expect(dispatcher.dispatchedEffects == [
        ActionRuntimeEffects(
            notifications: [ActionRuntimeNotification(title: "Build failed", body: event.summary)]
        )
    ])
}

@Test func automationPipelineIgnoresRulesThatDoNotMatch() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_jira",
        name: "Jira app review failure",
        enabled: true,
        provider: "appstoreconnect",
        eventType: "app.review.rejected",
        conditions: [],
        actions: [RuleActionDefinition(action: "jira.createIssue")]
    )
    let pipeline = AutomationPipeline(store: store)

    let result = try pipeline.process(event: event, rules: [rule])

    #expect(result.matches.isEmpty)
    #expect(result.actionResults.isEmpty)
    #expect(try store.auditEntryCount() == 0)
}

@Test func automationPipelineDeniesReviewRequiredActionWithoutWriteGrant() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = webhookRule()
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { Date(timeIntervalSince1970: 1_783_433_530) })
    )

    let result = try pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    #expect(actionRun.status == .denied)
    #expect(actionRun.error == "webhook.post requires explicit write permission before it can run.")
    #expect(try store.auditEntry(id: "aud_\(actionRun.id)")?.status == "denied")
}

@Test func automationPipelineDispatchesWebhookWhenWriteGrantExists() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent(provider: "com.status.github")
    let rule = webhookRule(provider: "com.status.github")
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    try installActionPlugin(provider: "com.status.github", store: store, at: now)
    try store.setPluginPermission(pluginID: "com.status.github", permission: .writeActions, granted: true, grantedAt: now)
    let dispatcher = RecordingActionEffectDispatcher()
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { now }),
        effectDispatcher: dispatcher
    )

    let result = try pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    let webhookURL = try #require(URL(string: "https://example.com/hooks/status"))
    #expect(actionRun.status == .success)
    #expect(actionRun.result == ["url": webhookURL.absoluteString])
    #expect(try store.auditEntry(id: "aud_\(actionRun.id)")?.status == "success")
    #expect(dispatcher.dispatchedEffects == [
        ActionRuntimeEffects(
            webhooks: [
                ActionRuntimeWebhook(
                    url: webhookURL,
                    payload: [
                        "event_id": event.id,
                        "event_type": event.type,
                        "event_title": event.title,
                        "event_summary": event.summary,
                        "resource_id": event.resourceID,
                        "resource_name": event.resourceName,
                        "severity": event.severity.rawValue,
                        "timestamp": iso8601String(from: event.timestamp)
                    ]
                )
            ]
        )
    ])
}

@Test func automationPipelineCanEvaluateStoredRules() throws {
    let database = try temporaryDatabase()
    try StatusDatabaseMigrator.migrate(database)
    let store = StatusPersistenceStore(database: database)
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_notify",
        name: "Notify workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "notification.show")
        ]
    )
    try store.upsertRule(rule, updatedAt: event.timestamp)
    let pipeline = AutomationPipeline(
        store: store,
        actionRunner: ActionRunner(now: { Date(timeIntervalSince1970: 1_783_433_530) })
    )

    let result = try pipeline.processStoredRules(for: event)

    #expect(result.matches.map(\.rule.id) == ["rul_notify"])
    #expect(result.actionResults.first?.actionRun.action == "notification.show")
    #expect(try store.actionRun(id: "run_rul_notify_evt_01workflowfailed_0")?.status == .success)
}

private func webhookRule(provider: String = "github") -> Rule {
    Rule(
        id: "rul_webhook",
        name: "Webhook workflow failure",
        enabled: true,
        provider: provider,
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "webhook.post", parameters: ["url": "https://example.com/hooks/status"])
        ]
    )
}

private func workflowFailedEvent(provider: String = "github") -> Event {
    Event(
        id: "evt_01workflowfailed",
        provider: provider,
        type: "github.workflow.failed",
        resourceID: "res_status_repo",
        resourceName: "status",
        severity: .critical,
        title: "Workflow failed",
        summary: "CI failed on main.",
        timestamp: Date(timeIntervalSince1970: 1_783_433_520),
        actionURL: URL(string: "https://github.com/statusfoundry/status/actions"),
        fingerprint: "github:workflow.failed:res_status_repo:failure"
    )
}

private func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func installActionPlugin(provider: String, store: StatusPersistenceStore, at date: Date) throws {
    let manifest = PluginManifest(
        id: provider,
        name: provider,
        version: "0.1.0",
        author: "Status Foundry",
        category: "automation",
        description: "Automation fixture.",
        minCoreVersion: "0.1.0",
        platforms: [.macOS, .iOS],
        permissions: [.writeActions],
        domains: []
    )
    try store.installPlugin(
        PluginInstallRecord(
            manifest: manifest,
            trustLevel: .official,
            installPath: "/tmp/\(provider)",
            verification: PluginPackageVerificationResult(
                pluginID: provider,
                version: manifest.version,
                sha256: "fixture",
                signedBy: "status-foundry-dev"
            ),
            installedAt: date
        )
    )
}

private func temporaryDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    return try SQLiteDatabase(path: path)
}
