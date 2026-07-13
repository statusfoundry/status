import CryptoKit
import Foundation
import Security

public struct PluginOAuthTokenSet: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var tokenType: String
    public var scope: String?
    public var expiresAt: Date?
    public var clientID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case tokenType
        case scope
        case expiresAt
        case clientID
    }

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        tokenType: String = "Bearer",
        scope: String? = nil,
        expiresAt: Date? = nil,
        clientID: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresAt = expiresAt
        self.clientID = clientID
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
    public var clientID: String?

    public init(url: URL, codeVerifier: String, state: String, clientID: String? = nil) {
        self.url = url
        self.codeVerifier = codeVerifier
        self.state = state
        self.clientID = clientID
    }
}

public struct PluginOAuthDeviceAuthorizationRequest: Equatable, Sendable {
    public var verificationURL: URL
    public var userCode: String
    public var deviceCode: String
    public var expiresAt: Date
    public var interval: TimeInterval
    public var clientID: String?

    public init(
        verificationURL: URL,
        userCode: String,
        deviceCode: String,
        expiresAt: Date,
        interval: TimeInterval = 5,
        clientID: String? = nil
    ) {
        self.verificationURL = verificationURL
        self.userCode = userCode
        self.deviceCode = deviceCode
        self.expiresAt = expiresAt
        self.interval = interval
        self.clientID = clientID
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

private struct PluginOAuthDeviceAuthorizationResponse: Codable {
    var deviceCode: String
    var userCode: String
    var verificationURI: String
    var expiresIn: TimeInterval
    var interval: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct PluginOAuthDeviceTokenErrorResponse: Codable {
    var error: String
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

public enum PluginOAuthError: Error, Equatable, LocalizedError, Sendable {
    case missingOAuthConfiguration(String)
    case invalidAuthorizationURL(String)
    case missingApplicationID(String)
    case missingRefreshToken(String)
    case invalidRedirectURI(String)
    case authorizationCallbackMissingCode
    case authorizationStateMismatch
    case authorizationRedirectMismatch(expected: String, actual: String)
    case authorizationDenied(String)
    case tokenExchangeFailed(statusCode: Int)
    case tokenRefreshFailed(statusCode: Int)
    case authorizationPending
    case authorizationExpired
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
        case .invalidRedirectURI(let redirectURI):
            "OAuth redirect URI must match com.statusfoundry.status.oauth:/{provider}: \(redirectURI)"
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
        case .authorizationPending:
            "OAuth authorization is not complete yet."
        case .authorizationExpired:
            "OAuth authorization expired. Start the connection again."
        case .invalidTokenResponse:
            "OAuth token response did not include an access token."
        }
    }
}

public enum PluginOAuth {
    public static let callbackScheme = "com.statusfoundry.status.oauth"
    public static let clientIDSetupFieldKey = "_status.oauth.clientId"

    public static func redirectURI(provider: String) -> String {
        "\(callbackScheme):/\(provider)"
    }

    public static func authorizationRequest(
        pluginID: String,
        auth: PackagedPluginAuth,
        clientIDOverride: String? = nil,
        state: String = randomURLSafeString(byteCount: 18),
        codeVerifier: String = randomURLSafeString(byteCount: 32)
    ) throws -> PluginOAuthAuthorizationRequest {
        guard auth.type == .oauth2, let config = auth.oauth2 else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard config.grantType == .authorizationCode,
              let authorizationURL = config.authorizationURL,
              let redirectURI = config.redirectURI else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard let clientID = resolvedClientID(auth: auth, override: clientIDOverride) else {
            throw PluginOAuthError.missingApplicationID(pluginID)
        }
        try validateConfiguredRedirectURI(redirectURI, provider: auth.provider, pluginID: pluginID)
        guard var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false) else {
            throw PluginOAuthError.invalidAuthorizationURL(authorizationURL.absoluteString)
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "response_type", value: "code"))
        queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectURI))
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
            throw PluginOAuthError.invalidAuthorizationURL(authorizationURL.absoluteString)
        }
        return PluginOAuthAuthorizationRequest(url: url, codeVerifier: codeVerifier, state: state, clientID: clientID)
    }

    public static func deviceAuthorizationRequest(
        pluginID: String,
        auth: PackagedPluginAuth,
        clientIDOverride: String? = nil,
        transport: PluginRequestHTTPTransport = URLSessionPluginRequestTransport(),
        now: Date = Date()
    ) async throws -> PluginOAuthDeviceAuthorizationRequest {
        guard auth.type == .oauth2, let config = auth.oauth2, config.grantType == .deviceCode else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard let clientID = resolvedClientID(auth: auth, override: clientIDOverride) else {
            throw PluginOAuthError.missingApplicationID(pluginID)
        }
        guard let deviceAuthorizationURL = config.deviceAuthorizationURL else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        var fields = [
            "client_id": clientID
        ]
        if config.scopes.isEmpty == false {
            fields["scope"] = config.scopes.joined(separator: " ")
        }
        let response = try await transport.response(
            for: PluginHTTPRequest(
                method: "POST",
                url: deviceAuthorizationURL,
                headers: [
                    "Accept": "application/json",
                    "Content-Type": "application/x-www-form-urlencoded"
                ],
                body: Data(formURLEncoded(fields).utf8),
                timeoutSeconds: 30
            )
        )
        guard (200..<300).contains(response.statusCode) else {
            throw PluginOAuthError.tokenExchangeFailed(statusCode: response.statusCode)
        }
        let deviceResponse = try JSONDecoder().decode(PluginOAuthDeviceAuthorizationResponse.self, from: response.data)
        guard let verificationURL = URL(string: deviceResponse.verificationURI) else {
            throw PluginOAuthError.invalidAuthorizationURL(deviceResponse.verificationURI)
        }
        return PluginOAuthDeviceAuthorizationRequest(
            verificationURL: verificationURL,
            userCode: deviceResponse.userCode,
            deviceCode: deviceResponse.deviceCode,
            expiresAt: now.addingTimeInterval(deviceResponse.expiresIn),
            interval: deviceResponse.interval ?? 5,
            clientID: clientID
        )
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
        guard config.grantType == .authorizationCode,
              let redirectURI = config.redirectURI else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard let clientID = resolvedClientID(auth: auth, override: request.clientID) else {
            throw PluginOAuthError.missingApplicationID(pluginID)
        }
        try validateConfiguredRedirectURI(redirectURI, provider: auth.provider, pluginID: pluginID)
        try validateCallbackRedirect(callbackURL, redirectURI: redirectURI)
        let callback = try callbackParameters(callbackURL, expectedState: request.state)
        let body = formURLEncoded([
            "grant_type": "authorization_code",
            "code": callback.code,
            "redirect_uri": redirectURI,
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
        var tokenSet = try tokenSet(from: response.data, now: now)
        tokenSet.clientID = clientID
        return tokenSet
    }

    public static func deviceTokenSet(
        pluginID: String,
        auth: PackagedPluginAuth,
        request: PluginOAuthDeviceAuthorizationRequest,
        transport: PluginRequestHTTPTransport = URLSessionPluginRequestTransport(),
        now: Date = Date()
    ) async throws -> PluginOAuthTokenSet {
        guard auth.type == .oauth2, let config = auth.oauth2, config.grantType == .deviceCode else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard now < request.expiresAt else {
            throw PluginOAuthError.authorizationExpired
        }
        guard let clientID = resolvedClientID(auth: auth, override: request.clientID) else {
            throw PluginOAuthError.missingApplicationID(pluginID)
        }
        let body = formURLEncoded([
            "client_id": clientID,
            "device_code": request.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
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
        if let error = try? JSONDecoder().decode(PluginOAuthDeviceTokenErrorResponse.self, from: response.data) {
            switch error.error {
            case "authorization_pending", "slow_down":
                throw PluginOAuthError.authorizationPending
            case "expired_token":
                throw PluginOAuthError.authorizationExpired
            default:
                throw PluginOAuthError.authorizationDenied(error.errorDescription ?? error.error)
            }
        }
        var tokenSet = try tokenSet(from: response.data, now: now)
        tokenSet.clientID = clientID
        return tokenSet
    }

    public static func resolvedClientID(auth: PackagedPluginAuth, override: String? = nil) -> String? {
        override?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ??
            auth.applicationId?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
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

    private static func validateConfiguredRedirectURI(_ redirectURI: String, provider: String?, pluginID: String) throws {
        guard let provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            throw PluginOAuthError.missingOAuthConfiguration(pluginID)
        }
        guard isAppOwnedRedirectURI(redirectURI, provider: provider) else {
            throw PluginOAuthError.invalidRedirectURI(redirectURI)
        }
    }

    public static func isAppOwnedRedirectURI(_ redirectURI: String, provider: String) -> Bool {
        guard let components = URLComponents(string: redirectURI),
              components.query == nil,
              components.fragment == nil else {
            return false
        }

        if components.scheme == callbackScheme,
           components.host == nil,
           components.path == "/\(provider)" {
            return true
        }

        return components.scheme == "status" &&
            components.host == "oauth" &&
            components.path == "/\(provider)"
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
