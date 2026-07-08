import Foundation

public protocol ActionEffectDispatcher: Sendable {
    func dispatch(_ effects: ActionRuntimeEffects) async throws
}

public protocol ProviderActionExecutor: Sendable {
    func execute(_ action: ActionRuntimeProviderAction) async throws -> [String: String]
}

public struct NoopActionEffectDispatcher: ActionEffectDispatcher {
    public init() {}

    public func dispatch(_ effects: ActionRuntimeEffects) async throws {}
}

public struct ActionEffectDispatchFailure: Error, Equatable, LocalizedError, Sendable {
    public var actionRunID: String
    public var message: String

    public init(actionRunID: String, message: String) {
        self.actionRunID = actionRunID
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public final class RecordingActionEffectDispatcher: ActionEffectDispatcher, @unchecked Sendable {
    public private(set) var dispatchedEffects: [ActionRuntimeEffects] = []

    public init() {}

    public func dispatch(_ effects: ActionRuntimeEffects) async throws {
        dispatchedEffects.append(effects)
    }
}
