import Foundation

public struct PluginPackageDefinition: Equatable, Sendable {
    public var auth: PackagedPluginAuth?
    public var setup: PackagedPluginSetup?
    public var triggers: [PackagedPluginTrigger]
    public var requests: PackagedPluginRequests
    public var mappings: PackagedPluginMappings
    public var rulePresets: [PackagedRulePreset]

    public init(
        auth: PackagedPluginAuth? = nil,
        setup: PackagedPluginSetup? = nil,
        triggers: [PackagedPluginTrigger] = [],
        requests: PackagedPluginRequests = PackagedPluginRequests(),
        mappings: PackagedPluginMappings = PackagedPluginMappings(),
        rulePresets: [PackagedRulePreset] = []
    ) {
        self.auth = auth
        self.setup = setup
        self.triggers = triggers
        self.requests = requests
        self.mappings = mappings
        self.rulePresets = rulePresets
    }

    public static func decode(from packageData: Data) throws -> PluginPackageDefinition {
        let archive = try StoredZipArchive(data: packageData)
        let decoder = JSONDecoder()

        let auth = try archive.file(named: "auth.json").map { data in
            try decoder.decode(PackagedPluginAuth.self, from: data)
        }

        let setup = try archive.file(named: "setup.schema.json").map { data in
            try decoder.decode(PackagedPluginSetup.self, from: data)
        }

        let triggers = try archive.file(named: "triggers.json").map { data in
            try decoder.decode(PackagedPluginTriggersFile.self, from: data).triggers
        } ?? []

        let requests = try archive.file(named: "requests.json").map { data in
            try decoder.decode(PackagedPluginRequests.self, from: data)
        } ?? PackagedPluginRequests()

        let mappings = try archive.file(named: "mappings.json").map { data in
            try decoder.decode(PackagedPluginMappings.self, from: data)
        } ?? PackagedPluginMappings()

        let presets = try archive.file(named: "rules.presets.json").map { data in
            try decoder.decode(PackagedRulePresetsFile.self, from: data).presets
        } ?? []

        return PluginPackageDefinition(auth: auth, setup: setup, triggers: triggers, requests: requests, mappings: mappings, rulePresets: presets)
    }
}

public struct PackagedPluginAuth: Codable, Equatable, Sendable {
    public var type: AuthKind
    public var fields: [PackagedPluginSetupField]

    public init(type: AuthKind, fields: [PackagedPluginSetupField] = []) {
        self.type = type
        self.fields = fields
    }
}

public struct PackagedPluginSetup: Codable, Equatable, Sendable {
    public var title: String
    public var description: String?
    public var fields: [PackagedPluginSetupField]

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case fields
    }

    public init(title: String, description: String? = nil, fields: [PackagedPluginSetupField]) {
        self.title = title
        self.description = description
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Setup"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        fields = try container.decode([PackagedPluginSetupField].self, forKey: .fields)
    }
}

public struct PackagedPluginSetupField: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var type: PackagedPluginSetupFieldType
    public var placeholder: String?
    public var help: String?
    public var required: Bool
    public var defaultValue: String?
    public var options: [PackagedPluginSetupFieldOption]

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case label
        case type
        case placeholder
        case help
        case required
        case `default`
        case defaultValue
        case options
    }

    public init(
        id: String,
        label: String,
        type: PackagedPluginSetupFieldType,
        placeholder: String? = nil,
        help: String? = nil,
        required: Bool = false,
        defaultValue: String? = nil,
        options: [PackagedPluginSetupFieldOption] = []
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.placeholder = placeholder
        self.help = help
        self.required = required
        self.defaultValue = defaultValue
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .key)
            ?? container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decode(PackagedPluginSetupFieldType.self, forKey: .type)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        help = try container.decodeIfPresent(String.self, forKey: .help)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        defaultValue = try container.decodeIfPresent(PluginJSONValue.self, forKey: .default)?.stringValue
            ?? container.decodeIfPresent(String.self, forKey: .defaultValue)
        options = try container.decodeIfPresent([PackagedPluginSetupFieldOption].self, forKey: .options) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .key)
        try container.encode(label, forKey: .label)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        try container.encodeIfPresent(help, forKey: .help)
        try container.encode(required, forKey: .required)
        try container.encodeIfPresent(defaultValue, forKey: .default)
        if options.isEmpty == false {
            try container.encode(options, forKey: .options)
        }
    }
}

