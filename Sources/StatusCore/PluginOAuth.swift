import CryptoKit
import Foundation
import Security

public struct PluginOAuthTokenSet: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var tokenType: String
    public var scope: String?
    public var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case tokenType
        case scope
        case expiresAt
    }

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        tokenType: String = "Bearer",
        scope: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresAt = expiresAt
    }

    public var authorizationHeader: String? {
        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        let normalizedType = tokenType.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Bearer"
        return "\(normalizedType) \(trimmed)"
    }

    public func needsRefresh(at date: Date, leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else {
            return false
        }
        return expiresAt <= date.addingTimeInterval(leeway)
    }
}

public struct PluginOAuthAuthorizationRequest: Equatable, Sendable {
    public var url: URL
    public var codeVerifier: String
    public var state: String

    public init(url: URL, codeVerifier: String, state: String) {
        self.url = url
        self.codeVerifier = codeVerifier
        self.state = state
    }
}

public struct PluginOAuthTokenResponse: Codable, Equatable, Sendable {
    public var accessToken: String?
    public var refreshToken: String?
    public var tokenType: String?
    public var scope: String?
    public var expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
    }

    public init(
        accessToken: String? = nil,
        refreshToken: String? = nil,
        tokenType: String? = nil,
        scope: String? = nil,
        expiresIn: TimeInterval? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresIn = expiresIn
    }
}

public enum PluginOAuthError: Error, Equatable, LocalizedError, Sendable {
    case missingOAuthConfiguration(String)
    case invalidAuthorizationURL(String)
    case missingApplicationID(String)
    case missingRefreshToken(String)
    case authorizationCallbackMissingCode
    case authorizationStateMismatch
    case authorizationRedirectMismatch(expected: String, actual: String)
    case authorizationDenied(String)
    case tokenExchangeFailed(statusCode: Int)
    case tokenRefreshFailed(statusCode: Int)
    case invalidTokenResponse

    public var errorDescription: String? {
        switch self {
        case .missingOAuthConfiguration(let pluginID):
            "Plugin does not declare OAuth configuration: \(pluginID)"
        case .invalidAuthorizationURL(let url):
            "OAuth authorization URL is invalid: \(url)"
        case .missingApplicationID(let pluginID):
            "OAuth plugin is missing a public application ID: \(pluginID)"
        case .missingRefreshToken(let pluginID):
            "OAuth token is expired and no refresh token is available: \(pluginID)"
        case .authorizationCallbackMissingCode:
            "OAuth callback did not include an authorization code."
        case .authorizationStateMismatch:
            "OAuth callback state did not match the active connection request."
        case .authorizationRedirectMismatch(let expected, let actual):
            "OAuth callback redirect did not match. Expected \(expected), got \(actual)."
        case .authorizationDenied(let message):
            "OAuth authorization was denied: \(message)"
        case .tokenExchangeFailed(let statusCode):
            "OAuth token exchange failed with HTTP \(statusCode)."
        case .tokenRefreshFailed(let statusCode):
            "OAuth token refresh failed with HTTP \(statusCode)."
        case .invalidTokenResponse:
            "OAuth token response did not include an access token."
        }
    }
}

