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
    case accountNotConfigured(String)
    case queuedJobUnavailable(String)
    case runnableTriggerUnavailable(String)
    case triggerRequestUnavailable(String)
    case missingPermission(pluginID: String, permission: PluginPermission)
    case actionUnavailable(String)
    case actionRequestFailed(action: String, statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .pluginNotInstalled(let pluginID):
            "Plugin is not installed: \(pluginID)"
        case .packageUnavailable(let pluginID):
            "Installed plugin package is unavailable: \(pluginID)"
        case .accountNotConfigured(let accountID):
            "Plugin account is not configured: \(accountID)"
        case .queuedJobUnavailable(let jobID):
            "Queued plugin job is unavailable: \(jobID)"
        case .runnableTriggerUnavailable(let pluginID):
            "No enabled runnable trigger is configured for plugin: \(pluginID)"
        case .triggerRequestUnavailable(let triggerID):
            "Trigger does not declare a plugin request: \(triggerID)"
        case .missingPermission(let pluginID, let permission):
            "Plugin \(pluginID) requires granted permission before it can run: \(permission.rawValue)"
        case .actionUnavailable(let action):
            "No installed plugin declares action: \(action)"
        case .actionRequestFailed(let action, let statusCode):
            "Provider action \(action) failed with HTTP \(statusCode)."
        }
    }
}

public final class PluginRuntimeService: ProviderActionExecutor, @unchecked Sendable {
    private let store: StatusPersistenceStore
    private let transport: PluginRequestHTTPTransport
    private let credentialStore: CredentialStore?
    private let actionRunner: ActionRunner
    private let effectDispatcher: ActionEffectDispatcher
    private let baseBackoffSeconds: TimeInterval
    private let maxBackoffSeconds: TimeInterval

    public init(
        store: StatusPersistenceStore,
        transport: PluginRequestHTTPTransport = URLSessionPluginRequestTransport(),
        credentialStore: CredentialStore? = KeychainCredentialStore(),
        actionRunner: ActionRunner = ActionRunner(),
        effectDispatcher: ActionEffectDispatcher = NoopActionEffectDispatcher(),
        baseBackoffSeconds: TimeInterval = 60,
        maxBackoffSeconds: TimeInterval = 3_600
    ) {
        self.store = store
        self.transport = transport
        self.credentialStore = credentialStore
        self.actionRunner = actionRunner
        self.effectDispatcher = effectDispatcher
        self.baseBackoffSeconds = baseBackoffSeconds
        self.maxBackoffSeconds = maxBackoffSeconds
    }

    public func saveAccountConfiguration(_ configuration: PluginAccountConfiguration, now: Date = Date()) throws {
        try store.upsertAccountConfiguration(configuration, updatedAt: now)
    }

    public func enqueueManualConfiguredPluginRun(
        pluginID: String,
        accountID: String,
        now: Date = Date()
    ) throws -> JobRecord {
        guard try store.accountConfiguration(accountID: accountID) != nil else {
            throw PluginRuntimeServiceError.accountNotConfigured(accountID)
        }
        guard var trigger = try store.triggers()
            .filter({ $0.pluginID == pluginID && $0.kind == .manual && $0.enabled })
            .sorted(by: { lhs, rhs in
                if (lhs.requestID != nil) != (rhs.requestID != nil) {
                    return lhs.requestID != nil
                }
                return lhs.id < rhs.id
            })
            .first else {
            throw PluginRuntimeServiceError.runnableTriggerUnavailable(pluginID)
        }
        guard let requestID = trigger.requestID ?? bundledManualRequestID(pluginID: pluginID) else {
            throw PluginRuntimeServiceError.triggerRequestUnavailable(trigger.id)
        }
        let job = JobRecord(
            id: jobID(pluginID: pluginID, requestID: requestID, accountID: accountID, date: now),
            pluginID: pluginID,
            triggerID: trigger.id,
            accountID: accountID,
            status: .queued,
            queuedAt: now
        )
        try store.upsertJob(job)
        trigger.requestID = requestID
        trigger.lastRunAt = now
        try store.upsertTrigger(trigger, updatedAt: now)
        return job
    }

