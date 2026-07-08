import Foundation

public struct PluginMappingExecutionInput: Equatable, Sendable {
    public var pluginID: String
    public var accountID: String
    public var provider: String
    public var requestID: String
    public var payload: MappingJSONValue
    public var capturedAt: Date
    public var account: MappingJSONValue?
    public var trigger: MappingJSONValue?

    public init(
        pluginID: String,
        accountID: String,
        provider: String,
        requestID: String,
        payload: MappingJSONValue,
        capturedAt: Date,
        account: MappingJSONValue? = nil,
        trigger: MappingJSONValue? = nil
    ) {
        self.pluginID = pluginID
        self.accountID = accountID
        self.provider = provider
        self.requestID = requestID
        self.payload = payload
        self.capturedAt = capturedAt
        self.account = account
        self.trigger = trigger
    }
}

public struct MappedPluginResource: Equatable, Sendable {
    public var resource: Resource
    public var state: [String: String]

    public init(resource: Resource, state: [String: String]) {
        self.resource = resource
        self.state = state
    }
}

public struct MappedPluginMetric: Equatable, Sendable {
    public var metric: Metric
    public var pointValue: Double
    public var pointTimestamp: Date

    public init(metric: Metric, pointValue: Double, pointTimestamp: Date) {
        self.metric = metric
        self.pointValue = pointValue
        self.pointTimestamp = pointTimestamp
    }
}

public struct PluginMappingExecutionOutput: Equatable, Sendable {
    public var resources: [MappedPluginResource]
    public var events: [Event]
    public var metrics: [MappedPluginMetric]

    public init(resources: [MappedPluginResource], events: [Event], metrics: [MappedPluginMetric] = []) {
        self.resources = resources
        self.events = events
        self.metrics = metrics
    }
}

public enum PluginMappingExecutionError: Error, Equatable, LocalizedError, Sendable {
    case invalidCondition(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCondition(let condition):
            "Plugin mapping condition is invalid: \(condition)"
        }
    }
}

public enum PluginMappingExecutor {
    public static func execute(
        _ mappings: PackagedPluginMappings,
        input: PluginMappingExecutionInput
    ) throws -> PluginMappingExecutionOutput {
        let resources = try mappings.resources
            .filter { $0.request == input.requestID }
            .flatMap { try executeResourceMapping($0, input: input) }

        let events = try mappings.events
            .filter { $0.request == input.requestID }
            .flatMap { try executeEventMapping($0, input: input) }

        let metrics = try mappings.metrics
            .filter { $0.request.isEmpty || $0.request == input.requestID }
            .flatMap { try executeMetricMapping($0, input: input) }

        return PluginMappingExecutionOutput(resources: resources, events: events, metrics: metrics)
    }

    private static func executeResourceMapping(
        _ mapping: PackagedResourceMapping,
        input: PluginMappingExecutionInput
    ) throws -> [MappedPluginResource] {
        try items(for: mapping.source, payload: input.payload).compactMap { item in
            let baseContext = templateContext(item: item, input: input)
            guard let rawID = try expression(mapping.id, item: item, context: baseContext), rawID.isEmpty == false,
                  let name = try expression(mapping.name, item: item, context: baseContext), name.isEmpty == false else {
                return nil
            }

            let resourceID = normalizedResourceID(accountID: input.accountID, rawID: rawID)
            var resourceScope = MappingJSONValue.object([
                "id": .string(resourceID),
                "rawId": .string(rawID),
                "type": .string(mapping.type),
                "name": .string(name)
            ])
            let context = templateContext(item: item, input: input, resource: resourceScope)
            let actionURLString = try mapping.actionURL.flatMap { try expression($0, item: item, context: context) }
            if let actionURLString, actionURLString.isEmpty == false {
                resourceScope = resourceScope.setting("actionUrl", value: .string(actionURLString))
            }

            var state = [
                "id": rawID,
                "name": name
            ]
            for (field, valueExpression) in mapping.fields {
                if let value = try expression(valueExpression, item: item, context: context) {
                    state[field] = value
                }
            }

            return MappedPluginResource(
                resource: Resource(
                    id: resourceID,
                    accountID: input.accountID,
                    pluginID: input.pluginID,
                    type: mapping.type,
                    name: name,
                    actionURL: actionURLString.flatMap(URL.init(string:))
                ),
                state: state
            )
        }
    }

