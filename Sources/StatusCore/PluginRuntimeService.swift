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
        }
    }
}

public final class PluginRuntimeService: @unchecked Sendable {
    private let store: StatusPersistenceStore
    private let transport: PluginRequestHTTPTransport
    private let actionRunner: ActionRunner
    private let effectDispatcher: ActionEffectDispatcher

    public init(
        store: StatusPersistenceStore,
        transport: PluginRequestHTTPTransport = URLSessionPluginRequestTransport(),
        actionRunner: ActionRunner = ActionRunner(),
        effectDispatcher: ActionEffectDispatcher = NoopActionEffectDispatcher()
    ) {
        self.store = store
        self.transport = transport
        self.actionRunner = actionRunner
        self.effectDispatcher = effectDispatcher
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
            guard let requestID = trigger.requestID,
                  let accountID = try configuredAccountID(for: trigger) else {
                continue
            }
            let job = JobRecord(
                id: jobID(pluginID: trigger.pluginID, requestID: requestID, accountID: accountID, date: now),
                pluginID: trigger.pluginID,
                triggerID: trigger.id,
                accountID: accountID,
                status: .queued,
                queuedAt: now
            )
            try store.upsertJob(job)
            trigger.lastRunAt = now
            trigger.nextRunAt = nextRunDate(for: trigger, from: now)
            try store.upsertTrigger(trigger, updatedAt: now)
            jobs.append(job)
        }
        return jobs
    }

    public func runDueConfiguredPluginJobs(
        headers: [String: String] = [:],
        now: Date = Date()
    ) async throws -> [PluginRequestJobResult] {
        let jobs = try enqueueDueConfiguredPluginJobs(now: now)
        var results: [PluginRequestJobResult] = []
        for job in jobs {
            results.append(try await runQueuedPluginJob(jobID: job.id, headers: headers, now: now))
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
                headers: headers,
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
                headers: headers,
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
            try processAutomation(for: result)
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
    }

    private func processAutomation(for result: PluginRequestJobResult) throws {
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
            effectDispatcher: effectDispatcher
        )
        for event in result.mappingOutput.events where insertedEventIDs.contains(event.id) {
            _ = try pipeline.processStoredRules(for: event)
        }
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

    private func configuredAccountID(for trigger: TriggerDefinition) throws -> String? {
        if let accountID = trigger.accountID,
           try store.accountConfiguration(accountID: accountID) != nil {
            return accountID
        }
        return try store.accountConfigurations(pluginID: trigger.pluginID).first?.id
    }

    private func jobID(pluginID: String, requestID: String, accountID: String, date: Date) -> String {
        let raw = "\(pluginID)_\(requestID)_\(accountID)_\(Int(date.timeIntervalSince1970))"
        let sanitized = raw
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "job_\(sanitized)"
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
