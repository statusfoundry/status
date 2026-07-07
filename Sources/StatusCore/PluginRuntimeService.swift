import Foundation

public struct PluginRuntimeRequest: Equatable, Sendable {
    public var pluginID: String
    public var requestID: String
    public var accountID: String
    public var accountName: String
    public var variables: [String: String]
    public var headers: [String: String]
    public var now: Date

    public init(
        pluginID: String,
        requestID: String,
        accountID: String,
        accountName: String,
        variables: [String: String] = [:],
        headers: [String: String] = [:],
        now: Date = Date()
    ) {
        self.pluginID = pluginID
        self.requestID = requestID
        self.accountID = accountID
        self.accountName = accountName
        self.variables = variables
        self.headers = headers
        self.now = now
    }
}

public enum PluginRuntimeServiceError: Error, Equatable, LocalizedError, Sendable {
    case pluginNotInstalled(String)
    case packageUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .pluginNotInstalled(let pluginID):
            "Plugin is not installed: \(pluginID)"
        case .packageUnavailable(let pluginID):
            "Installed plugin package is unavailable: \(pluginID)"
        }
    }
}

public final class PluginRuntimeService {
    private let store: StatusPersistenceStore
    private let transport: PluginRequestHTTPTransport

    public init(store: StatusPersistenceStore, transport: PluginRequestHTTPTransport = URLSessionPluginRequestTransport()) {
        self.store = store
        self.transport = transport
    }

    public func runInstalledPluginRequest(_ request: PluginRuntimeRequest) async throws -> PluginRequestJobResult {
        guard let plugin = try store.installedPlugin(id: request.pluginID), plugin.enabled else {
            throw PluginRuntimeServiceError.pluginNotInstalled(request.pluginID)
        }
        guard let installedVersion = try store.installedPluginVersions(pluginID: request.pluginID)
            .sorted(by: { $0.installedAt > $1.installedAt })
            .first,
            let packagePath = installedVersion.packagePath else {
            throw PluginRuntimeServiceError.packageUnavailable(request.pluginID)
        }

        let packageData = try Data(contentsOf: URL(fileURLWithPath: packagePath))
        let definition = try PluginPackageDefinition.decode(from: packageData)
        let jobID = jobID(pluginID: request.pluginID, requestID: request.requestID, accountID: request.accountID, date: request.now)

        try store.upsertAccount(
            Account(
                id: request.accountID,
                pluginID: request.pluginID,
                provider: request.pluginID,
                displayName: request.accountName
            ),
            updatedAt: request.now
        )
        try store.upsertJob(
            JobRecord(
                id: jobID,
                pluginID: request.pluginID,
                triggerID: "manual_\(request.requestID)",
                accountID: request.accountID,
                status: .running,
                queuedAt: request.now,
                startedAt: request.now
            )
        )

        do {
            let runner = PluginRequestJobRunner(
                transport: transport,
                committer: PluginMappingOutputCommitter(store: store)
            )
            let result = try await runner.run(
                definition: definition,
                input: PluginRequestJobInput(
                    pluginID: request.pluginID,
                    accountID: request.accountID,
                    provider: request.pluginID,
                    requestID: request.requestID,
                    variables: request.variables,
                    headers: request.headers,
                    jobID: jobID,
                    capturedAt: request.now
                )
            )
            try store.upsertJob(
                JobRecord(
                    id: jobID,
                    pluginID: request.pluginID,
                    triggerID: "manual_\(request.requestID)",
                    accountID: request.accountID,
                    status: .success,
                    queuedAt: request.now,
                    startedAt: request.now,
                    finishedAt: request.now,
                    emittedEventIDs: result.mappingOutput.events.map(\.id)
                )
            )
            if let job = try store.job(id: jobID) {
                try store.insertJobAuditEntry(for: job, timestamp: request.now)
            }
            return result
        } catch {
            try store.upsertJob(
                JobRecord(
                    id: jobID,
                    pluginID: request.pluginID,
                    triggerID: "manual_\(request.requestID)",
                    accountID: request.accountID,
                    status: .failed,
                    queuedAt: request.now,
                    startedAt: request.now,
                    finishedAt: request.now,
                    error: error.localizedDescription
                )
            )
            if let job = try store.job(id: jobID) {
                try store.insertJobAuditEntry(for: job, timestamp: request.now)
            }
            throw error
        }
    }

    private func jobID(pluginID: String, requestID: String, accountID: String, date: Date) -> String {
        let raw = "\(pluginID)_\(requestID)_\(accountID)_\(Int(date.timeIntervalSince1970))"
        let sanitized = raw
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "job_\(sanitized)"
    }
}