    private static func executeEventMapping(
        _ mapping: PackagedEventMapping,
        input: PluginMappingExecutionInput
    ) throws -> [Event] {
        try items(for: mapping.source, payload: input.payload).compactMap { item in
            if let condition = mapping.when, try evaluate(condition, item: item) == false {
                return nil
            }

            let baseContext = templateContext(item: item, input: input)
            guard let rawResourceID = try expression(mapping.resourceID, item: item, context: baseContext),
                  rawResourceID.isEmpty == false else {
                return nil
            }

            let resourceID = normalizedResourceID(accountID: input.accountID, rawID: rawResourceID)
            let resourceScope = MappingJSONValue.object([
                "id": .string(resourceID),
                "rawId": .string(rawResourceID),
                "name": .string(rawResourceID)
            ])
            let eventSeed = MappingJSONValue.object([
                "type": .string(mapping.type),
                "resourceId": .string(rawResourceID)
            ])
            let context = templateContext(item: item, input: input, resource: resourceScope, event: eventSeed)
            let title = try expression(mapping.title, item: item, context: context) ?? mapping.title
            let summary = try expression(mapping.summary, item: item, context: context) ?? ""
            let actionURLString = try mapping.actionURL.flatMap { try expression($0, item: item, context: context) }
            let timestampString = try mapping.timestamp.flatMap { try expression($0, item: item, context: context) }
            let timestamp = timestampString.flatMap(parseDate) ?? input.capturedAt
            let severity = fixedSeverity(mapping.severity)
            let fingerprint = EventFingerprint.make(
                EventFingerprintInput(
                    provider: input.provider,
                    eventType: mapping.type,
                    resourceID: resourceID,
                    relevantState: "\(severity.rawValue)|\(title)|\(summary)|\(actionURLString ?? "")"
                )
            )

            return Event(
                id: "evt_" + fingerprint.prefix(26),
                provider: input.provider,
                type: mapping.type,
                resourceID: resourceID,
                resourceName: rawResourceID,
                severity: severity,
                title: title,
                summary: summary,
                timestamp: timestamp,
                actionURL: actionURLString.flatMap(URL.init(string:)),
                fingerprint: fingerprint
            )
        }
    }

    private static func executeMetricMapping(
        _ mapping: PackagedMetricMapping,
        input: PluginMappingExecutionInput
    ) throws -> [MappedPluginMetric] {
        try items(for: mapping.source, payload: input.payload).compactMap { item in
            let context = templateContext(item: item, input: input)
            guard let rawResourceID = try expression(mapping.resourceID, item: item, context: context),
                  rawResourceID.isEmpty == false,
                  let valueString = try expression(mapping.value, item: item, context: context),
                  let pointValue = Double(valueString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }

            let timestampString = try mapping.timestamp.flatMap { try expression($0, item: item, context: context) }
            let pointTimestamp = timestampString.flatMap(parseDate) ?? input.capturedAt
            let resourceID = normalizedResourceID(accountID: input.accountID, rawID: rawResourceID)
            let metricID = normalizedMetricID(resourceID: resourceID, name: mapping.name)

            return MappedPluginMetric(
                metric: Metric(
                    id: metricID,
                    resourceID: resourceID,
                    label: mapping.name,
                    value: formatMetricValue(pointValue, unit: mapping.unit),
                    delta: mapping.unit,
                    severity: .ok
                ),
                pointValue: pointValue,
                pointTimestamp: pointTimestamp
            )
        }
    }

    private static func items(for source: String?, payload: MappingJSONValue) throws -> [MappingJSONValue] {
        try MappingSelector(source ?? "$").resolveItems(in: payload)
    }

    private static func expression(
        _ rawExpression: String,
        item: MappingJSONValue,
        context: MappingTemplateContext
    ) throws -> String? {
        if rawExpression.contains("{{") {
            return MappingTemplateRenderer.render(rawExpression, context: context)
        }
        if rawExpression.hasPrefix("$") {
            return try MappingSelector(rawExpression).resolve(in: item)?.scalarString
        }
        return rawExpression
    }

