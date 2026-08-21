import Foundation
import AuthenticationServices
import Combine
import UIKit

/// Strava OAuth (Authorization Code flow) via `ASWebAuthenticationSession`.
///
/// The app only ever holds a **Client ID**, which is not secret — Strava's
/// own docs treat it as public (it's visible in every authorize URL). The
/// **Client Secret** never ships in the app at all: token exchange goes
/// through a small proxy server (see `strava-proxy/`) that holds the secret
/// server-side. That's what keeps the App Store binary free of it — a
/// decompiled `.ipa` reveals only the Client ID and the proxy's URL, neither
/// of which lets anyone impersonate the app or mint tokens.
///
/// The public Client ID and proxy URL come from Info.plist. OAuth refresh
/// tokens live in the Keychain and never in UserDefaults or source control.
@MainActor
final class StravaAuth: NSObject, ObservableObject {
    private static let authorizeURL = "https://www.strava.com/oauth/mobile/authorize"
    private static let scope = "activity:write"
    /// Must match the "Authorization Callback Domain" set on the Strava API
    /// app page (just the scheme name, no "://"). Strava validates that
    /// setting against the *host* component of redirectUri below — for a URI
    /// like "smarttrainer://smarttrainer" that's the part right after "://",
    /// not the scheme — so the host here must equal callbackScheme too.
    static let callbackScheme = "smarttrainer"
    private static let redirectUri = "\(callbackScheme)://\(callbackScheme)"

    private let clientId: String
    /// URL of the deployed token-exchange proxy (see `strava-proxy/README.md`).
    private let proxyURL: URL?
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
    private var pendingState: String?

    private var isConfigured: Bool {
        !clientId.isEmpty && clientId.allSatisfy(\.isNumber) && proxyURL != nil
    }

    override init() {
        clientId = (Bundle.main.object(forInfoDictionaryKey: "StravaClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawProxyURL = (Bundle.main.object(forInfoDictionaryKey: "StravaTokenProxyURL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: rawProxyURL),
           url.scheme == "https", url.host != nil,
           url.user == nil, url.password == nil {
            proxyURL = url
        } else {
            proxyURL = nil
        }
        refreshToken = KeychainStore.get("refreshToken")
        athleteName = KeychainStore.get("athleteName")
        super.init()
        // Remove the deprecated user-entered configuration from older builds.
        KeychainStore.remove("clientId")
        KeychainStore.remove("proxyURL")
        connected = refreshToken != nil
    }

    func connect() {
        errorMessage = nil
        guard isConfigured else {
            errorMessage = "Strava sign-in is temporarily unavailable."
            return
        }
        let state = UUID().uuidString
        pendingState = state
        var comps = URLComponents(string: Self.authorizeURL)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: state),
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
        if !session.start() {
            pendingState = nil
            isBusy = false
            errorMessage = "Couldn't open Strava sign-in. Please try again."
        }
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
        defer {
            pendingState = nil
            session = nil
        }
        if let error {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                return // user dismissed — not an error worth surfacing
            }
            errorMessage = error.localizedDescription
            return
        }
        guard let url else {
            errorMessage = "Strava didn't return an authorization code."
            return
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if queryItems.first(where: { $0.name == "error" })?.value == "access_denied" {
            return
        }
        guard let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
              returnedState == pendingState else {
            errorMessage = "Strava sign-in couldn't be verified. Please try again."
            return
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            errorMessage = "Strava didn't return an authorization code."
            return
        }
        let grantedScopes = Set((queryItems.first(where: { $0.name == "scope" })?.value ?? "")
            .split(separator: ",").map(String.init))
        guard grantedScopes.contains(Self.scope) else {
            errorMessage = "Strava activity upload permission wasn't granted."
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

    /// Posts to the token proxy (never directly to Strava) so the Client
    /// Secret — held only by the proxy — never has to be on this device.
    private func requestToken(body: [String: String]) async throws -> Tokens {
        guard isConfigured, let url = proxyURL else { throw StravaError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var payload = body
        payload["client_id"] = clientId
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw StravaError.requestFailed("HTTP \(status)")
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
        case .notConfigured: return "Strava sign-in is temporarily unavailable."
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
