import Foundation

public enum MappingJSONValue: Equatable, Sendable {
    case object([String: MappingJSONValue])
    case array([MappingJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public var scalarString: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value.rounded() == value ? String(Int64(value)) : String(value)
        case .bool(let value):
            value ? "true" : "false"
        case .null, .object, .array:
            nil
        }
    }
}

extension MappingJSONValue: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MappingJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([MappingJSONValue].self))
        }
    }
}

public enum MappingSelectorError: Error, Equatable, LocalizedError, Sendable {
    case emptySelector
    case selectorMustStartAtRoot(String)
    case unsupportedSyntax(String)
    case wildcardMustBeTail(String)
    case invalidArrayIndex(String)
    case unterminatedBracket(String)

    public var errorDescription: String? {
        switch self {
        case .emptySelector:
            "Mapping selector is empty."
        case .selectorMustStartAtRoot(let selector):
            "Mapping selector must start at root: \(selector)"
        case .unsupportedSyntax(let selector):
            "Mapping selector uses unsupported syntax: \(selector)"
        case .wildcardMustBeTail(let selector):
            "Mapping selector wildcard is only allowed as the final step: \(selector)"
        case .invalidArrayIndex(let selector):
            "Mapping selector contains an invalid array index: \(selector)"
        case .unterminatedBracket(let selector):
            "Mapping selector contains an unterminated bracket: \(selector)"
        }
    }
}

public enum MappingSelectorStep: Equatable, Sendable {
    case field(String)
    case index(Int)
    case wildcard
}

public struct MappingSelector: Equatable, Sendable {
    public var rawValue: String
    public var steps: [MappingSelectorStep]

