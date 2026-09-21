//
//  APIConfiguration.swift
//  HiddenJams
//
//  Centralized API configuration for external services
//

import Foundation

struct APIConfiguration {

    // MARK: - Secret Loading
    //
    // Secrets are never hardcoded in source. They are resolved at runtime, in order:
    //
    //   1. `Secrets.plist` in the app bundle  (git-ignored; see Secrets.example.plist)
    //   2. The app's Info.plist               (useful for CI / xcconfig-driven builds)
    //   3. An environment variable            (useful for local development in Xcode)
    //
    // If none of these supply a value, the key is empty and the calling service
    // reports a clear "missing API key" error instead of a confusing HTTP 401.
    //
    // See SETUP.md for how to provide each key.

    private static let secretsPlist: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else {
            return [:]
        }
        return plist
    }()

    /// Resolves a secret by key, trying Secrets.plist, then Info.plist, then the environment.
    /// Returns an empty string when the secret has not been configured.
    static func secret(_ key: String, environmentVariable: String) -> String {
        if let value = secretsPlist[key] as? String, !value.isEmpty {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment[environmentVariable], !value.isEmpty {
            return value
        }
        return ""
    }

    // MARK: - Last.fm Configuration
    // Get your API key at: https://www.last.fm/api/account/create
    static var lastFmAPIKey: String {
        secret("LastFmAPIKey", environmentVariable: "LASTFM_API_KEY")
    }

    // MARK: - OpenAI Configuration
    // Get your API key at: https://platform.openai.com/api-keys
    //
    // ⚠️ Shipping an OpenAI key inside the app binary means anyone who downloads
    // the app can extract it and spend against your account. Before releasing on
    // the App Store, move OpenAI calls behind a server you control and have the
    // app talk to that instead. See SETUP.md.
    static var openAIAPIKey: String {
        secret("OpenAIAPIKey", environmentVariable: "OPENAI_API_KEY")
    }

    // MARK: - MusicBrainz Configuration
    // MusicBrainz doesn't require an API key, but requires a User-Agent
    static let musicBrainzUserAgent = "HiddenJams/1.0 (your-email@example.com)"

    // MARK: - Discovery Parameters
    struct Discovery {
        static let popularityThreshold = 30       // Tracks with popularity < 30
        static let followerThreshold = 10_000     // Artists with < 10k followers
        static let recencyMonths = 3              // Releases within last 3 months
        static let maxRecommendations = 50        // Number of recommendations to return
    }

    // MARK: - Rate Limiting
    struct RateLimits {
        static let lastFmMinInterval: TimeInterval = 0.2      // 5 requests/sec
        static let musicBrainzMinInterval: TimeInterval = 1.0 // 1 request/sec
        static let spotifyMinInterval: TimeInterval = 0.1     // 10 requests/sec
    }
}
