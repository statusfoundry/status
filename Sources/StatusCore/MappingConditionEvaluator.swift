import Foundation

public enum MappingOperator: String, Codable, CaseIterable, Sendable {
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
    case changed
    case changedTo = "changed_to"
    case changedFrom = "changed_from"
}

public struct MappingCondition: Codable, Equatable, Sendable {
    public var path: String
    public var operation: MappingOperator
    public var value: String?

    public init(path: String, operation: MappingOperator, value: String? = nil) {
        self.path = path
        self.operation = operation
        self.value = value
    }
}

public enum MappingConditionEvaluator {
    public static func evaluate(
        _ condition: MappingCondition,
        currentState: [String: String],
        previousState: [String: String]?
    ) -> Bool {
        let field = stateFieldName(from: condition.path)
        let current = currentState[field]
        let previous = previousState?[field]

        switch condition.operation {
        case .equals:
            return current == condition.value
        case .notEquals:
            return current != condition.value
        case .contains:
            return contains(current, condition.value)
        case .notContains:
            return contains(current, condition.value) == false
        case .startsWith:
            return current?.hasPrefix(condition.value ?? "") == true
        case .endsWith:
            return current?.hasSuffix(condition.value ?? "") == true
        case .greaterThan:
            return compare(current, condition.value) { $0 > $1 }
        case .lessThan:
            return compare(current, condition.value) { $0 < $1 }
        case .isEmpty:
            return isEmpty(current)
        case .isNotEmpty:
            return isEmpty(current) == false
        case .changed:
            guard let previous else { return false }
            return previous != current
        case .changedTo:
            guard current == condition.value else { return false }
            return previous != current
        case .changedFrom:
            guard let previous else { return false }
            return previous == condition.value && current != previous
        }
    }

    public static func evaluateAll(
        _ conditions: [MappingCondition],
        currentState: [String: String],
        previousState: [String: String]?
    ) -> Bool {
        conditions.allSatisfy {
            evaluate($0, currentState: currentState, previousState: previousState)
        }
    }

    public static func stateFieldName(from path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$") else { return trimmed }

        if let bracketStart = trimmed.lastIndex(of: "["),
           let bracketEnd = trimmed.lastIndex(of: "]"),
           bracketStart < bracketEnd {
            let raw = trimmed[trimmed.index(after: bracketStart)..<bracketEnd]
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }

        if let lastDot = trimmed.lastIndex(of: ".") {
            return String(trimmed[trimmed.index(after: lastDot)...])
        }

        return trimmed
    }

    private static func contains(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.localizedCaseInsensitiveContains(rhs)
    }

    private static func compare(_ lhs: String?, _ rhs: String?, _ predicate: (Double, Double) -> Bool) -> Bool {
        guard let lhs, let rhs, let left = Double(lhs), let right = Double(rhs) else {
            return false
        }
        return predicate(left, right)
    }

    private static func isEmpty(_ value: String?) -> Bool {
        value?.isEmpty ?? true
    }
}