    private static func templateContext(
        item: MappingJSONValue,
        input: PluginMappingExecutionInput,
        resource: MappingJSONValue? = nil,
        event: MappingJSONValue? = nil
    ) -> MappingTemplateContext {
        var scopes: [String: MappingJSONValue] = ["item": item]
        if let account = input.account {
            scopes["account"] = account
        }
        if let trigger = input.trigger {
            scopes["trigger"] = trigger
        }
        if let resource {
            scopes["resource"] = resource
        }
        if let event {
            scopes["event"] = event
        }
        return MappingTemplateContext(scopes: scopes)
    }

    private static func evaluate(_ condition: PackagedMappingCondition, item: MappingJSONValue) throws -> Bool {
        switch condition {
        case .shorthand(let expression):
            try evaluateOrExpression(expression, item: item)
        }
    }

    private static func evaluateOrExpression(_ expression: String, item: MappingJSONValue) throws -> Bool {
        let groups = expression.components(separatedBy: " || ")
        return try groups.contains { group in
            try evaluateAndExpression(group, item: item)
        }
    }

    private static func evaluateAndExpression(_ expression: String, item: MappingJSONValue) throws -> Bool {
        let terms = expression.components(separatedBy: " && ")
        return try terms.allSatisfy { term in
            try evaluateTerm(term, item: item)
        }
    }

    private static func evaluateTerm(_ rawTerm: String, item: MappingJSONValue) throws -> Bool {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let operators = [">=", "<=", "==", "!=", ">", "<"]
        guard let operation = operators.first(where: { term.contains(" \($0) ") }) else {
            throw PluginMappingExecutionError.invalidCondition(rawTerm)
        }
        let pieces = term.components(separatedBy: " \(operation) ")
        guard pieces.count == 2 else {
            throw PluginMappingExecutionError.invalidCondition(rawTerm)
        }

        let left = try MappingSelector(pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)).resolve(in: item)
        let right = literal(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines))

        switch operation {
        case "==":
            return left == right
        case "!=":
            return left != right
        case ">":
            return number(left).map { leftNumber in number(right).map { leftNumber > $0 } ?? false } ?? false
        case "<":
            return number(left).map { leftNumber in number(right).map { leftNumber < $0 } ?? false } ?? false
        case ">=":
            return number(left).map { leftNumber in number(right).map { leftNumber >= $0 } ?? false } ?? false
        case "<=":
            return number(left).map { leftNumber in number(right).map { leftNumber <= $0 } ?? false } ?? false
        default:
            throw PluginMappingExecutionError.invalidCondition(rawTerm)
        }
    }

    private static func literal(_ rawValue: String) -> MappingJSONValue {
        if rawValue == "true" {
            return .bool(true)
        }
        if rawValue == "false" {
            return .bool(false)
        }
        if rawValue == "null" {
            return .null
        }
        if rawValue.hasPrefix("'"), rawValue.hasSuffix("'"), rawValue.count >= 2 {
            return .string(String(rawValue.dropFirst().dropLast()))
        }
        if let value = Double(rawValue) {
            return .number(value)
        }
        return .string(rawValue)
    }

    private static func number(_ value: MappingJSONValue?) -> Double? {
        switch value {
        case .number(let number):
            number
        case .string(let string):
            Double(string)
        case .bool, .object, .array, .null, nil:
            nil
        }
    }

    private static func fixedSeverity(_ severity: PackagedEventSeverity) -> Severity {
        switch severity {
        case .fixed(let severity):
            severity
        }
    }

    private static func normalizedResourceID(accountID: String, rawID: String) -> String {
        "\(accountID):\(rawID)"
    }

    private static func normalizedMetricID(resourceID: String, name: String) -> String {
        "\(resourceID):metric:\(name)"
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9:_\-\.]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func formatMetricValue(_ value: Double, unit: String?) -> String {
        let formatted: String
        if value.rounded() == value {
            formatted = String(Int64(value))
        } else {
            formatted = String(value)
        }
        guard let unit, unit.isEmpty == false, unit != "count" else {
            return formatted
        }
        return "\(formatted) \(unit)"
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private extension MappingJSONValue {
    func setting(_ key: String, value: MappingJSONValue) -> MappingJSONValue {
        guard case .object(var object) = self else { return self }
        object[key] = value
        return .object(object)
    }
}
