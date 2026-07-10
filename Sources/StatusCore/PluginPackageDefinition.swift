import Foundation

public struct PluginPackageDefinition: Equatable, Sendable {
    public var auth: PackagedPluginAuth?
    public var setup: PackagedPluginSetup?
    public var readmeMarkdown: String?
    public var iconAsset: PackagedPluginIconAsset?
    public var triggers: [PackagedPluginTrigger]
    public var requests: PackagedPluginRequests
    public var events: [EventTypeDeclaration]
    public var actions: [PackagedPluginAction]
    public var mappings: PackagedPluginMappings
    public var views: [PackagedPluginView]
    public var dashboardTile: PackagedPluginDashboardTile?
    public var rulePresets: [PackagedRulePreset]

    public init(
        auth: PackagedPluginAuth? = nil,
        setup: PackagedPluginSetup? = nil,
        readmeMarkdown: String? = nil,
        iconAsset: PackagedPluginIconAsset? = nil,
        triggers: [PackagedPluginTrigger] = [],
        requests: PackagedPluginRequests = PackagedPluginRequests(),
        events: [EventTypeDeclaration] = [],
        actions: [PackagedPluginAction] = [],
        mappings: PackagedPluginMappings = PackagedPluginMappings(),
        views: [PackagedPluginView] = [],
        dashboardTile: PackagedPluginDashboardTile? = nil,
        rulePresets: [PackagedRulePreset] = []
    ) {
        self.auth = auth
        self.setup = setup
        self.readmeMarkdown = readmeMarkdown
        self.iconAsset = iconAsset
        self.triggers = triggers
        self.requests = requests
        self.events = events
        self.actions = actions
        self.mappings = mappings
        self.views = views
        self.dashboardTile = dashboardTile
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

        let readmeMarkdown = try archive.file(named: "README.md").map { data in
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw PluginPackageDefinitionError.invalidReadmeAsset("README.md")
            }
            return markdown
        }

        let iconAsset = try archive.file(named: "icon.svg").map { data in
            try PackagedPluginIconAsset(path: "icon.svg", data: data)
        }

        let triggers = try archive.file(named: "triggers.json").map { data in
            try decoder.decode(PackagedPluginTriggersFile.self, from: data).triggers
        } ?? []

        let requests = try archive.file(named: "requests.json").map { data in
            try decoder.decode(PackagedPluginRequests.self, from: data)
        } ?? PackagedPluginRequests()

        let events = try archive.file(named: "events.json").map { data in
            try decoder.decode(PackagedPluginEventsFile.self, from: data).events
        } ?? []

        let actions = try archive.file(named: "actions.json").map { data in
            try decoder.decode(PackagedPluginActionsFile.self, from: data).actions
        } ?? []

        let mappings = try archive.file(named: "mappings.json").map { data in
            try decoder.decode(PackagedPluginMappings.self, from: data)
        } ?? PackagedPluginMappings()

        let viewsFile = try archive.file(named: "views.json").map { data in
            try decoder.decode(PackagedPluginViewsFile.self, from: data)
        }
        let views = viewsFile?.views ?? []
        let dashboardTile = viewsFile?.dashboardTile

        let presets = try archive.file(named: "rules.presets.json").map { data in
            try decoder.decode(PackagedRulePresetsFile.self, from: data).presets
        } ?? []

        try validateActionRequests(actions, requests: requests)

        return PluginPackageDefinition(auth: auth, setup: setup, readmeMarkdown: readmeMarkdown, iconAsset: iconAsset, triggers: triggers, requests: requests, events: events, actions: actions, mappings: mappings, views: views, dashboardTile: dashboardTile, rulePresets: presets)
    }

    private static func validateActionRequests(_ actions: [PackagedPluginAction], requests: PackagedPluginRequests) throws {
        let requestIDs = Set(requests.requests.keys)
        for action in actions where requestIDs.contains(action.request) == false {
            throw PluginPackageDefinitionError.missingActionRequest(actionID: action.id, requestID: action.request)
        }
    }
}

public struct PackagedPluginIconAsset: Codable, Equatable, Hashable, Sendable {
    public var path: String
    public var svgText: String

    public init(path: String, svgText: String) {
        self.path = path
        self.svgText = svgText
    }