public enum PluginOAuth {
    public static func authorizationRequest(
        pluginID: String,
        auth: PackagedPluginAuth,
        state: String = randomURLSafeString(byteCount: 18),
        codeVerifier: String = randomURLSafeString(byteCount: 32)
    ) throws -> PluginOAuthAuthorizationRequest {
        guard auth.type == .oauth2, let config = auth.oauth2 else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard let clientID = auth.applicationId?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            throw PluginOAuthError.missingApplicationID(pluginID)
        }
        guard var components = URLComponents(url: config.authorizationURL, resolvingAgainstBaseURL: false) else {
            throw PluginOAuthError.invalidAuthorizationURL(config.authorizationURL.absoluteString)
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "response_type", value: "code"))
        queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        queryItems.append(URLQueryItem(name: "redirect_uri", value: config.redirectURI))
        queryItems.append(URLQueryItem(name: "state", value: state))
        queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge(for: codeVerifier)))
        queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        if config.scopes.isEmpty == false {
            queryItems.append(URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")))
        }
        for (name, value) in config.additionalAuthorizationParameters.sorted(by: { $0.key < $1.key }) {
            queryItems.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw PluginOAuthError.invalidAuthorizationURL(config.authorizationURL.absoluteString)
        }
        return PluginOAuthAuthorizationRequest(url: url, codeVerifier: codeVerifier, state: state)
    }

    public static func tokenSet(
        pluginID: String,
        auth: PackagedPluginAuth,
        request: PluginOAuthAuthorizationRequest,
        callbackURL: URL,
        transport: PluginRequestHTTPTransport = URLSessionPluginRequestTransport(),
        now: Date = Date()
    ) async throws -> PluginOAuthTokenSet {
        guard auth.type == .oauth2, let config = auth.oauth2 else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard let clientID = auth.applicationId?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            throw PluginOAuthError.missingApplicationID(pluginID)
        }
        try validateCallbackRedirect(callbackURL, redirectURI: config.redirectURI)
        let callback = try callbackParameters(callbackURL, expectedState: request.state)
        let body = formURLEncoded([
            "grant_type": "authorization_code",
            "code": callback.code,
            "redirect_uri": config.redirectURI,
            "client_id": clientID,
            "code_verifier": request.codeVerifier
        ])
        let response = try await transport.response(
            for: PluginHTTPRequest(
                method: "POST",
                url: config.tokenURL,
                headers: [
                    "Accept": "application/json",
                    "Content-Type": "application/x-www-form-urlencoded"
                ],
                body: Data(body.utf8),
                timeoutSeconds: 30
            )
        )
        guard (200..<300).contains(response.statusCode) else {
            throw PluginOAuthError.tokenExchangeFailed(statusCode: response.statusCode)
        }
        return try tokenSet(from: response.data, now: now)
    }

    public static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    public static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func callbackParameters(_ callbackURL: URL, expectedState: String) throws -> (code: String, state: String) {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let fields = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        if let error = fields["error"] {
            throw PluginOAuthError.authorizationDenied(fields["error_description"] ?? error)
        }
        guard fields["state"] == expectedState else {
            throw PluginOAuthError.authorizationStateMismatch
        }
        guard let code = fields["code"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              code.isEmpty == false else {
            throw PluginOAuthError.authorizationCallbackMissingCode
        }
        return (code, expectedState)
    }

    private static func validateCallbackRedirect(_ callbackURL: URL, redirectURI: String) throws {
        guard let expectedURL = URL(string: redirectURI),
              let expected = URLComponents(url: expectedURL, resolvingAgainstBaseURL: false),
              let actual = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              expected.scheme == actual.scheme,
              (expected.host ?? "") == (actual.host ?? ""),
              normalizedPath(expected.path) == normalizedPath(actual.path) else {
            throw PluginOAuthError.authorizationRedirectMismatch(
                expected: normalizedRedirectDescription(redirectURI),
                actual: normalizedRedirectDescription(callbackURL.absoluteString)
            )
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        path == "/" ? "" : path
    }

    private static func normalizedRedirectDescription(_ value: String) -> String {
        guard var components = URLComponents(string: value) else {
            return value
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? value
    }

    private static func tokenSet(from data: Data, now: Date) throws -> PluginOAuthTokenSet {
        let response = try JSONDecoder().decode(PluginOAuthTokenResponse.self, from: data)
        guard let accessToken = response.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              accessToken.isEmpty == false else {
            throw PluginOAuthError.invalidTokenResponse
        }
        return PluginOAuthTokenSet(
            accessToken: accessToken,
            refreshToken: response.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            tokenType: response.tokenType?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Bearer",
            scope: response.scope?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            expiresAt: response.expiresIn.map { now.addingTimeInterval($0) }
        )
    }

    private static func formURLEncoded(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(urlFormEncode(key))=\(urlFormEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func urlFormEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
