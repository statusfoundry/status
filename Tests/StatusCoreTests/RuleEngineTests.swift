import Foundation
import Testing
@testable import StatusCore

@Test func ruleMatchesEventTypeProviderAndConditions() throws {
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_workflow_failed",
        name: "Critical GitHub workflow",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [
            RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("warning")),
            RuleCondition(field: "resourceName", operation: .contains, value: .string("status"))
        ],
        actions: [
            RuleActionDefinition(action: "notification.show")
        ]
    )

    let matches = RuleEngine.matchingRules(for: event, rules: [rule])

    #expect(matches.count == 1)
    #expect(matches.first?.actions.first?.action == "notification.show")
}

@Test func disabledRulesDoNotMatch() throws {
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_disabled",
        name: "Disabled",
        enabled: false,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "notification.show")]
    )

    #expect(RuleEngine.matchingRules(for: event, rules: [rule]).isEmpty)
}

@Test func actionRunnerRunsSafeNotificationAndCreatesAudit() throws {
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_notify",
        name: "Notify workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "notification.show", parameters: ["title": "Build failed"])
        ]
    )
    let match = try #require(RuleEngine.matchingRules(for: event, rules: [rule]).first)
    let now = Date(timeIntervalSince1970: 1_783_433_530)
    let runner = ActionRunner(now: { now })

    let results = runner.run(match)

    #expect(results.count == 1)
    #expect(runner.effects.notifications == [
        ActionRuntimeNotification(
            title: "Build failed",
            body: event.summary,
            eventID: event.id,
            actionRunID: "run_rul_notify_evt_01workflowfailed_0"
        )
    ])
    #expect(results[0].actionRun.status == .success)
    #expect(results[0].actionRun.action == "notification.show")
    #expect(results[0].auditEntry.actionRunID == results[0].actionRun.id)
    #expect(results[0].auditEntry.eventID == event.id)
}

@Test func actionRunnerDeniesReviewRequiredActionsWithoutPermission() throws {
    let event = workflowFailedEvent()
    let rule = Rule(
        id: "rul_webhook",
        name: "Webhook workflow failure",
        enabled: true,
        provider: "github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "webhook.post", parameters: ["url": "https://example.com/hooks/status"])
        ]
    )
    let match = try #require(RuleEngine.matchingRules(for: event, rules: [rule]).first)
    let runner = ActionRunner(now: { Date(timeIntervalSince1970: 1_783_433_530) })

    let result = try #require(runner.run(match).first)

    #expect(result.actionRun.status == .denied)
    #expect(result.actionRun.error == "webhook.post requires explicit write permission before it can run.")
    #expect(result.auditEntry.status == "denied")
}

@Test func fingerprintIsStableAndStateSensitive() {
    let first = EventFingerprint.make(
        EventFingerprintInput(
            provider: "github",
            eventType: "github.workflow.failed",
            resourceID: "res_status_repo",
            relevantState: "failure"
        )
    )
    let second = EventFingerprint.make(
        EventFingerprintInput(
            provider: "github",
            eventType: "github.workflow.failed",
            resourceID: "res_status_repo",
            relevantState: "failure"
        )
    )
    let different = EventFingerprint.make(
        EventFingerprintInput(
            provider: "github",
            eventType: "github.workflow.failed",
            resourceID: "res_status_repo",
            relevantState: "success"
        )
    )

    #expect(first == second)
    #expect(first != different)
    #expect(first.count == 64)
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