    public func runNextQueuedPluginJob(headers: [String: String] = [:], now: Date = Date()) async throws -> PluginRequestJobResult? {
        guard let job = try store.nextQueuedJob() else {
            return nil
        }
        return try await runQueuedPluginJob(jobID: job.id, headers: headers, now: now)
    }

    @discardableResult
    public func enqueueDueConfiguredPluginJobs(now: Date = Date()) throws -> [JobRecord] {
        var jobs: [JobRecord] = []
        for var trigger in try store.triggers() where isDueCronTrigger(trigger, at: now) {
            guard try hasGrantedPermission(pluginID: trigger.pluginID, permission: .backgroundRefresh) else {
                try insertSkippedTriggerAudit(
                    trigger,
                    reason: "background_refresh_permission",
                    detail: "Status skipped \(trigger.label) because \(trigger.pluginID) does not have background refresh permission.",
                    at: now
                )
                continue
            }
            guard let requestID = trigger.requestID else {
                try insertSkippedTriggerAudit(
                    trigger,
                    reason: "request_missing",
                    detail: "Status skipped \(trigger.label) because the cron trigger does not declare a plugin request.",
                    at: now
                )
                continue
            }
            let accountIDs = try configuredAccountIDs(for: trigger)
            guard accountIDs.isEmpty == false else {
                try insertSkippedTriggerAudit(
                    trigger,
                    reason: "account_missing",
                    detail: "Status skipped \(trigger.label) because no configured account is available for \(trigger.pluginID).",
                    at: now
                )
                continue
            }
            for accountID in accountIDs {
                let job = JobRecord(
                    id: jobID(pluginID: trigger.pluginID, requestID: requestID, accountID: accountID, date: now),
                    pluginID: trigger.pluginID,
                    triggerID: trigger.id,
                    accountID: accountID,
                    status: .queued,
                    queuedAt: now
                )
                try store.upsertJob(job)
                jobs.append(job)
            }
            trigger.lastRunAt = now
            trigger.nextRunAt = nextRunDate(for: trigger, from: now)
            try store.upsertTrigger(trigger, updatedAt: now)
        }
        return jobs
    }