public enum PackagedPluginSetupFieldType: String, Codable, Equatable, Sendable {
    case text
    case secret
    case secretFile = "secret-file"
    case url
    case hostname
    case number
    case toggle
    case select
}

public struct PackagedPluginSetupFieldOption: Codable, Equatable, Sendable {
    public var value: String
    public var label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct PackagedPluginTrigger: Decodable, Equatable, Sendable {
    public var id: String
    public var type: TriggerKind
    public var label: String
    public var defaultSchedule: String?
    public var request: String?
    public var path: String?
    public var eventType: String?

    public init(
        id: String,
        type: TriggerKind,
        label: String,
        defaultSchedule: String? = nil,
        request: String? = nil,
        path: String? = nil,
        eventType: String? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.defaultSchedule = defaultSchedule
        self.request = request
        self.path = path
        self.eventType = eventType
    }
}

public struct PackagedPluginRequests: Decodable, Equatable, Sendable {
    public var requests: [String: PackagedPluginRequest]

    public init(requests: [String: PackagedPluginRequest] = [:]) {
        self.requests = requests
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        requests = try container.decodeIfPresent([String: PackagedPluginRequest].self, forKey: DynamicCodingKey("requests")) ?? [:]
    }
}

public struct PackagedPluginRequest: Decodable, Equatable, Sendable {
    public var method: String
    public var url: String
    public var auth: String?
    public var query: [String: String]
    public var timeoutSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case method
        case url
        case auth
        case query
        case timeoutSeconds
    }

    public init(
        method: String = "GET",
        url: String,
        auth: String? = nil,
        query: [String: String] = [:],
        timeoutSeconds: TimeInterval? = nil
    ) {
        self.method = method
        self.url = url
        self.auth = auth
        self.query = query
        self.timeoutSeconds = timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "GET"
        url = try container.decode(String.self, forKey: .url)
        auth = try container.decodeIfPresent(String.self, forKey: .auth)
        query = try container.decodeIfPresent([String: String].self, forKey: .query) ?? [:]
        timeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds)
    }
}

public struct PackagedPluginMappings: Decodable, Equatable, Sendable {
    public var resources: [PackagedResourceMapping]
    public var events: [PackagedEventMapping]
    public var metrics: [PackagedMetricMapping]

    public init(
        resources: [PackagedResourceMapping] = [],
        events: [PackagedEventMapping] = [],
        metrics: [PackagedMetricMapping] = []
    ) {
        self.resources = resources
        self.events = events
        self.metrics = metrics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        resources = try container.decodeIfPresent([PackagedResourceMapping].self, forKey: DynamicCodingKey("resources")) ?? []
        events = try container.decodeIfPresent([PackagedEventMapping].self, forKey: DynamicCodingKey("events")) ?? []
        metrics = try container.decodeIfPresent([PackagedMetricMapping].self, forKey: DynamicCodingKey("metrics")) ?? []
    }
}

public struct PackagedResourceMapping: Decodable, Equatable, Sendable {
    public var type: String
    public var request: String
    public var source: String?
    public var id: String
    public var name: String
    public var fields: [String: String]
    public var actionURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case request
        case source
        case items
        case id
        case name
        case fields
        case actionURL = "actionUrl"
    }

    public init(
        type: String,
        request: String,
        source: String? = nil,
        id: String,
        name: String,
        fields: [String: String] = [:],
        actionURL: String? = nil
    ) {
        self.type = type
        self.request = request
        self.source = source
        self.id = id
        self.name = name
        self.fields = fields
        self.actionURL = actionURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        request = try container.decode(String.self, forKey: .request)
        source = try container.decodeIfPresent(String.self, forKey: .source)
            ?? container.decodeIfPresent(String.self, forKey: .items)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fields = try container.decodeIfPresent([String: String].self, forKey: .fields) ?? [:]
        actionURL = try container.decodeIfPresent(String.self, forKey: .actionURL)
    }
}

