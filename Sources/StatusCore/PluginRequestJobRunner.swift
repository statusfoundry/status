import Foundation

public struct PluginHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeoutSeconds: TimeInterval?

    public init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct PluginHTTPResponse: Equatable, Sendable {
    public var data: Data
    public var statusCode: Int
    public var url: URL

    public init(data: Data, statusCode: Int, url: URL) {
        self.data = data
        self.statusCode = statusCode
        self.url = url
    }
}

public protocol PluginRequestHTTPTransport: Sendable {
    func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse
}

public struct URLSessionPluginRequestTransport: PluginRequestHTTPTransport {
    public init() {}

    public func response(for request: PluginHTTPRequest) async throws -> PluginHTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeoutSeconds ?? 30)
        urlRequest.httpMethod = request.method
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = request.body
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        return PluginHTTPResponse(data: data, statusCode: statusCode, url: request.url)
    }
}

public struct PluginRequestJobInput: Equatable, Sendable {
    public var pluginID: String
    public var accountID: String
    public var provider: String
    public var requestID: String
    public var variables: [String: String]
    public var headers: [String: String]
    public var jobID: String?
    public var capturedAt: Date

    public init(
        pluginID: String,
        accountID: String,
        provider: String,
        requestID: String,
        variables: [String: String] = [:],
        headers: [String: String] = [:],
        jobID: String? = nil,
        capturedAt: Date
    ) {
        self.pluginID = pluginID
        self.accountID = accountID
        self.provider = provider
        self.requestID = requestID
        self.variables = variables
        self.headers = headers
        self.jobID = jobID
        self.capturedAt = capturedAt
    }
}

public struct PluginRequestJobResult: Equatable, Sendable {
    public var request: PluginHTTPRequest
    public var payload: MappingJSONValue
    public var mappingOutput: PluginMappingExecutionOutput
    public var commitResult: PluginMappingCommitResult
    public var warnings: [PluginMappingWarning]

    public init(
        request: PluginHTTPRequest,
        payload: MappingJSONValue,
        mappingOutput: PluginMappingExecutionOutput,
        commitResult: PluginMappingCommitResult,
        warnings: [PluginMappingWarning] = []
    ) {
        self.request = request
        self.payload = payload
        self.mappingOutput = mappingOutput
        self.commitResult = commitResult
        self.warnings = warnings
    }
}

public enum PluginRequestJobRunnerError: Error, Equatable, LocalizedError, Sendable {
    case missingRequest(String)
    case invalidURL(String)
    case invalidPaginationURL(String)
    case invalidBody
    case timedOut(requestID: String, timeoutSeconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .missingRequest(let requestID):
            "Plugin request is not declared: \(requestID)"
        case .invalidURL(let url):
            "Plugin request URL is invalid: \(url)"
        case .invalidPaginationURL(let url):
            "Plugin pagination URL is invalid: \(url)"
        case .invalidBody:
            "Plugin request body could not be rendered."
        case .timedOut(let requestID, let timeoutSeconds):
            "Plugin request \(requestID) timed out after \(formatTimeout(timeoutSeconds)) seconds."
        }
    }
}

public final class PluginRequestJobRunner {
    private let transport: PluginRequestHTTPTransport
    private let committer: PluginMappingOutputCommitter
    private let decoder = JSONDecoder()

    public init(
        transport: PluginRequestHTTPTransport = URLSessionPluginRequestTransport(),
        committer: PluginMappingOutputCommitter
    ) {
        self.transport = transport
        self.committer = committer
    }

