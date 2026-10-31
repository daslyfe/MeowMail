import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum Keychain {
    private static let service = "dev.jaderowland.meowmail.refresh-token"

    static func save(_ token: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AuthError: LocalizedError {
    case badClientID
    case stateMismatch
    case noRefreshToken
    case reconnectRequired(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badClientID: return "That doesn't look like an iOS OAuth client ID."
        case .stateMismatch: return "Google's sign-in response didn't match this request."
        case .noRefreshToken: return "Google didn't return a long-lived sign-in. Remove meowmail from your Google account's third-party access and try again."
        case .reconnectRequired(let email): return "\(email) needs to be reconnected."
        case .server(let message): return message
        }
    }
}

private struct TokenResponse: Decodable {
    var access_token: String?
    var refresh_token: String?
    var expires_in: Double?
    var error: String?
    var error_description: String?
}

/// Runs Google's OAuth flow for installed apps (authorization code with PKCE)
/// and hands out access tokens, refreshing them when they expire.
actor TokenProvider {
    static let scope = "https://www.googleapis.com/auth/gmail.modify"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    private var cache: [String: (token: String, expires: Date)] = [:]

    func store(accessToken: String, expiresIn: Double, account: String) {
        cache[account] = (accessToken, Date().addingTimeInterval(expiresIn - 60))
    }

    func accessToken(account: String, clientID: String) async throws -> String {
        if let cached = cache[account], cached.expires > Date() { return cached.token }
        guard let refresh = Keychain.load(account: account) else {
            throw AuthError.reconnectRequired(account)
        }
        let response = try await Self.exchange(["client_id": clientID,
                                                "refresh_token": refresh,
                                                "grant_type": "refresh_token"])
        if response.error == "invalid_grant" { throw AuthError.reconnectRequired(account) }
        guard let token = response.access_token else {
            throw AuthError.server(response.error_description ?? response.error ?? "Couldn't refresh sign-in.")
        }
        store(accessToken: token, expiresIn: response.expires_in ?? 3600, account: account)
        return token
    }

    func forget(account: String) { cache[account] = nil }

    static func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws -> (access: String, refresh: String, expiresIn: Double) {
        let response = try await exchange(["client_id": clientID,
                                           "code": code,
                                           "code_verifier": verifier,
                                           "grant_type": "authorization_code",
                                           "redirect_uri": redirectURI])
        guard let access = response.access_token else {
            throw AuthError.server(response.error_description ?? response.error ?? "Sign-in failed.")
        }
        guard let refresh = response.refresh_token else { throw AuthError.noRefreshToken }
        return (access, refresh, response.expires_in ?? 3600)
    }

    private static func exchange(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Result {
        var access: String
        var refresh: String
        var expiresIn: Double
    }

    private var session: ASWebAuthenticationSession?

    static func redirectScheme(for clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix), clientID.count > suffix.count else { return nil }
        return "com.googleusercontent.apps." + clientID.dropLast(suffix.count)
    }

    func signIn(clientID: String) async throws -> Result {
        guard let scheme = Self.redirectScheme(for: clientID) else { throw AuthError.badClientID }
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomToken()
        let state = Self.randomToken()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: TokenProvider.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "select_account consent"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? AuthError.server("Sign-in was cancelled."))
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.server(items.first { $0.name == "error" }?.value ?? "Sign-in failed.")
        }
        let tokens = try await TokenProvider.exchangeCode(code, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
        return Result(access: tokens.access, refresh: tokens.refresh, expiresIn: tokens.expiresIn)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(macOS)
            NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #else
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
            #endif
        }
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