public struct PackagedEventMapping: Decodable, Equatable, Sendable {
    public var type: String
    public var request: String
    public var source: String?
    public var when: PackagedMappingCondition?
    public var resourceID: String
    public var title: String
    public var summary: String
    public var severity: PackagedEventSeverity
    public var actionURL: String?
    public var timestamp: String?

    enum CodingKeys: String, CodingKey {
        case type
        case request
        case source
        case items
        case when
        case resourceID = "resourceId"
        case title
        case summary
        case severity
        case actionURL = "actionUrl"
        case timestamp
    }

    public init(
        type: String,
        request: String,
        source: String? = nil,
        when: PackagedMappingCondition? = nil,
        resourceID: String,
        title: String,
        summary: String,
        severity: PackagedEventSeverity,
        actionURL: String? = nil,
        timestamp: String? = nil
    ) {
        self.type = type
        self.request = request
        self.source = source
        self.when = when
        self.resourceID = resourceID
        self.title = title
        self.summary = summary
        self.severity = severity
        self.actionURL = actionURL
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        request = try container.decode(String.self, forKey: .request)
        source = try container.decodeIfPresent(String.self, forKey: .source)
            ?? container.decodeIfPresent(String.self, forKey: .items)
        when = try container.decodeIfPresent(PackagedMappingCondition.self, forKey: .when)
        resourceID = try container.decode(String.self, forKey: .resourceID)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        severity = try container.decode(PackagedEventSeverity.self, forKey: .severity)
        actionURL = try container.decodeIfPresent(String.self, forKey: .actionURL)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
    }
}

public struct PackagedMetricMapping: Decodable, Equatable, Sendable {
    public var request: String
    public var source: String?
    public var name: String
    public var resourceID: String
    public var value: String
    public var unit: String?
    public var timestamp: String?

    enum CodingKeys: String, CodingKey {
        case request
        case source
        case name
        case resourceID = "resourceId"
        case value
        case unit
        case timestamp
    }

    public init(
        request: String = "",
        source: String? = nil,
        name: String,
        resourceID: String,
        value: String,
        unit: String? = nil,
        timestamp: String? = nil
    ) {
        self.request = request
        self.source = source
        self.name = name
        self.resourceID = resourceID
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decodeIfPresent(String.self, forKey: .request) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source)
        name = try container.decode(String.self, forKey: .name)
        resourceID = try container.decode(String.self, forKey: .resourceID)
        value = try container.decode(String.self, forKey: .value)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
    }
}

public enum PackagedMappingCondition: Decodable, Equatable, Sendable {
    case shorthand(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = .shorthand(try container.decode(String.self))
    }
}

public enum PackagedEventSeverity: Decodable, Equatable, Sendable {
    case fixed(Severity)

    public init(_ severity: Severity) {
        self = .fixed(severity)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = .fixed(try container.decode(Severity.self))
    }
}

public struct PackagedRulePreset: Decodable, Equatable, Sendable {
    public var name: String
    public var description: String?
    public var when: PackagedRuleWhen
    public var conditions: [PackagedRuleCondition]
    public var actions: [PackagedRuleAction]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case when
        case conditions = "if"
        case actions = "then"
    }

    public init(
        name: String,
        description: String? = nil,
        when: PackagedRuleWhen,
        conditions: [PackagedRuleCondition] = [],
        actions: [PackagedRuleAction]
    ) {
        self.name = name
        self.description = description
        self.when = when
        self.conditions = conditions
        self.actions = actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        when = try container.decode(PackagedRuleWhen.self, forKey: .when)
        conditions = try container.decodeIfPresent([PackagedRuleCondition].self, forKey: .conditions) ?? []
        actions = try container.decode([PackagedRuleAction].self, forKey: .actions)
    }
}

public struct PackagedRuleWhen: Decodable, Equatable, Sendable {
    public var eventType: String
    public var provider: String?

    public init(eventType: String, provider: String? = nil) {
        self.eventType = eventType
        self.provider = provider
    }
}