    public func run(
        definition: PluginPackageDefinition,
        input: PluginRequestJobInput
    ) async throws -> PluginRequestJobResult {
        guard let requestDefinition = definition.requests.requests[input.requestID] else {
            throw PluginRequestJobRunnerError.missingRequest(input.requestID)
        }

        let request = try makeRequest(requestDefinition, input: input)
        let payloadResult = try await fetchPayload(
            request: request,
            definition: requestDefinition,
            requestID: input.requestID,
            variables: input.variables
        )
        let mappingOutput = try PluginMappingExecutor.execute(
            definition.mappings,
            input: PluginMappingExecutionInput(
                pluginID: input.pluginID,
                accountID: input.accountID,
                provider: input.provider,
                requestID: input.requestID,
                payload: payloadResult.payload,
                capturedAt: input.capturedAt,
                account: .object(input.variables.mapValues(MappingJSONValue.string))
            )
        )
        let commitResult = try committer.commit(
            mappingOutput,
            jobID: input.jobID,
            capturedAt: input.capturedAt,
            eventDeclarations: definition.events
        )

        return PluginRequestJobResult(
            request: request,
            payload: payloadResult.payload,
            mappingOutput: mappingOutput,
            commitResult: commitResult,
            warnings: payloadResult.warnings + mappingOutput.warnings
        )
    }

    public func request(
        definition: PackagedPluginRequest,
        input: PluginRequestJobInput,
        context: MappingTemplateContext? = nil
    ) throws -> PluginHTTPRequest {
        try makeRequest(definition, input: input, context: context)
    }

    public func response(for request: PluginHTTPRequest, requestID: String) async throws -> PluginHTTPResponse {
        try await fetchResponse(for: request, requestID: requestID)
    }

    private struct PayloadFetchResult {
        var payload: MappingJSONValue
        var warnings: [PluginMappingWarning]
    }

    private func fetchPayload(
        request: PluginHTTPRequest,
        definition: PackagedPluginRequest,
        requestID: String,
        variables: [String: String]
    ) async throws -> PayloadFetchResult {
        let firstResponse = try await fetchResponse(for: request, requestID: requestID)
        var payload = decodePayload(response: firstResponse, variables: variables)
        guard let pagination = definition.pagination else {
            return PayloadFetchResult(payload: payload, warnings: [])
        }

        var warnings: [PluginMappingWarning] = []
        var state = PaginationState(currentPage: pagination.start ?? 1)
        var nextURL = try paginationNextURL(from: payload, pagination: pagination, originalURL: request.url, state: &state)
        let maxPages = max(1, min(pagination.maxPages ?? 20, 100))
        var fetchedPages = 1
        while let url = nextURL, fetchedPages < maxPages {
            let pageRequest = PluginHTTPRequest(
                method: definition.method,
                url: url,
                headers: request.headers,
                timeoutSeconds: definition.timeoutSeconds
            )
            let pageResponse = try await fetchResponse(for: pageRequest, requestID: requestID)
            let pagePayload = decodePayload(response: pageResponse, variables: variables)
            payload = payload.mergingTopLevelArrays(from: pagePayload)
            fetchedPages += 1
            nextURL = try paginationNextURL(from: pagePayload, pagination: pagination, originalURL: request.url, state: &state)
        }
        if nextURL != nil {
            warnings.append(PluginMappingWarning(message: "Request \(requestID) reached pagination maxPages limit of \(maxPages)."))
        }
        return PayloadFetchResult(payload: payload, warnings: warnings)
    }

