import Foundation

public enum TriggerKind: String, Codable, CaseIterable, Sendable {
    case cron
    case manual
    case push
    case event
    case appLifecycle = "app-lifecycle"
}

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case success
    case failed
    case cancelled
    case skipped
}

public struct TriggerDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var pluginID: String
    public var accountID: String?
    public var kind: TriggerKind
    public var label: String
    public var enabled: Bool
    public var intervalSeconds: TimeInterval?
    public var requestID: String?
    public var failureCount: Int
    public var lastRunAt: Date?
    public var nextRunAt: Date?

    public init(
        id: String,
        pluginID: String,
        accountID: String? = nil,
        kind: TriggerKind,
        label: String,
        enabled: Bool = true,
        intervalSeconds: TimeInterval? = nil,
        requestID: String? = nil,
        failureCount: Int = 0,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.pluginID = pluginID
        self.accountID = accountID
        self.kind = kind
        self.label = label
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.requestID = requestID
        self.failureCount = failureCount
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
    }
}

public struct JobRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var pluginID: String
    public var triggerID: String
    public var accountID: String?
    public var status: JobStatus
    public var queuedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var error: String?
    public var emittedEventIDs: [String]

    public init(
        id: String,
        pluginID: String,
        triggerID: String,
        accountID: String? = nil,
        status: JobStatus,
        queuedAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        error: String? = nil,
        emittedEventIDs: [String] = []
    ) {
        self.id = id
        self.pluginID = pluginID
        self.triggerID = triggerID
        self.accountID = accountID
        self.status = status
        self.queuedAt = queuedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.error = error
        self.emittedEventIDs = emittedEventIDs
    }
}

public final class InMemoryJobQueue {
    private var jobs: [JobRecord] = []

    public init() {}

    public func enqueue(trigger: TriggerDefinition, at date: Date) -> JobRecord {
        let job = JobRecord(
            id: "job_\(trigger.id)_\(Int(date.timeIntervalSince1970))",
            pluginID: trigger.pluginID,
            triggerID: trigger.id,
            accountID: trigger.accountID,
            status: .queued,
            queuedAt: date
        )
        jobs.append(job)
        return job
    }

    public func nextQueuedJob() -> JobRecord? {
        jobs
            .filter { $0.status == .queued }
            .sorted { $0.queuedAt < $1.queuedAt }
            .first
    }

    public func start(jobID: String, at date: Date) {
        update(jobID: jobID) { job in
            job.status = .running
            job.startedAt = date
        }
    }

    public func finish(jobID: String, at date: Date, emittedEventIDs: [String] = []) {
        update(jobID: jobID) { job in
            job.status = .success
            job.finishedAt = date
            job.error = nil
            job.emittedEventIDs = emittedEventIDs
        }
    }

    public func fail(jobID: String, at date: Date, error: String) {
        update(jobID: jobID) { job in
            job.status = .failed
            job.finishedAt = date
            job.error = error
        }
    }

    public func job(id: String) -> JobRecord? {
        jobs.first { $0.id == id }
    }

    public func allJobs() -> [JobRecord] {
        jobs
    }

    private func update(jobID: String, mutate: (inout JobRecord) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }
        mutate(&jobs[index])
    }
}
