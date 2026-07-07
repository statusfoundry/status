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
    let pipeline = AutomationPipeline(store: store, actionRunner: runner)

    let result = try pipeline.process(event: event, rules: [rule])

    let actionRun = try #require(result.actionResults.first?.actionRun)
    let auditEntry = try #require(result.actionResults.first?.auditEntry)
    #expect(result.matches.count == 1)
    #expect(try store.actionRun(id: actionRun.id) == actionRun)
    #expect(try store.auditEntry(id: auditEntry.id) == auditEntry)
    #expect(runner.effects.notifications == [ActionRuntimeNotification(title: "Build failed", body: event.summary)])
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

private func workflowFailedEvent() -> Event {
    Event(
        id: "evt_01workflowfailed",
        provider: "github",
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

private func temporaryDatabase() throws -> SQLiteDatabase {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("status-\(UUID().uuidString).sqlite")
        .path
    return try SQLiteDatabase(path: path)
}
