import Foundation
import AuthenticationServices
import Combine
import UIKit

/// Strava OAuth (Authorization Code flow) via `ASWebAuthenticationSession` —
/// Strava's API is genuinely self-serve for individuals: create a free app at
/// https://www.strava.com/settings/api (instant, no partner approval, unlike
/// TrainingPeaks). The rider pastes their own Client ID/Secret into Settings
/// once; nothing Strava-related ships baked into the app or its source.
///
/// Client id/secret and tokens all live in the Keychain, never UserDefaults
/// or source control.
@MainActor
final class StravaAuth: NSObject, ObservableObject {
    private static let authorizeURL = "https://www.strava.com/oauth/mobile/authorize"
    private static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    private static let scope = "activity:write"
    /// Must match the "Authorization Callback Domain" set on the Strava API
    /// app page (just the scheme name, no "://").
    static let callbackScheme = "smarttrainer"
    private static let redirectUri = "\(callbackScheme)://strava-auth"

    @Published var clientId: String {
        didSet { KeychainStore.set(clientId.isEmpty ? nil : clientId, forKey: "clientId") }
    }
    @Published var clientSecret: String {
        didSet { KeychainStore.set(clientSecret.isEmpty ? nil : clientSecret, forKey: "clientSecret") }
    }
    @Published private(set) var connected: Bool = false
    @Published private(set) var athleteName: String?
    @Published var isBusy = false
    @Published var errorMessage: String?

    private var accessToken: String?
    private var refreshToken: String? {
        didSet { KeychainStore.set(refreshToken, forKey: "refreshToken") }
    }
    private var expiresAt: Int = 0
    private var session: ASWebAuthenticationSession?

    var isConfigured: Bool { !clientId.isEmpty && !clientSecret.isEmpty }

    override init() {
        clientId = KeychainStore.get("clientId") ?? ""
        clientSecret = KeychainStore.get("clientSecret") ?? ""
        refreshToken = KeychainStore.get("refreshToken")
        athleteName = KeychainStore.get("athleteName")
        super.init()
        connected = refreshToken != nil
    }

    func connect() {
        errorMessage = nil
        guard isConfigured else {
            errorMessage = "Add your Strava Client ID and Client Secret first."
            return
        }
        var comps = URLComponents(string: Self.authorizeURL)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: Self.scope),
        ]
        guard let url = comps.url else { return }

        isBusy = true
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.handleCallback(callbackURL, error: error)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        athleteName = nil
        KeychainStore.remove("athleteName")
        connected = false
    }

    /// Returns a valid access token, transparently refreshing it if needed.
    func validAccessToken() async throws -> String {
        guard let refreshToken else { throw StravaError.notConnected }
        let nowSec = Int(Date().timeIntervalSince1970)
        if let accessToken, expiresAt - nowSec > 60 {
            return accessToken
        }
        let tokens = try await requestToken(body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        apply(tokens)
        return tokens.accessToken
    }

    private func handleCallback(_ url: URL?, error: Error?) async {
        isBusy = false
        if let error {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                return // user dismissed — not an error worth surfacing
            }
            errorMessage = error.localizedDescription
            return
        }
        guard let url,
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
            errorMessage = "Strava didn't return an authorization code."
            return
        }
        do {
            isBusy = true
            let tokens = try await requestToken(body: [
                "grant_type": "authorization_code",
                "code": code,
            ])
            apply(tokens)
            connected = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_at: Int
        let athlete: Athlete?
        struct Athlete: Decodable { let firstname: String?; let lastname: String? }
    }
    private struct Tokens { let accessToken: String; let refreshToken: String; let expiresAt: Int; let athleteName: String? }

    private func requestToken(body: [String: String]) async throws -> Tokens {
        guard isConfigured else { throw StravaError.notConfigured }
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = body
        payload["client_id"] = clientId
        payload["client_secret"] = clientSecret
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StravaError.requestFailed(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let name = [decoded.athlete?.firstname, decoded.athlete?.lastname]
            .compactMap { $0 }.joined(separator: " ")
        return Tokens(accessToken: decoded.access_token, refreshToken: decoded.refresh_token,
                      expiresAt: decoded.expires_at, athleteName: name.isEmpty ? nil : name)
    }

    private func apply(_ tokens: Tokens) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        expiresAt = tokens.expiresAt
        if let name = tokens.athleteName {
            athleteName = name
            KeychainStore.set(name, forKey: "athleteName")
        }
    }
}

enum StravaError: LocalizedError {
    case notConfigured
    case notConnected
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Strava isn't configured yet — add your Client ID and Secret in Settings."
        case .notConnected: return "Strava isn't connected yet."
        case .requestFailed(let text): return "Strava request failed: \(text)"
        }
    }
}

extension StravaAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
