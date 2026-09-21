//
//  SpotifyAuthManager.swift
//  SpotifyHiddenGems
//
//  Handles Spotify OAuth 2.0 PKCE flow and token management
//

import Foundation
import Combine
import CryptoKit
#if os(iOS)
import UIKit
#endif

class SpotifyAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var user: SpotifyUser?
    
    // Spotify OAuth credentials.
    //
    // This client ID is a *public* identifier: the PKCE flow is designed for clients
    // that cannot keep a secret, so there is no client secret here and none should be
    // added. Everything else (tokens, verifier) is generated per-session at runtime.
    private let clientId = "d5baa23332d64e198419d95d2272be2e"
    private let redirectUri = "spotifyhiddengems://callback"
    
    private let tokenKey = "spotify_access_token"
    private let refreshTokenKey = "spotify_refresh_token"
    private let tokenExpiryKey = "spotify_token_expiry"
    
    private var codeVerifier: String?
    
    init() {
        loadSavedToken()
    }
    
    // MARK: - OAuth PKCE Flow
    
    func startAuth() {
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        
        guard let challenge = generateCodeChallenge(from: verifier) else {
            print("Failed to generate code challenge")
            return
        }
        
        let scope = "user-read-private user-read-email user-library-read playlist-read-private user-top-read user-read-recently-played user-library-modify playlist-modify-public playlist-modify-private"
        
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scope)
        ]
        
        if let url = components.url {
            DispatchQueue.main.async {
                #if os(iOS)
                UIApplication.shared.open(url)
                #else
                NSWorkspace.shared.open(url)
                #endif
            }
        }
    }
    
    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            print("Invalid callback or missing code verifier")
            return
        }
        
        exchangeCodeForToken(code: code, codeVerifier: verifier)
    }
    
    private func exchangeCodeForToken(code: String, codeVerifier: String) {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "client_id": clientId,
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                print("Token exchange failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            DispatchQueue.main.async {
                self?.accessToken = json.accessToken
                self?.saveToken(json.accessToken, refreshToken: json.refreshToken, expiresIn: json.expiresIn)
                self?.isAuthenticated = true
            }
        }.resume()
    }
    
    // MARK: - Token Management
    
    private func saveToken(_ token: String, refreshToken: String?, expiresIn: Int) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        if let refreshToken = refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        }
        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        UserDefaults.standard.set(expiryDate, forKey: tokenExpiryKey)
    }
    
    private func loadSavedToken() {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              let expiryDate = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date,
              expiryDate > Date() else {
            return
        }
        
        self.accessToken = token
        self.isAuthenticated = true
        
        // Load cached user profile
        if let cachedUser = UserDataManager.shared.loadUserProfile() {
            self.user = cachedUser
            print("✅ Loaded cached user: \(cachedUser.displayName ?? "Unknown")")
        }
        
        // Check for expiration and refresh if needed
        if isTokenExpired {
            print("⚠️ Token expired, refreshing...")
            refreshAccessToken()
        }
    }
    
    var isTokenExpired: Bool {
        guard let expiryDate = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date else {
            return true
        }
        // Buffer of 5 minutes
        return Date().addingTimeInterval(300) > expiryDate
    }
    
    func refreshAccessToken(completion: ((Bool) -> Void)? = nil) {
        guard let refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey) else {
            print("❌ No refresh token available")
            completion?(false)
            return
        }
        
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Basic Auth header not needed for PKCE? Actually for refresh token flow with PKCE, 
        // we send client_id in body if not using client secret.
        // For public clients (PKCE), we send client_id but NO client_secret
        
        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        print("🔄 Refreshing access token...")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                print("❌ Token refresh failed: \(error?.localizedDescription ?? "Unknown error")")
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    print("Response: \(str)")
                }
                
                // If refresh fails (e.g. revoked), logout
                if let httpResponse = response as? HTTPURLResponse, (400...499).contains(httpResponse.statusCode) {
                    self?.logout()
                }
                
                completion?(false)
                return
            }
            
            DispatchQueue.main.async {
                print("✅ Token refreshed successfully!")
                self?.accessToken = json.accessToken
                // If new refresh token is provided, save it (sometimes it rotates)
                self?.saveToken(json.accessToken, refreshToken: json.refreshToken ?? refreshToken, expiresIn: json.expiresIn)
                self?.isAuthenticated = true
                completion?(true)
            }
        }.resume()
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
        
        // Clear all cached user data (profile, library, analysis)
        UserDataManager.shared.clearAllData()
        
        DispatchQueue.main.async {
            self.accessToken = nil
            self.isAuthenticated = false
            self.user = nil
        }
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func generateCodeChallenge(from verifier: String) -> String? {
        guard let data = verifier.data(using: .utf8) else { return nil }
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Token Response
private struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}