    public init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw MappingSelectorError.emptySelector
        }
        guard trimmed.first == "$" else {
            throw MappingSelectorError.selectorMustStartAtRoot(rawValue)
        }
        self.rawValue = trimmed
        self.steps = try Self.parse(trimmed)
    }

    public var containsWildcard: Bool {
        steps.contains(.wildcard)
    }

    public func resolve(in root: MappingJSONValue) -> MappingJSONValue? {
        var current: MappingJSONValue? = root

        for step in steps {
            guard let value = current else { return nil }
            switch (step, value) {
            case (.field(let key), .object(let object)):
                current = object[key]
            case (.index(let index), .array(let array)):
                current = array.indices.contains(index) ? array[index] : nil
            case (.wildcard, _):
                current = value
            default:
                return nil
            }
        }

        return current
    }

    public func resolveItems(in root: MappingJSONValue) -> [MappingJSONValue] {
        guard steps.last == .wildcard else {
            return resolve(in: root).map { [$0] } ?? []
        }

        let parent = MappingSelector(rawValue: rawValue, steps: Array(steps.dropLast()))
        guard case .array(let values)? = parent.resolve(in: root) else {
            return []
        }
        return values
    }

    private init(rawValue: String, steps: [MappingSelectorStep]) {
        self.rawValue = rawValue
        self.steps = steps
    }

    private static func parse(_ selector: String) throws -> [MappingSelectorStep] {
        var steps: [MappingSelectorStep] = []
        var index = selector.index(after: selector.startIndex)

        while index < selector.endIndex {
            let character = selector[index]

            if character == "." {
                index = selector.index(after: index)
                let start = index
                while index < selector.endIndex, isIdentifierCharacter(selector[index]) {
                    index = selector.index(after: index)
                }
                guard start < index else {
                    throw MappingSelectorError.unsupportedSyntax(selector)
                }
                steps.append(.field(String(selector[start..<index])))
                continue
            }

            if character == "[" {
                let bracketStart = index
                index = selector.index(after: index)
                guard index < selector.endIndex else {
                    throw MappingSelectorError.unterminatedBracket(selector)
                }

                if selector[index] == "*" {
                    index = selector.index(after: index)
                    guard index < selector.endIndex, selector[index] == "]" else {
                        throw MappingSelectorError.unsupportedSyntax(selector)
                    }
                    index = selector.index(after: index)
                    guard index == selector.endIndex else {
                        throw MappingSelectorError.wildcardMustBeTail(selector)
                    }
                    steps.append(.wildcard)
                    continue
                }

                if selector[index] == "'" {
                    index = selector.index(after: index)
                    let keyStart = index
                    while index < selector.endIndex, selector[index] != "'" {
                        index = selector.index(after: index)
                    }
                    guard index < selector.endIndex else {
                        throw MappingSelectorError.unterminatedBracket(selector)
                    }
                    let key = String(selector[keyStart..<index])
                    index = selector.index(after: index)
                    guard index < selector.endIndex, selector[index] == "]" else {
                        throw MappingSelectorError.unterminatedBracket(selector)
                    }
                    index = selector.index(after: index)
                    steps.append(.field(key))
                    continue
                }

                let numberStart = index
                while index < selector.endIndex, selector[index].isNumber {
                    index = selector.index(after: index)
                }
                guard numberStart < index, index < selector.endIndex, selector[index] == "]" else {
                    throw MappingSelectorError.invalidArrayIndex(String(selector[bracketStart...]))
                }
                let rawIndex = String(selector[numberStart..<index])
                guard let arrayIndex = Int(rawIndex) else {
                    throw MappingSelectorError.invalidArrayIndex(rawIndex)
                }
                index = selector.index(after: index)
                steps.append(.index(arrayIndex))
                continue
            }

            throw MappingSelectorError.unsupportedSyntax(selector)
        }

        if steps.dropLast().contains(.wildcard) {
            throw MappingSelectorError.wildcardMustBeTail(selector)
        }
        return steps
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

public struct MappingTemplateContext: Equatable, Sendable {
    public var scopes: [String: MappingJSONValue]

    public init(scopes: [String: MappingJSONValue]) {
        self.scopes = scopes
    }

    public func value(for path: String) -> MappingJSONValue? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".").map(String.init)
        guard parts.isEmpty == false else { return nil }

        let knownScopes = Set(["item", "resource", "event", "account", "trigger", "action"])
        let scopeName: String
        let fieldParts: ArraySlice<String>
        if knownScopes.contains(parts[0]) {
            scopeName = parts[0]
            fieldParts = parts.dropFirst()
        } else {
            scopeName = "item"
            fieldParts = parts[...]
        }

        guard var current = scopes[scopeName] else {
            return nil
        }

        for field in fieldParts {
            guard case .object(let object) = current, let next = object[field] else {
                return nil
            }
            current = next
        }
        return current
    }
}

public enum MappingTemplateRenderer {
    public static func render(_ template: String, context: MappingTemplateContext) -> String {
        var result = ""
        var index = template.startIndex

        while index < template.endIndex {
            if template[index] == "\\",
               template.index(index, offsetBy: 2, limitedBy: template.endIndex) != nil {
                let next = template.index(after: index)
                let afterNext = template.index(after: next)
                if template[next] == "{", afterNext < template.endIndex, template[afterNext] == "{" {
                    result.append("{{")
                    index = template.index(after: afterNext)
                    continue
                }
            }

            if template[index] == "{",
               let next = template.index(index, offsetBy: 1, limitedBy: template.endIndex),
               next < template.endIndex,
               template[next] == "{" {
                let placeholderStart = template.index(after: next)
                var placeholderEnd = placeholderStart
                var foundEnd: String.Index?
                while placeholderEnd < template.endIndex {
                    let closeNext = template.index(after: placeholderEnd)
                    if template[placeholderEnd] == "}", closeNext < template.endIndex, template[closeNext] == "}" {
                        foundEnd = placeholderEnd
                        break
                    }
                    placeholderEnd = template.index(after: placeholderEnd)
                }

                if let foundEnd {
                    let rawPath = String(template[placeholderStart..<foundEnd])
                    result.append(context.value(for: rawPath)?.scalarString ?? "")
                    index = template.index(foundEnd, offsetBy: 2)
                    continue
                }
            }

            result.append(template[index])
            index = template.index(after: index)
        }

        return result
    }
}
