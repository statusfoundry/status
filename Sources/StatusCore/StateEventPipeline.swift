import Foundation

public struct StateEventMappingDefinition: Equatable, Sendable {
    public var provider: String
    public var eventType: String
    public var resourceID: String
    public var resourceName: String
    public var severity: Severity
    public var title: String
    public var summary: String
    public var actionURL: URL?
    public var conditions: [MappingCondition]
    public var fingerprintStatePath: String

    public init(
        provider: String,
        eventType: String,
        resourceID: String,
        resourceName: String,
        severity: Severity,
        title: String,
        summary: String,
        actionURL: URL? = nil,
        conditions: [MappingCondition],
        fingerprintStatePath: String
    ) {
        self.provider = provider
        self.eventType = eventType
        self.resourceID = resourceID
        self.resourceName = resourceName
        self.severity = severity
        self.title = title
        self.summary = summary
        self.actionURL = actionURL
        self.conditions = conditions
        self.fingerprintStatePath = fingerprintStatePath
    }
}

public struct StateEventPipelineResult: Equatable, Sendable {
    public var observation: StateObservationResult
    public var events: [Event]
    public var ingestionResults: [EventIngestionResult]

    public init(observation: StateObservationResult, events: [Event], ingestionResults: [EventIngestionResult]) {
        self.observation = observation
        self.events = events
        self.ingestionResults = ingestionResults
    }
}

public final class StateEventPipeline {
    private let detector: StateChangeDetector
    private let ingestor: EventIngestor

    public init(detector: StateChangeDetector, ingestor: EventIngestor) {
        self.detector = detector
        self.ingestor = ingestor
    }

    public func process(
        resourceID: String,
        currentState: [String: String],
        jobID: String? = nil,
        capturedAt: Date,
        mappings: [StateEventMappingDefinition]
    ) throws -> StateEventPipelineResult {
        let observation = try detector.record(
            resourceID: resourceID,
            state: currentState,
            jobID: jobID,
            capturedAt: capturedAt
        )
        let previousState = previousState(from: observation)
        let events = mappings.compactMap {
            makeEvent(from: $0, currentState: currentState, previousState: previousState, timestamp: capturedAt)
        }
        let ingestionResults = try events.map { try ingestor.ingest($0) }

        return StateEventPipelineResult(
            observation: observation,
            events: events,
            ingestionResults: ingestionResults
        )
    }

    private func makeEvent(
        from mapping: StateEventMappingDefinition,
        currentState: [String: String],
        previousState: [String: String]?,
        timestamp: Date
    ) -> Event? {
        guard MappingConditionEvaluator.evaluateAll(
            mapping.conditions,
            currentState: currentState,
            previousState: previousState
        ) else {
            return nil
        }

        let fingerprintStateField = MappingConditionEvaluator.stateFieldName(from: mapping.fingerprintStatePath)
        let relevantState = currentState[fingerprintStateField] ?? ""
        let fingerprint = EventFingerprint.make(
            EventFingerprintInput(
                provider: mapping.provider,
                eventType: mapping.eventType,
                resourceID: mapping.resourceID,
                relevantState: relevantState
            )
        )

        return Event(
            id: eventID(fingerprint: fingerprint),
            provider: mapping.provider,
            type: mapping.eventType,
            resourceID: mapping.resourceID,
            resourceName: mapping.resourceName,
            severity: mapping.severity,
            title: mapping.title,
            summary: mapping.summary,
            timestamp: timestamp,
            actionURL: mapping.actionURL,
            fingerprint: fingerprint
        )
    }

    private func previousState(from observation: StateObservationResult) -> [String: String]? {
        switch observation {
        case .firstObservation:
            nil
        case .unchanged(let current):
            current.state
        case .changed(let previous, _):
            previous.state
        }
    }

    private func eventID(fingerprint: String) -> String {
        "evt_" + fingerprint.prefix(26)
    }
}