    public init(path: String, data: Data) throws {
        guard data.count <= 32 * 1024,
              let svgText = String(data: data, encoding: .utf8) else {
            throw PluginPackageDefinitionError.invalidIconAsset(path)
        }

        guard PluginSVGValidator.isSafe(svgText) else {
            throw PluginPackageDefinitionError.invalidIconAsset(path)
        }
        self.path = path
        self.svgText = svgText
    }
}

private enum PluginSVGValidator {
    private static let maxElementCount = 128
    private static let maxAttributeCount = 512
    private static let maxReferenceCount = 64
    private static let maxPathDataBytes = 16 * 1024

    static func isSafe(_ svgText: String) -> Bool {
        let trimmed = svgText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<svg") else {
            return false
        }
        let disallowedPatterns = [
            #"<(?:script|foreignObject|iframe|object|embed|audio|video|canvas|image|animate|animateMotion|animateTransform|set|mpath|feImage)\b"#,
            #"<!DOCTYPE|<!ENTITY|<\?xml-stylesheet|<html\b|<body\b"#,
            #"\son[a-z][a-z0-9_-]*\s*="#,
            #"<style\b"#,
            #"\sstyle\s*="#,
            #"\b(?:href|xlink:href)\s*=\s*(['"])\s*(?!#)[^'"]+\1"#,
            #"\b(?:src|poster|data|from|to)\s*=\s*(['"])\s*(?:https?:|data:|javascript:|mailto:|ftp:|//)[^'"]*\1"#
        ]
        for pattern in disallowedPatterns where svgText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }

        let tagPattern = try? NSRegularExpression(pattern: #"<([A-Za-z][A-Za-z0-9:_-]*)(\s[^<>]*?)?>"#, options: [])
        let attributePattern = try? NSRegularExpression(pattern: #"([A-Za-z_:][A-Za-z0-9:._-]*)\s*=\s*(['"])(.*?)\2"#, options: [])
        let idPattern = try? NSRegularExpression(pattern: #"\bid\s*=\s*(['"])(.*?)\1"#, options: [.caseInsensitive])
        let hrefPattern = try? NSRegularExpression(pattern: #"\b(?:href|xlink:href)\s*=\s*(['"])(.*?)\1"#, options: [.caseInsensitive])
        let urlPattern = try? NSRegularExpression(pattern: #"url\(\s*(['"]?)(.*?)\1\s*\)"#, options: [.caseInsensitive])
        let pathPattern = try? NSRegularExpression(pattern: #"\bd\s*=\s*(['"])(.*?)\1"#, options: [.caseInsensitive])
        guard let tagPattern, let attributePattern, let idPattern, let hrefPattern, let urlPattern, let pathPattern else {
            return false
        }

        let range = NSRange(svgText.startIndex..., in: svgText)
        let tags = tagPattern.matches(in: svgText, options: [], range: range)
        guard tags.count <= maxElementCount else {
            return false
        }

        let ids = Set(idPattern.matches(in: svgText, options: [], range: range).compactMap {
            Range($0.range(at: 2), in: svgText).map { String(svgText[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }.filter { $0.isEmpty == false })

        var references: [String] = []
        for regex in [hrefPattern, urlPattern] {
            for match in regex.matches(in: svgText, options: [], range: range) {
                guard let referenceRange = Range(match.range(at: 2), in: svgText) else {
                    return false
                }
                let reference = String(svgText[referenceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard reference.hasPrefix("#"), reference.count > 1 else {
                    return false
                }
                references.append(String(reference.dropFirst()))
            }
        }
        guard references.count <= maxReferenceCount else {
            return false
        }
        guard references.allSatisfy(ids.contains) else {
            return false
        }

        let attributes = attributePattern.matches(in: svgText, options: [], range: range)
        guard attributes.count <= maxAttributeCount else {
            return false
        }

        let pathBytes = pathPattern.matches(in: svgText, options: [], range: range).reduce(0) { partialResult, match in
            guard let valueRange = Range(match.range(at: 2), in: svgText) else {
                return partialResult
            }
            return partialResult + String(svgText[valueRange]).lengthOfBytes(using: .utf8)
        }
        return pathBytes <= maxPathDataBytes
    }
}

public struct PackagedPluginEventsFile: Decodable, Equatable, Sendable {
    public var events: [EventTypeDeclaration]
}

public struct PackagedPluginActionsFile: Decodable, Equatable, Sendable {
    public var actions: [PackagedPluginAction]
}

public struct PackagedPluginViewsFile: Decodable, Equatable, Sendable {
    public var views: [PackagedPluginView]
    public var dashboardTile: PackagedPluginDashboardTile?

    enum CodingKeys: String, CodingKey {
        case views
        case dashboardTile
    }

    public init(views: [PackagedPluginView], dashboardTile: PackagedPluginDashboardTile? = nil) {
        self.views = views
        self.dashboardTile = dashboardTile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        views = try container.decode([PackagedPluginView].self, forKey: .views)
        dashboardTile = try container.decodeIfPresent(PackagedPluginDashboardTile.self, forKey: .dashboardTile)
    }
}

public struct PackagedPluginDashboardTile: Codable, Equatable, Sendable {
    public var primaryFields: [String]
    public var secondaryFields: [String]

    enum CodingKeys: String, CodingKey {
        case primaryFields
        case secondaryFields
    }

    public init(primaryFields: [String] = [], secondaryFields: [String] = []) {
        self.primaryFields = primaryFields
        self.secondaryFields = secondaryFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryFields = try container.decodeIfPresent([String].self, forKey: .primaryFields) ?? []
        secondaryFields = try container.decodeIfPresent([String].self, forKey: .secondaryFields) ?? []
    }

    public var defaultFields: [String] {
        uniqueFields(primaryFields + secondaryFields)
    }

    private func uniqueFields(_ fields: [String]) -> [String] {
        var seen: Set<String> = []
        return fields.filter { field in
            guard seen.contains(field) == false else { return false }
            seen.insert(field)
            return true
        }
    }
}

public struct PackagedPluginView: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var type: PackagedPluginViewType
    public var title: String?
    public var resourceType: String?
    public var fields: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case resourceType
        case fields
    }

    public init(
        id: String,
        type: PackagedPluginViewType,
        title: String? = nil,
        resourceType: String? = nil,
        fields: [String] = []
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.resourceType = resourceType
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(PackagedPluginViewType.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        resourceType = try container.decodeIfPresent(String.self, forKey: .resourceType)
        fields = try container.decodeIfPresent([String].self, forKey: .fields) ?? []
    }
}

public enum PackagedPluginViewType: String, Codable, Equatable, Sendable {
    case overviewCards = "overview_cards"
    case resourceList = "resource_list"
    case resourceDetail = "resource_detail"
    case timeline
    case metricGrid = "metric_grid"
    case alertList = "alert_list"
}

public struct PackagedPluginAction: Decodable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var description: String?
    public var requiresWritePermission: Bool
    public var safety: ActionSafetyLevel?
    public var inputSchema: PackagedPluginActionInputSchema?
    public var request: String

    public init(
        id: String,
        label: String,
        description: String? = nil,
        requiresWritePermission: Bool = false,
        safety: ActionSafetyLevel? = nil,
        inputSchema: PackagedPluginActionInputSchema? = nil,
        request: String
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.requiresWritePermission = requiresWritePermission
        self.safety = safety
        self.inputSchema = inputSchema
        self.request = request
    }
}

public struct PackagedPluginActionInputSchema: Decodable, Equatable, Sendable {
    public var fields: [PackagedPluginActionInputField]

    public init(fields: [PackagedPluginActionInputField]) {
        self.fields = fields
    }
}

public struct PackagedPluginActionInputField: Decodable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var type: PackagedPluginActionInputType
    public var required: Bool
    public var placeholder: String?
    public var help: String?
    public var defaultValue: String?
    public var options: [PackagedPluginSetupFieldOption]

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case type
        case required
        case placeholder
        case help
        case `default`
        case options
    }

    public init(
        key: String,
        label: String,
        type: PackagedPluginActionInputType,
        required: Bool = false,
        placeholder: String? = nil,
        help: String? = nil,
        defaultValue: String? = nil,
        options: [PackagedPluginSetupFieldOption] = []
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.placeholder = placeholder
        self.help = help
        self.defaultValue = defaultValue
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decode(PackagedPluginActionInputType.self, forKey: .type)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        help = try container.decodeIfPresent(String.self, forKey: .help)
        defaultValue = try container.decodeIfPresent(PluginJSONValue.self, forKey: .default)?.stringValue
        options = try container.decodeIfPresent([PackagedPluginSetupFieldOption].self, forKey: .options) ?? []
    }
}

public enum PackagedPluginActionInputType: String, Decodable, Equatable, Sendable {
    case text
    case template
    case select
    case number
    case toggle
}

public struct PackagedPluginAuth: Codable, Equatable, Sendable {
    public var type: AuthKind
    public var provider: String?
    public var applicationId: String?
    public var oauth2: PackagedPluginOAuth2?
    public var fields: [PackagedPluginSetupField]
    public var placement: PackagedPluginAuthPlacement?

    enum CodingKeys: String, CodingKey {
        case type
        case provider
        case applicationId
        case oauth2
        case fields
        case placement
    }

    public init(
        type: AuthKind,
        provider: String? = nil,
        applicationId: String? = nil,
        oauth2: PackagedPluginOAuth2? = nil,
        fields: [PackagedPluginSetupField] = [],
        placement: PackagedPluginAuthPlacement? = nil
    ) {
        self.type = type
        self.provider = provider
        self.applicationId = applicationId
        self.oauth2 = oauth2
        self.fields = fields
        self.placement = placement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(AuthKind.self, forKey: .type)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        applicationId = try container.decodeIfPresent(String.self, forKey: .applicationId)
        oauth2 = try container.decodeIfPresent(PackagedPluginOAuth2.self, forKey: .oauth2)
        fields = try container.decodeIfPresent([PackagedPluginSetupField].self, forKey: .fields) ?? []
        placement = try container.decodeIfPresent(PackagedPluginAuthPlacement.self, forKey: .placement)
    }
}

public struct PackagedPluginOAuth2: Codable, Equatable, Sendable {
    public var authorizationURL: URL
    public var tokenURL: URL
    public var redirectURI: String
    public var scopes: [String]
    public var additionalAuthorizationParameters: [String: String]

    enum CodingKeys: String, CodingKey {
        case authorizationURL = "authorizationUrl"
        case tokenURL = "tokenUrl"
        case redirectURI = "redirectUri"
        case scopes
        case additionalAuthorizationParameters
    }

    public init(
        authorizationURL: URL,
        tokenURL: URL,
        redirectURI: String,
        scopes: [String] = [],
        additionalAuthorizationParameters: [String: String] = [:]
    ) {
        self.authorizationURL = authorizationURL
        self.tokenURL = tokenURL
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.additionalAuthorizationParameters = additionalAuthorizationParameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationURL = try container.decode(URL.self, forKey: .authorizationURL)
        tokenURL = try container.decode(URL.self, forKey: .tokenURL)
        redirectURI = try container.decode(String.self, forKey: .redirectURI)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
        additionalAuthorizationParameters = try container.decodeIfPresent([String: String].self, forKey: .additionalAuthorizationParameters) ?? [:]
    }
}

public struct PackagedPluginAuthPlacement: Codable, Equatable, Sendable {
    public enum Location: String, Codable, Sendable {
        case header
    }

    public var location: Location
    public var name: String

    enum CodingKeys: String, CodingKey {
        case location = "in"
        case name
    }

    public init(location: Location = .header, name: String) {
        self.location = location
        self.name = name
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
    public var headers: [String: String]
    public var query: [String: String]
    public var body: PackagedPluginRequestBody?
    public var pagination: PackagedPluginRequestPagination?
    public var timeoutSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case method
        case url
        case auth
        case headers
        case query
        case body
        case pagination
        case timeoutSeconds
    }

    public init(
        method: String = "GET",
        url: String,
        auth: String? = nil,
        headers: [String: String] = [:],
        query: [String: String] = [:],
        body: PackagedPluginRequestBody? = nil,
        pagination: PackagedPluginRequestPagination? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) {
        self.method = method
        self.url = url
        self.auth = auth
        self.headers = headers
        self.query = query
        self.body = body
        self.pagination = pagination
        self.timeoutSeconds = timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "GET"
        url = try container.decode(String.self, forKey: .url)
        auth = try container.decodeIfPresent(String.self, forKey: .auth)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        query = try container.decodeIfPresent([String: String].self, forKey: .query) ?? [:]
        body = try container.decodeIfPresent(PackagedPluginRequestBody.self, forKey: .body)
        pagination = try container.decodeIfPresent(PackagedPluginRequestPagination.self, forKey: .pagination)
        timeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds)
    }
}

public enum PackagedPluginRequestBody: Decodable, Equatable, Sendable {
    case string(String)
    case object([String: PackagedPluginRequestBody])
    case array([PackagedPluginRequestBody])
    case number(Double)
    case bool(Bool)
    case null

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
        } else if let value = try? container.decode([String: PackagedPluginRequestBody].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([PackagedPluginRequestBody].self))
        }
    }

    public init(_ value: String) {
        self = .string(value)
    }

    public init(object: [String: PackagedPluginRequestBody]) {
        self = .object(object)
    }
}

public struct PackagedPluginRequestPagination: Decodable, Equatable, Sendable {
    public var type: String
    public var path: String?
    public var cursorPath: String?
    public var param: String?
    public var start: Int?
    public var itemsPath: String?
    public var pageSize: Int?
    public var maxPages: Int?

    public init(
        type: String,
        path: String? = nil,
        cursorPath: String? = nil,
        param: String? = nil,
        start: Int? = nil,
        itemsPath: String? = nil,
        pageSize: Int? = nil,
        maxPages: Int? = nil
    ) {
        self.type = type
        self.path = path
        self.cursorPath = cursorPath
        self.param = param
        self.start = start
        self.itemsPath = itemsPath
        self.pageSize = pageSize
        self.maxPages = maxPages
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
    case predicate(PackagedMappingPredicate)
    case all([PackagedMappingCondition])
    case any([PackagedMappingCondition])

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let expression = try? container.decode(String.self) {
            self = .shorthand(expression)
            return
        }
        if let container = try? decoder.singleValueContainer(),
           let conditions = try? container.decode([PackagedMappingCondition].self) {
            self = .all(conditions)
            return
        }
        let object = try decoder.container(keyedBy: CodingKeys.self)
        if let conditions = try object.decodeIfPresent([PackagedMappingCondition].self, forKey: .any) {
            self = .any(conditions)
            return
        }
        self = .predicate(try PackagedMappingPredicate(from: decoder))
    }

    enum CodingKeys: String, CodingKey {
        case any
    }
}

public struct PackagedMappingPredicate: Decodable, Equatable, Sendable {
    public var path: String
    public var operation: MappingOperator
    public var value: MappingJSONValue?

    enum CodingKeys: String, CodingKey {
        case path
        case operation = "operator"
        case value
    }

    public init(path: String, operation: MappingOperator, value: MappingJSONValue? = nil) {
        self.path = path
        self.operation = operation
        self.value = value
    }
}

public enum PackagedEventSeverity: Decodable, Equatable, Sendable {
    case fixed(Severity)
    case mapped(PackagedEventSeverityMap)

    public init(_ severity: Severity) {
        self = .fixed(severity)
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let severity = try? container.decode(Severity.self) {
            self = .fixed(severity)
            return
        }
        self = .mapped(try PackagedEventSeverityMap(from: decoder))
    }
}

public struct PackagedEventSeverityMap: Decodable, Equatable, Sendable {
    public var path: String
    public var map: [String: Severity]
    public var defaultSeverity: Severity

    enum CodingKeys: String, CodingKey {
        case path
        case map
        case defaultSeverity = "default"
    }

    public init(path: String, map: [String: Severity], defaultSeverity: Severity) {
        self.path = path
        self.map = map
        self.defaultSeverity = defaultSeverity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        map = try container.decode([String: Severity].self, forKey: .map)
        defaultSeverity = try container.decode(Severity.self, forKey: .defaultSeverity)
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
    case invalidIconAsset(String)
    case invalidReadmeAsset(String)
    case missingActionRequest(actionID: String, requestID: String)

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
        case .invalidIconAsset(let path):
            "Plugin package icon asset must be a UTF-8 SVG file: \(path)"
        case .invalidReadmeAsset(let path):
            "Plugin package README must be a UTF-8 Markdown file: \(path)"
        case .missingActionRequest(let actionID, let requestID):
            "Plugin action \(actionID) references missing request \(requestID)."
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
