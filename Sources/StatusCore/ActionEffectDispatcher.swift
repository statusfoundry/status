import Foundation

public protocol ActionEffectDispatcher: Sendable {
    func dispatch(_ effects: ActionRuntimeEffects) throws
}

public struct NoopActionEffectDispatcher: ActionEffectDispatcher {
    public init() {}

    public func dispatch(_ effects: ActionRuntimeEffects) throws {}
}

public final class RecordingActionEffectDispatcher: ActionEffectDispatcher, @unchecked Sendable {
    public private(set) var dispatchedEffects: [ActionRuntimeEffects] = []

    public init() {}

    public func dispatch(_ effects: ActionRuntimeEffects) throws {
        dispatchedEffects.append(effects)
    }
}