    private func fetchResponse(for request: PluginHTTPRequest, requestID: String) async throws -> PluginHTTPResponse {
        let timeoutSeconds = request.timeoutSeconds ?? 30
        guard timeoutSeconds > 0 else {
            throw PluginRequestJobRunnerError.timedOut(requestID: requestID, timeoutSeconds: timeoutSeconds)
        }
        let transport = transport
        return try await withThrowingTaskGroup(of: PluginHTTPResponse.self) { group in
            group.addTask {
                try await transport.response(for: request)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds(timeoutSeconds))
                throw PluginRequestJobRunnerError.timedOut(requestID: requestID, timeoutSeconds: timeoutSeconds)
            }
            guard let result = try await group.next() else {
                throw PluginRequestJobRunnerError.timedOut(requestID: requestID, timeoutSeconds: timeoutSeconds)
            }
            group.cancelAll()
            return result
        }
    }

    private func makeRequest(
        _ definition: PackagedPluginRequest,
        input: PluginRequestJobInput,
        context providedContext: MappingTemplateContext? = nil
    ) throws -> PluginHTTPRequest {
        let variables = MappingJSONValue.object(input.variables.mapValues(MappingJSONValue.string))
        let context = providedContext ?? MappingTemplateContext(scopes: ["item": variables, "account": variables])
        let renderedURL = MappingTemplateRenderer.render(definition.url, context: context)
        guard var components = URLComponents(string: renderedURL) else {
            throw PluginRequestJobRunnerError.invalidURL(renderedURL)
        }
        let existingQueryItems = components.queryItems ?? []
        let queryItems = definition.query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: MappingTemplateRenderer.render($0.value, context: context)) }
        components.queryItems = (existingQueryItems + queryItems).isEmpty ? nil : existingQueryItems + queryItems
        if isPageNumberPagination(definition.pagination),
           let param = definition.pagination?.param,
           param.isEmpty == false {
            components = components.replacingQueryItem(name: param, value: String(definition.pagination?.start ?? 1))
        }
        guard let url = components.url else {
            throw PluginRequestJobRunnerError.invalidURL(renderedURL)
        }

        var headers = definition.headers
            .mapValues { MappingTemplateRenderer.render($0, context: context) }
        for (field, value) in input.headers {
            headers[field] = value
        }
        let body = try definition.body.map { try renderBody($0, context: context) }
        if definition.body?.isJSONContainer == true,
           headers.keys.contains(where: { $0.lowercased() == "content-type" }) == false {
            headers["Content-Type"] = "application/json"
        }

        return PluginHTTPRequest(
            method: definition.method,
            url: url,
            headers: headers,
            body: body,
            timeoutSeconds: definition.timeoutSeconds
        )
    }

    private func decodePayload(response: PluginHTTPResponse, variables: [String: String]) -> MappingJSONValue {
        if let payload = try? decoder.decode(MappingJSONValue.self, from: response.data) {
            return payload.mergingObjectFields([
                "statusCode": .number(Double(response.statusCode))
            ])
        }

        var fields = variables.mapValues(MappingJSONValue.string)
        fields["statusCode"] = .number(Double(response.statusCode))
        fields["reachable"] = .bool((200..<500).contains(response.statusCode))
        fields["previousHealthy"] = .null
        return .object(fields)
    }

    private func renderBody(_ body: PackagedPluginRequestBody, context: MappingTemplateContext) throws -> Data {
        switch body {
        case .string(let value):
            return Data(MappingTemplateRenderer.render(value, context: context).utf8)
        case .object, .array:
            guard JSONSerialization.isValidJSONObject(body.renderedJSONObject(context: context)) else {
                throw PluginRequestJobRunnerError.invalidBody
            }
            return try JSONSerialization.data(
                withJSONObject: body.renderedJSONObject(context: context),
                options: [.sortedKeys]
            )
        case .number(let value):
            return Data(String(value).utf8)
        case .bool(let value):
            return Data((value ? "true" : "false").utf8)
        case .null:
            return Data("null".utf8)
        }
    }

    private func paginationNextURL(
        from payload: MappingJSONValue,
        pagination: PackagedPluginRequestPagination,
        originalURL: URL,
        state: inout PaginationState
    ) throws -> URL? {
        switch pagination.type {
        case "jsonapi-next-link", "next-link":
            guard let path = pagination.path,
                  let value = try MappingSelector(path).resolve(in: payload)?.scalarString,
                  value.isEmpty == false else {
                return nil
            }
            guard let url = URL(string: value, relativeTo: originalURL)?.absoluteURL,
                  url.scheme == "https",
                  url.host?.lowercased() == originalURL.host?.lowercased() else {
                throw PluginRequestJobRunnerError.invalidPaginationURL(value)
            }
            return url
        case "cursor":
            guard let param = pagination.param, param.isEmpty == false else {
                return nil
            }
            let path = pagination.cursorPath ?? pagination.path
            guard let path,
                  let cursor = try MappingSelector(path).resolve(in: payload)?.scalarString,
                  cursor.isEmpty == false,
                  cursor != state.previousCursor else {
                return nil
            }
            state.previousCursor = cursor
            return try originalURL.withQueryItem(name: param, value: cursor)
        case "page-number", "page":
            guard let param = pagination.param, param.isEmpty == false else {
                return nil
            }
            if let itemsPath = pagination.itemsPath,
               try MappingSelector(itemsPath).resolve(in: payload)?.isEmptyArray != false {
                return nil
            }
            state.currentPage += 1
            return try originalURL.withQueryItem(name: param, value: String(state.currentPage))
        default:
            return nil
        }
    }

    private func isPageNumberPagination(_ pagination: PackagedPluginRequestPagination?) -> Bool {
        pagination?.type == "page-number" || pagination?.type == "page"
    }
}

