import Foundation

public enum RuleOperator: String, Codable, CaseIterable, Sendable {
    case equals
    case notEquals = "not_equals"
    case contains
    case notContains = "not_contains"
    case startsWith = "starts_with"
    case endsWith = "ends_with"
    case greaterThan = "greater_than"
    case lessThan = "less_than"
    case isEmpty = "is_empty"
    case isNotEmpty = "is_not_empty"
    case matchesSeverity = "matches_severity"
}

public enum RuleValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

public struct RuleCondition: Codable, Equatable, Sendable {
    public var field: String
    public var operation: RuleOperator
    public var value: RuleValue?

    public init(field: String, operation: RuleOperator, value: RuleValue? = nil) {
        self.field = field
        self.operation = operation
        self.value = value
    }
}

public struct RuleActionDefinition: Codable, Equatable, Sendable {
    public var action: String
    public var parameters: [String: String]

    public init(action: String, parameters: [String: String] = [:]) {
        self.action = action
        self.parameters = parameters
    }
}

public enum RuleScope: String, Codable, Equatable, Sendable {
    case plugin
    case app
    case crossApp = "cross_app"
}

public struct Rule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var scope: RuleScope
    public var accountID: String?
    public var provider: String?
    public var eventType: String
    public var conditions: [RuleCondition]
    public var actions: [RuleActionDefinition]

    public init(
        id: String,
        name: String,
        enabled: Bool,
        scope: RuleScope = .plugin,
        accountID: String? = nil,
        provider: String? = nil,
        eventType: String,
        conditions: [RuleCondition],
        actions: [RuleActionDefinition]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.scope = scope
        self.accountID = accountID
        self.provider = provider
        self.eventType = eventType
        self.conditions = conditions
        self.actions = actions
    }
}

public struct RuleMatch: Equatable, Sendable {
    public var rule: Rule
    public var event: Event
    public var actions: [RuleActionDefinition]

    public init(rule: Rule, event: Event, actions: [RuleActionDefinition]) {
        self.rule = rule
        self.event = event
        self.actions = actions
    }
}

public enum RuleEngine {
    public static func matchingRules(for event: Event, rules: [Rule]) -> [RuleMatch] {
        rules.compactMap { rule in
            guard rule.enabled else { return nil }
            guard rule.eventType == event.type else { return nil }
            if let provider = rule.provider, provider != event.provider {
                return nil
            }
            guard rule.conditions.allSatisfy({ evaluate($0, event: event) }) else {
                return nil
            }
            return RuleMatch(rule: rule, event: event, actions: rule.actions)
        }
    }

    private static func evaluate(_ condition: RuleCondition, event: Event) -> Bool {
        let fieldValue = value(for: condition.field, event: event)

        switch condition.operation {
        case .equals:
            return fieldValue == condition.value
        case .notEquals:
            return fieldValue != condition.value
        case .contains:
            return contains(fieldValue, condition.value)
        case .notContains:
            return contains(fieldValue, condition.value) == false
        case .startsWith:
            return string(fieldValue)?.hasPrefix(string(condition.value) ?? "") == true
        case .endsWith:
            return string(fieldValue)?.hasSuffix(string(condition.value) ?? "") == true
        case .greaterThan:
            return compare(fieldValue, condition.value) { $0 > $1 }
        case .lessThan:
            return compare(fieldValue, condition.value) { $0 < $1 }
        case .isEmpty:
            return isEmpty(fieldValue)
        case .isNotEmpty:
            return isEmpty(fieldValue) == false
        case .matchesSeverity:
            guard case .string(let threshold)? = condition.value, let severity = Severity(rawValue: threshold) else {
                return false
            }
            return event.severity >= severity
        }
    }

    private static func value(for field: String, event: Event) -> RuleValue? {
        switch field {
        case "provider": .string(event.provider)
        case "type", "eventType": .string(event.type)
        case "resourceID", "resourceId", "resource_id": .string(event.resourceID)
        case "resourceName", "resource_name": .string(event.resourceName)
        case "severity": .string(event.severity.rawValue)
        case "title": .string(event.title)
        case "summary": .string(event.summary)
        case "fingerprint": .string(event.fingerprint)
        case "actionURL", "actionUrl", "action_url":
            event.actionURL.map { .string($0.absoluteString) }
        default:
            nil
        }
    }

    private static func contains(_ lhs: RuleValue?, _ rhs: RuleValue?) -> Bool {
        guard let left = string(lhs), let right = string(rhs) else { return false }
        return left.localizedCaseInsensitiveContains(right)
    }

    private static func compare(_ lhs: RuleValue?, _ rhs: RuleValue?, _ predicate: (Double, Double) -> Bool) -> Bool {
        guard case .number(let left)? = lhs, case .number(let right)? = rhs else { return false }
        return predicate(left, right)
    }

    private static func string(_ value: RuleValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        return string
    }

    private static func isEmpty(_ value: RuleValue?) -> Bool {
        switch value {
        case nil, .null:
            true
        case .string(let value):
            value.isEmpty
        case .number, .bool:
            false
        }
    }
}
