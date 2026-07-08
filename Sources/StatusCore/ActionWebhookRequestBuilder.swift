import Foundation

public enum ActionWebhookRequestBuilderError: Error, Equatable, LocalizedError, Sendable {
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            "Webhook payload could not be encoded as JSON."
        }
    }
}

public struct ActionWebhookRequestBuilder: Sendable {
    public init() {}

    public func request(for webhook: ActionRuntimeWebhook) throws -> PluginHTTPRequest {
        let body: Data
        do {
            body = try JSONEncoder().encode(webhook.payload)
        } catch {
            throw ActionWebhookRequestBuilderError.invalidPayload
        }

        return PluginHTTPRequest(
            method: "POST",
            url: webhook.url,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": "Status/0.1"
            ],
            body: body,
            timeoutSeconds: 30
        )
    }
}
