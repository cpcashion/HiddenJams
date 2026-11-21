//
//  SpotifyAccessGate.swift
//  HiddenJams
//
//  Spotify Development Mode guard. While the Hidden Jams Spotify app is in
//  Development Mode, only allowlisted users (5 max, Premium) get Web API
//  access; everyone else gets HTTP 403 ("the user may not be registered")
//  right after a successful OAuth sign-in. Some fields and batch endpoints
//  are also gated. This detects that state at runtime so the app can say so
//  plainly and route the user to Apple Music / the non-Spotify discovery
//  engine, instead of an empty deck, a "check your connection" error, or an
//  "Analyze your library" prompt that can never succeed.
//
//  The Spotify sign-in option itself stays visible and unchanged.
//

import Foundation
import Combine

enum SpotifyAccessGate {
    static let limitedTitle = "Spotify is in early access"
    static let limitedMessage = "Spotify access is limited while Hidden Jams is in early access — continue with Apple Music."
    static let continueButtonTitle = "Continue with Apple Music"

    /// Paths whose 403 means *this user* can't use the Web API (not on the
    /// Development Mode allowlist). 403s from batch lookups (`/artists?ids=`,
    /// `/tracks?ids=`) and deprecated endpoints (recommendations,
    /// related-artists, audio-features, top-tracks) are endpoint gating that
    /// every Dev-Mode user sees, so they must not trip the gate.
    static func isUserScopedPath(_ path: String) -> Bool {
        path == "/v1/me" || path.hasPrefix("/v1/me/") || path == "/v1/search"
    }

    /// Track-bearing feeds; a decode failure here means every track in the
    /// payload was lost (e.g. a field Development Mode removed).
    static func isTrackFeedPath(_ path: String) -> Bool {
        path == "/v1/search" || path == "/v1/me/tracks" || path.hasPrefix("/v1/me/top/")
    }

    /// True when a Spotify Web API response means the signed-in user has no
    /// API access while the app is in Development Mode.
    static func isUserAccessDenied(status: Int, url: URL?, body: Data? = nil) -> Bool {
        guard status == 403 else { return false }
        if let body, let text = String(data: body, encoding: .utf8)?.lowercased(),
           text.contains("not be registered") || text.contains("not registered") {
            return true
        }
        guard let path = url?.path else { return false }
        return isUserScopedPath(path)
    }

    /// Seconds to wait before retrying a 429, or nil to give up now. The
    /// wait is capped so a long Retry-After can't stall analysis for minutes
    /// (it used to sleep Retry-After + 1 seconds, uncapped, up to 3 times).
    static let maxRateLimitWait = 5
    static func rateLimitWait(retryAfterHeader: String?, attempt: Int, maxRetries: Int = 3) -> Int? {
        guard attempt < maxRetries else { return nil }
        let retryAfter = max(0, Int(retryAfterHeader?.trimmingCharacters(in: .whitespaces) ?? "") ?? 1)
        // A Retry-After far beyond the cap won't clear by retrying soon:
        // fail fast and let the caller degrade.
        guard retryAfter <= maxRateLimitWait * 6 else { return nil }
        return min(retryAfter + 1, maxRateLimitWait)
    }
}

/// Session-wide record of whether Spotify access is limited for this user.
/// In memory only, so a user who is later allowlisted gets Spotify back on
/// the next launch (and signing in to Spotify again resets it).
final class SpotifyAccessMonitor: ObservableObject {
    static let shared = SpotifyAccessMonitor()

    /// Empty Spotify decks in a row (with Spotify answering, but nothing
    /// usable) before we treat access as limited.
    static let emptyResultsBeforeLimited = 2
    /// Spotify payloads that failed to decode before we treat it as limited.
    static let decodeFailuresBeforeLimited = 2

    @Published private(set) var isLimited = false

    private let lock = NSLock()
    private var limited = false
    private var consecutiveEmpty = 0
    private var decodeFailures = 0

    init() {}

    /// Thread-safe read (the @Published copy is updated on the main queue).
    var isLimitedNow: Bool {
        lock.lock(); defer { lock.unlock() }
        return limited
    }

    /// A user-scoped Spotify call returned 403: not on the allowlist.
    func recordAccessDenied() {
        setLimited()
    }

    /// A Spotify response couldn't be decoded (e.g. a field Dev Mode removed).
    func recordDecodeFailure(count: Int = 1) {
        lock.lock()
        decodeFailures += max(1, count)
        let trip = decodeFailures >= Self.decodeFailuresBeforeLimited
        lock.unlock()
        if trip { setLimited() }
    }

    /// Spotify answered but produced no usable tracks.
    func recordEmptyResult() {
        lock.lock()
        consecutiveEmpty += 1
        let trip = consecutiveEmpty >= Self.emptyResultsBeforeLimited
        lock.unlock()
        if trip { setLimited() }
    }

    /// Spotify returned usable tracks.
    func recordSuccess() {
        lock.lock()
        consecutiveEmpty = 0
        decodeFailures = 0
        lock.unlock()
    }

    /// Fresh Spotify sign-in: try Spotify again.
    func reset() {
        lock.lock()
        limited = false
        consecutiveEmpty = 0
        decodeFailures = 0
        lock.unlock()
        publish(false)
    }

    private func setLimited() {
        lock.lock()
        let changed = !limited
        limited = true
        lock.unlock()
        if changed {
            print("🔒 Spotify access is limited (Development Mode) — routing to Apple Music / non-Spotify discovery")
        }
        publish(true)
    }

    private func publish(_ value: Bool) {
        if Thread.isMainThread {
            isLimited = value
        } else {
            DispatchQueue.main.async { [weak self] in self?.isLimited = value }
        }
    }
}