    public func runDueConfiguredPluginJobs(
        headers: [String: String] = [:],
        now: Date = Date()
    ) async throws -> [PluginRequestJobResult] {
        let jobs = try enqueueDueConfiguredPluginJobs(now: now)
        var results: [PluginRequestJobResult] = []
        var firstError: Error?
        for job in jobs {
            do {
                results.append(try await runQueuedPluginJob(jobID: job.id, headers: headers, now: now))
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if results.isEmpty, let firstError {
            throw firstError
        }
        return results
    }

    public func runQueuedPluginJob(
        jobID: String,
        headers: [String: String] = [:],
        now: Date = Date()
    ) async throws -> PluginRequestJobResult {
        guard let job = try store.job(id: jobID), job.status == .queued else {
            throw PluginRuntimeServiceError.queuedJobUnavailable(jobID)
        }
        guard let trigger = try store.trigger(id: job.triggerID),
              let requestID = trigger.requestID else {
            try failQueuedJob(job, at: now, error: PluginRuntimeServiceError.triggerRequestUnavailable(job.triggerID))
            throw PluginRuntimeServiceError.triggerRequestUnavailable(job.triggerID)
        }
        guard let accountID = job.accountID,
              let configuration = try store.accountConfiguration(accountID: accountID) else {
            let missingAccountID = job.accountID ?? "unknown"
            try failQueuedJob(job, at: now, error: PluginRuntimeServiceError.accountNotConfigured(missingAccountID))
            throw PluginRuntimeServiceError.accountNotConfigured(missingAccountID)
        }

        return try await executeInstalledPluginRequest(
            PluginRuntimeRequest(
                pluginID: job.pluginID,
                requestID: requestID,
                accountID: configuration.id,
                accountName: configuration.accountName,
                variables: configuration.variables,
                headers: try resolvedHeaders(base: headers, pluginID: job.pluginID, configuration: configuration, now: now),
                now: now
            ),
            jobID: job.id,
            triggerID: job.triggerID,
            queuedAt: job.queuedAt,
            upsertAccount: false
        )
    }

    public func runConfiguredPluginRequest(
        pluginID: String,
        requestID: String,
        accountID: String,
        headers: [String: String] = [:],
        now: Date = Date()
    ) async throws -> PluginRequestJobResult {
        guard let configuration = try store.accountConfiguration(accountID: accountID) else {
            throw PluginRuntimeServiceError.accountNotConfigured(accountID)
        }
        return try await runInstalledPluginRequest(
            PluginRuntimeRequest(
                pluginID: pluginID,
                requestID: requestID,
                accountID: configuration.id,
                accountName: configuration.accountName,
                variables: configuration.variables,
                headers: try resolvedHeaders(base: headers, pluginID: pluginID, configuration: configuration, now: now),
                now: now
            )
        )
    }

    public func runInstalledPluginRequest(_ request: PluginRuntimeRequest) async throws -> PluginRequestJobResult {
        let jobID = jobID(pluginID: request.pluginID, requestID: request.requestID, accountID: request.accountID, date: request.now)
        return try await executeInstalledPluginRequest(
            request,
            jobID: jobID,
            triggerID: "manual_\(request.requestID)",
            queuedAt: request.now,
            upsertAccount: true
        )
    }

    private func executeInstalledPluginRequest(
        _ request: PluginRuntimeRequest,
        jobID: String,
        triggerID: String,
        queuedAt: Date,
        upsertAccount: Bool
    ) async throws -> PluginRequestJobResult {
        guard let plugin = try store.installedPlugin(id: request.pluginID), plugin.enabled else {
            throw PluginRuntimeServiceError.pluginNotInstalled(request.pluginID)
        }
        guard let installedVersion = try store.installedPluginVersions(pluginID: request.pluginID)
            .sorted(by: { $0.installedAt > $1.installedAt })
            .first,
            let packagePath = installedVersion.packagePath else {
            throw PluginRuntimeServiceError.packageUnavailable(request.pluginID)
        }
        try requireGrantedPermissionIfDeclared(
            pluginID: request.pluginID,
            manifest: installedVersion.manifest,
            permission: .network
        )

        let packageData = try Data(contentsOf: URL(fileURLWithPath: packagePath))
        let definition = try PluginPackageDefinition.decode(from: packageData)

        if upsertAccount {
            try store.upsertAccount(
                Account(
                    id: request.accountID,
                    pluginID: request.pluginID,
                    provider: request.pluginID,
                    displayName: request.accountName
                ),
                updatedAt: request.now
            )
        }
        try store.upsertJob(
            JobRecord(
                id: jobID,
                pluginID: request.pluginID,
                triggerID: triggerID,
                accountID: request.accountID,
                status: .running,
                queuedAt: queuedAt,
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
                    triggerID: triggerID,
                    accountID: request.accountID,
                    status: .success,
                    queuedAt: queuedAt,
                    startedAt: request.now,
                    finishedAt: request.now,
                    emittedEventIDs: result.mappingOutput.events.map(\.id)
                )
            )
            if let job = try store.job(id: jobID) {
                try store.insertJobAuditEntry(for: job, timestamp: request.now)
            }
            try recordTriggerSuccess(triggerID: triggerID, at: request.now)
            try await processAutomation(for: result)
            return result
        } catch {
            try store.upsertJob(
                JobRecord(
                    id: jobID,
                    pluginID: request.pluginID,
                    triggerID: triggerID,
                    accountID: request.accountID,
                    status: .failed,
                    queuedAt: queuedAt,
                    startedAt: request.now,
                    finishedAt: request.now,
                    error: error.localizedDescription
                )
            )
            if let job = try store.job(id: jobID) {
                try store.insertJobAuditEntry(for: job, timestamp: request.now)
            }
            try recordTriggerFailure(triggerID: triggerID, at: request.now)
            throw error
        }
    }

    private func failQueuedJob(_ job: JobRecord, at date: Date, error: Error) throws {
        try store.upsertJob(
            JobRecord(
                id: job.id,
                pluginID: job.pluginID,
                triggerID: job.triggerID,
                accountID: job.accountID,
                status: .failed,
                queuedAt: job.queuedAt,
                startedAt: date,
                finishedAt: date,
                error: error.localizedDescription
            )
        )
        if let failedJob = try store.job(id: job.id) {
            try store.insertJobAuditEntry(for: failedJob, timestamp: date)
        }
        try recordTriggerFailure(triggerID: job.triggerID, at: date)
    }

    private func recordTriggerSuccess(triggerID: String, at date: Date) throws {
        guard var trigger = try store.trigger(id: triggerID), trigger.kind == .cron else {
            return
        }
        trigger.failureCount = 0
        trigger.lastRunAt = date
        trigger.nextRunAt = nextRunDate(for: trigger, from: date)
        try store.upsertTrigger(trigger, updatedAt: date)
    }

    private func recordTriggerFailure(triggerID: String, at date: Date) throws {
        guard var trigger = try store.trigger(id: triggerID), trigger.kind == .cron else {
            return
        }
        trigger.failureCount += 1
        trigger.lastRunAt = date
        trigger.nextRunAt = date.addingTimeInterval(backoffDelay(forFailureCount: trigger.failureCount))
        try store.upsertTrigger(trigger, updatedAt: date)
    }

    private func insertSkippedTriggerAudit(
        _ trigger: TriggerDefinition,
        reason: String,
        detail: String,
        at date: Date
    ) throws {
        try store.insertAuditEntry(
            AuditEntry(
                id: "aud_\(sanitizedIDPart(trigger.id))_skipped_\(reason)",
                title: "Plugin trigger skipped",
                detail: detail,
                timestamp: date,
                status: "skipped"
            )
        )
    }

    private func processAutomation(for result: PluginRequestJobResult) async throws {
        let insertedEventIDs = result.commitResult.eventResults.compactMap { ingestionResult -> String? in
            guard case .inserted(let eventID, _) = ingestionResult else {
                return nil
            }
            return eventID
        }
        guard insertedEventIDs.isEmpty == false else {
            return
        }
        let pipeline = AutomationPipeline(
            store: store,
            actionRunner: actionRunner,
            effectDispatcher: effectDispatcher,
            providerActionExecutor: self
        )
        for event in result.mappingOutput.events where insertedEventIDs.contains(event.id) {
            _ = try await pipeline.processStoredRules(for: event)
        }
    }

    public func execute(_ action: ActionRuntimeProviderAction) async throws -> [String: String] {
        let target = try providerActionTarget(for: action)
        try requireGrantedPermissionIfDeclared(pluginID: target.plugin.id, manifest: target.manifest, permission: .writeActions)
        try requireGrantedPermissionIfDeclared(pluginID: target.plugin.id, manifest: target.manifest, permission: .network)
        let account = try providerActionAccount(for: action, pluginID: target.plugin.id)
        let headers = try resolvedHeaders(
            base: [:],
            pluginID: target.plugin.id,
            configuration: account,
            now: Date()
        )
        let requestInput = PluginRequestJobInput(
            pluginID: target.plugin.id,
            accountID: account.id,
            provider: target.plugin.id,
            requestID: target.action.request,
            variables: account.variables.merging(action.parameters) { _, actionValue in actionValue },
            headers: headers,
            capturedAt: Date()
        )
        let runner = PluginRequestJobRunner(
            transport: transport,
            committer: PluginMappingOutputCommitter(store: store)
        )
        let request = try runner.request(
            definition: target.request,
            input: requestInput,
            context: providerActionTemplateContext(action: action, account: account)
        )
        let response = try await runner.response(for: request, requestID: target.action.request)
        guard (200..<300).contains(response.statusCode) else {
            throw PluginRuntimeServiceError.actionRequestFailed(action: action.action, statusCode: response.statusCode)
        }
        var result = [
            "plugin_id": target.plugin.id,
            "account_id": account.id,
            "request_id": target.action.request,
            "status_code": String(response.statusCode),
            "url": response.url.absoluteString
        ]
        if let body = String(data: response.data, encoding: .utf8), body.isEmpty == false {
            result["body"] = body
        }
        return result
    }

    private struct ProviderActionTarget {
        var plugin: InstalledPlugin
        var manifest: PluginManifest
        var definition: PluginPackageDefinition
        var action: PackagedPluginAction
        var request: PackagedPluginRequest
    }

    private func providerActionTarget(for action: ActionRuntimeProviderAction) throws -> ProviderActionTarget {
        var matches: [ProviderActionTarget] = []
        for plugin in try store.installedPlugins() where plugin.enabled {
            guard let definition = try store.installedPluginDefinition(pluginID: plugin.id),
                  let declaredAction = definition.actions.first(where: { $0.id == action.action }),
                  let request = definition.requests.requests[declaredAction.request],
                  let manifest = try store.installedPluginVersions(pluginID: plugin.id)
                    .sorted(by: { $0.installedAt > $1.installedAt })
                    .first?
                    .manifest else {
                continue
            }
            matches.append(ProviderActionTarget(
                plugin: plugin,
                manifest: manifest,
                definition: definition,
                action: declaredAction,
                request: request
            ))
        }
        if let provider = action.provider,
           let exact = matches.first(where: { $0.plugin.id == provider }) {
            return exact
        }
        if let suffix = action.action.split(separator: ".").first.map(String.init),
           let suffixMatch = matches.first(where: { $0.plugin.id.hasSuffix(".\(suffix)") }) {
            return suffixMatch
        }
        guard let first = matches.first else {
            throw PluginRuntimeServiceError.actionUnavailable(action.action)
        }
        return first
    }

    private func providerActionAccount(for action: ActionRuntimeProviderAction, pluginID: String) throws -> PluginAccountConfiguration {
        if let accountID = action.parameters["account_id"] ?? action.parameters["accountID"],
           let account = try store.accountConfiguration(accountID: accountID) {
            return account
        }
        if let resource = try store.resource(id: action.event.resourceID),
           resource.pluginID == pluginID,
           let account = try store.accountConfiguration(accountID: resource.accountID) {
            return account
        }
        guard let account = try store.accountConfigurations(pluginID: pluginID).first else {
            throw PluginRuntimeServiceError.accountNotConfigured(pluginID)
        }
        return account
    }

    private func providerActionTemplateContext(
        action: ActionRuntimeProviderAction,
        account: PluginAccountConfiguration
    ) -> MappingTemplateContext {
        let accountValue = MappingJSONValue.object(account.variables.mapValues(MappingJSONValue.string))
        let actionValue = MappingJSONValue.object(action.parameters.mapValues(MappingJSONValue.string))
        let item = account.variables
            .merging(action.parameters) { _, actionValue in actionValue }
            .mapValues(MappingJSONValue.string)
        return MappingTemplateContext(scopes: [
            "item": .object(item),
            "account": accountValue,
            "action": actionValue,
            "event": action.event.mappingValue
        ])
    }

    private func isDueCronTrigger(_ trigger: TriggerDefinition, at date: Date) -> Bool {
        guard trigger.enabled, trigger.kind == .cron else {
            return false
        }
        if let nextRunAt = trigger.nextRunAt {
            return nextRunAt <= date
        }
        guard let lastRunAt = trigger.lastRunAt else {
            return true
        }
        guard let intervalSeconds = trigger.intervalSeconds else {
            return false
        }
        return lastRunAt.addingTimeInterval(intervalSeconds) <= date
    }

    private func nextRunDate(for trigger: TriggerDefinition, from date: Date) -> Date? {
        guard trigger.kind == .cron, let intervalSeconds = trigger.intervalSeconds else {
            return nil
        }
        return date.addingTimeInterval(intervalSeconds)
    }

    private func backoffDelay(forFailureCount failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return 0 }
        let exponent = min(failureCount - 1, 10)
        let delay = baseBackoffSeconds * pow(2, Double(exponent))
        return min(delay, maxBackoffSeconds)
    }