public struct PackagedRuleCondition: Decodable, Equatable, Sendable {
    public var field: String
    public var operation: RuleOperator
    public var value: RuleValue?

    enum CodingKeys: String, CodingKey {
        case field
        case operation = "operator"
        case value
    }

    public init(field: String, operation: RuleOperator, value: RuleValue? = nil) {
        self.field = field
        self.operation = operation
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        field = try container.decode(String.self, forKey: .field)
        operation = try container.decode(RuleOperator.self, forKey: .operation)
        value = try container.decodeIfPresent(PluginJSONValue.self, forKey: .value)?.ruleValue
    }
}

public struct PackagedRuleAction: Decodable, Equatable, Sendable {
    public var action: String
    public var parameters: [String: String]

    public init(action: String, parameters: [String: String] = [:]) {
        self.action = action
        self.parameters = parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        action = try container.decode(String.self, forKey: DynamicCodingKey("action"))
        var parameters: [String: String] = [:]

        for key in container.allKeys where key.stringValue != "action" {
            parameters[key.stringValue] = try container.decode(PluginJSONValue.self, forKey: key).stringValue
        }

        self.parameters = parameters
    }
}

private struct PackagedPluginTriggersFile: Decodable {
    var triggers: [PackagedPluginTrigger]
}

private struct PackagedRulePresetsFile: Decodable {
    var presets: [PackagedRulePreset]
}

private enum PluginJSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var ruleValue: RuleValue {
        switch self {
        case .string(let value): .string(value)
        case .number(let value): .number(value)
        case .bool(let value): .bool(value)
        case .null: .null
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            if value.rounded() == value {
                String(Int64(value))
            } else {
                String(value)
            }
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            ""
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct StoredZipArchive {
    private var files: [String: Data] = [:]

    init(data: Data) throws {
        var offset = 0

        while offset + 30 <= data.count {
            let signature = try data.uint32(at: offset)
            if signature == 0x0201_4b50 || signature == 0x0605_4b50 {
                break
            }
            guard signature == 0x0403_4b50 else {
                throw PluginPackageDefinitionError.invalidZipSignature
            }

            let compression = try data.uint16(at: offset + 8)
            guard compression == 0 else {
                throw PluginPackageDefinitionError.unsupportedCompression
            }

            let compressedSize = Int(try data.uint32(at: offset + 18))
            let uncompressedSize = Int(try data.uint32(at: offset + 22))
            let nameLength = Int(try data.uint16(at: offset + 26))
            let extraLength = Int(try data.uint16(at: offset + 28))
            let nameStart = offset + 30
            let dataStart = nameStart + nameLength + extraLength
            let dataEnd = dataStart + compressedSize

            guard nameStart <= data.count, dataStart <= data.count, dataEnd <= data.count else {
                throw PluginPackageDefinitionError.truncatedZipEntry
            }
            guard compressedSize == uncompressedSize else {
                throw PluginPackageDefinitionError.unsupportedCompression
            }

            let nameData = data.subdata(in: nameStart ..< nameStart + nameLength)
            guard let name = String(data: nameData, encoding: .utf8), name.isEmpty == false else {
                throw PluginPackageDefinitionError.invalidZipEntryName
            }

            files[name] = data.subdata(in: dataStart ..< dataEnd)
            offset = dataEnd
        }
    }

    func file(named name: String) -> Data? {
        files[name]
    }
}

public enum PluginPackageDefinitionError: Error, Equatable, LocalizedError, Sendable {
    case invalidZipSignature
    case unsupportedCompression
    case truncatedZipEntry
    case invalidZipEntryName

    public var errorDescription: String? {
        switch self {
        case .invalidZipSignature:
            "Plugin package is not a supported Status plugin archive."
        case .unsupportedCompression:
            "Plugin package uses unsupported compression."
        case .truncatedZipEntry:
            "Plugin package archive is truncated."
        case .invalidZipEntryName:
            "Plugin package contains an invalid file name."
        }
    }
}

private extension Data {
    func uint16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else {
            throw PluginPackageDefinitionError.truncatedZipEntry
        }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw PluginPackageDefinitionError.truncatedZipEntry
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
