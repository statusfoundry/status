import Foundation
import Testing
@testable import StatusCore
@testable import StatusUI

@MainActor
@Test func rulesViewModelSavesCrossAppRuleDrafts() throws {
    var storedRules = [Rule]()
    let viewModel = RulesViewModel {
        storedRules
    } saveRule: { rule in
        storedRules.removeAll { $0.id == rule.id }
        storedRules.append(rule)
    }

    viewModel.saveCrossAppRule(
        existingRuleID: nil,
        name: "Failed workflow creates inbox item",
        provider: " github ",
        eventType: " github.workflow.failed ",
        conditions: [
            RuleCondition(field: "severity", operation: .matchesSeverity, value: .string("warning"))
        ],
        actions: [
            RuleActionDefinition(action: "status.inbox.add"),
            RuleActionDefinition(action: "notification.show", parameters: ["title": "{{event.title}}"])
        ],
        enabled: true
    )

    let rule = try #require(storedRules.first)
    #expect(rule.scope == .crossApp)
    #expect(rule.accountID == nil)
    #expect(rule.provider == "github")
    #expect(rule.eventType == "github.workflow.failed")
    #expect(rule.enabled)
    #expect(rule.conditions.count == 1)
    #expect(rule.actions.map(\.action) == ["status.inbox.add", "notification.show"])
    #expect(viewModel.rules.count == 1)
}

@MainActor
@Test func rulesViewModelLoadsProviderActionOptionsAndSavesParameters() throws {
    var storedRules = [Rule]()
    let providerAction = CrossAppRuleActionOption(
        action: "jira.createIssue",
        label: "Create Jira issue",
        provider: "com.status.jira",
        inputFields: [
            PackagedPluginActionInputField(
                key: "summary",
                label: "Summary",
                type: .template,
                required: true,
                defaultValue: "{{event.title}}"
            )
        ],
        safety: .reviewRequired
    )
    let viewModel = RulesViewModel {
        storedRules
    } loadActionOptions: {
        CrossAppRuleActionOption.builtIn + [providerAction]
    } saveRule: { rule in
        storedRules.removeAll { $0.id == rule.id }
        storedRules.append(rule)
    }

    viewModel.reload()

    #expect(viewModel.actionOptions.contains(providerAction))

    viewModel.saveCrossAppRule(
        existingRuleID: nil,
        name: "GitHub failure creates Jira issue",
        provider: "com.status.github",
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [
            RuleActionDefinition(action: "jira.createIssue", parameters: ["summary": "{{event.title}}"])
        ],
        enabled: true
    )

    let rule = try #require(storedRules.first)
    #expect(rule.scope == .crossApp)
    #expect(rule.provider == "com.status.github")
    #expect(rule.actions == [
        RuleActionDefinition(action: "jira.createIssue", parameters: ["summary": "{{event.title}}"])
    ])
}

@MainActor
@Test func rulesViewModelDeletesCrossAppRules() throws {
    let rule = Rule(
        id: "rule_cross_app_delete_me",
        name: "Delete me",
        enabled: false,
        scope: .crossApp,
        eventType: "github.workflow.failed",
        conditions: [],
        actions: [RuleActionDefinition(action: "status.inbox.add")]
    )
    var storedRules = [rule]
    let viewModel = RulesViewModel(
        loadRules: { storedRules },
        saveRule: { _ in },
        deleteRule: { deletedRule in
            storedRules.removeAll { $0.id == deletedRule.id }
        }
    )

    viewModel.reload()
    #expect(viewModel.rules.count == 1)

    viewModel.delete(rule)

    #expect(storedRules.isEmpty)
    #expect(viewModel.rules.isEmpty)
}