private struct PaginationState {
    var previousCursor: String?
    var currentPage: Int
}

private extension URL {
    func withQueryItem(name: String, value: String) throws -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            throw PluginRequestJobRunnerError.invalidURL(absoluteString)
        }
        components = components.replacingQueryItem(name: name, value: value)
        guard let url = components.url else {
            throw PluginRequestJobRunnerError.invalidURL(absoluteString)
        }
        return url
    }
}

private func timeoutNanoseconds(_ seconds: TimeInterval) -> UInt64 {
    let boundedSeconds = max(0, min(seconds, TimeInterval(UInt64.max) / 1_000_000_000))
    return UInt64((boundedSeconds * 1_000_000_000).rounded(.up))
}

private func formatTimeout(_ seconds: TimeInterval) -> String {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    return formatter.string(from: NSNumber(value: seconds)) ?? String(seconds)
}

private extension URLComponents {
    func replacingQueryItem(name: String, value: String) -> URLComponents {
        var copy = self
        var items = copy.queryItems ?? []
        items.removeAll { $0.name == name }
        items.append(URLQueryItem(name: name, value: value))
        copy.queryItems = items.isEmpty ? nil : items
        return copy
    }
}

private extension MappingJSONValue {
    var isEmptyArray: Bool {
        if case .array(let values) = self {
            return values.isEmpty
        }
        return false
    }

    func mergingObjectFields(_ fields: [String: MappingJSONValue]) -> MappingJSONValue {
        guard case .object(var object) = self else { return self }
        for (key, value) in fields {
            object[key] = value
        }
        return .object(object)
    }

    func mergingTopLevelArrays(from next: MappingJSONValue) -> MappingJSONValue {
        guard case .object(var object) = self,
              case .object(let nextObject) = next else {
            return self
        }
        for (key, nextValue) in nextObject {
            if case .array(let existingArray) = object[key],
               case .array(let nextArray) = nextValue {
                object[key] = .array(existingArray + nextArray)
            } else if object[key] == nil {
                object[key] = nextValue
            }
        }
        return .object(object)
    }
}

private extension PackagedPluginRequestBody {
    var isJSONContainer: Bool {
        switch self {
        case .object, .array:
            true
        case .string, .number, .bool, .null:
            false
        }
    }

    func renderedJSONObject(context: MappingTemplateContext) -> Any {
        switch self {
        case .string(let value):
            MappingTemplateRenderer.render(value, context: context)
        case .object(let object):
            object.mapValues { $0.renderedJSONObject(context: context) }
        case .array(let values):
            values.map { $0.renderedJSONObject(context: context) }
        case .number(let value):
            value
        case .bool(let value):
            value
        case .null:
            NSNull()
        }
    }
}