    private func configuredAccountIDs(for trigger: TriggerDefinition) throws -> [String] {
        if let accountID = trigger.accountID,
           try store.accountConfiguration(accountID: accountID) != nil {
            return [accountID]
        }
        return try store.accountConfigurations(pluginID: trigger.pluginID).map(\.id)
    }

    private func hasGrantedPermission(pluginID: String, permission: PluginPermission) throws -> Bool {
        try store.pluginPermissions(pluginID: pluginID).contains { record in
            record.permission == permission && record.granted
        }
    }

    private func requireGrantedPermission(pluginID: String, permission: PluginPermission) throws {
        guard try hasGrantedPermission(pluginID: pluginID, permission: permission) else {
            throw PluginRuntimeServiceError.missingPermission(pluginID: pluginID, permission: permission)
        }
    }

    private func requireGrantedPermissionIfDeclared(pluginID: String, manifest: PluginManifest, permission: PluginPermission) throws {
        guard manifest.permissions.contains(permission) else {
            return
        }
        try requireGrantedPermission(pluginID: pluginID, permission: permission)
    }

    private func resolvedHeaders(
        base headers: [String: String],
        pluginID: String,
        configuration: PluginAccountConfiguration,
        now: Date
    ) throws -> [String: String] {
        var resolved = headers
        guard let credentialRef = configuration.credentialRef else {
            return resolved
        }
        let manifest = try store.installedPluginVersions(pluginID: pluginID)
            .sorted(by: { $0.installedAt > $1.installedAt })
            .first?
            .manifest
        if let manifest {
            try requireGrantedPermissionIfDeclared(pluginID: pluginID, manifest: manifest, permission: .keychain)
            if manifest.permissions.contains(.privateKey),
               configuration.authType == AuthKind.jwtAPIKey.rawValue || configuration.authType == AuthKind.privateKeyJWT.rawValue {
                try requireGrantedPermission(pluginID: pluginID, permission: .privateKey)
            }
        } else {
            try requireGrantedPermission(pluginID: pluginID, permission: .keychain)
        }
        guard let credentialStore,
              let data = try credentialStore.read(reference: credentialRef) else {
            return resolved
        }
        switch configuration.authType {
        case AuthKind.bearerToken.rawValue:
            guard resolved["Authorization"] == nil else {
                return resolved
            }
            guard let token = String(data: data, encoding: .utf8),
                  token.isEmpty == false else {
                return resolved
            }
            resolved["Authorization"] = "Bearer \(token)"
        case AuthKind.basicAuth.rawValue:
            guard resolved["Authorization"] == nil else {
                return resolved
            }
            let credentials = try JSONDecoder().decode(PluginAuthCredentialBundle.self, from: data)
            if let authorization = basicAuthorizationHeader(credentials: credentials) {
                resolved["Authorization"] = authorization
            }
        case AuthKind.jwtAPIKey.rawValue:
            guard resolved["Authorization"] == nil else {
                return resolved
            }
            let credentials = try JSONDecoder().decode(PluginAuthCredentialBundle.self, from: data)
            let token = try PluginJWTSigner.appStoreConnectToken(credentials: credentials, now: now)
            resolved["Authorization"] = "Bearer \(token)"
        case AuthKind.apiKey.rawValue:
            let credentials = try JSONDecoder().decode(PluginAuthCredentialBundle.self, from: data)
            guard let apiKey = credentialValue(["apiKey", "api_key", "key", "token", "secret"], in: credentials) else {
                return resolved
            }
            let headerName = try apiKeyHeaderName(pluginID: pluginID)
            guard resolved[headerName] == nil else {
                return resolved
            }
            resolved[headerName] = apiKey
        default:
            break
        }
        return resolved
    }

    private func apiKeyHeaderName(pluginID: String) throws -> String {
        let rawName = try store.installedPlugin(id: pluginID)?
            .auth?
            .placement?
            .name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawName, rawName.isEmpty == false else {
            return "X-API-Key"
        }
        return rawName
    }

    private func basicAuthorizationHeader(credentials: PluginAuthCredentialBundle) -> String? {
        guard let username = credentialValue(["username", "email", "account", "user"], in: credentials),
              let password = credentialValue(["password", "apiToken", "token", "secret"], in: credentials) else {
            return nil
        }
        let raw = "\(username):\(password)"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    private func credentialValue(_ keys: [String], in credentials: PluginAuthCredentialBundle) -> String? {
        for key in keys {
            if let value = credentials.fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    private func jobID(pluginID: String, requestID: String, accountID: String, date: Date) -> String {
        let raw = "\(pluginID)_\(requestID)_\(accountID)_\(Int(date.timeIntervalSince1970))"
        return "job_\(sanitizedIDPart(raw))"
    }

    private func sanitizedIDPart(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func bundledManualRequestID(pluginID: String) -> String? {
        switch pluginID {
        case WebsitePluginSetup.pluginID:
            WebsitePluginSetup.requestID
        default:
            nil
        }
    }
}
