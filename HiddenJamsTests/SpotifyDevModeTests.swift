//
//  SpotifyDevModeTests.swift
//  HiddenJamsTests
//
//  Spotify Development Mode hardening: Track objects without `popularity`
//  must decode (unknown, never "ultra-rare"), a non-allowlisted user's 403
//  must flip SpotifyAccessMonitor so the app routes to Apple Music, endpoint
//  gating (batch /artists 403) must not, and 429 waits are capped.
//  All network calls are stubbed; nothing reaches Spotify.
//

import Testing
import Foundation
@testable import HiddenJams

// MARK: - Fixtures

private enum DevModeJSON {
    /// A Track object as a Development Mode app receives it: no
    /// `popularity`, `available_markets` or `linked_from`.
    static let track = """
    {
      "id": "4uLU6hMCjMI75M1A2tKUQC",
      "name": "Deep Cut",
      "uri": "spotify:track:4uLU6hMCjMI75M1A2tKUQC",
      "duration_ms": 201000,
      "preview_url": null,
      "external_ids": { "isrc": "USABC2600001" },
      "artists": [ { "id": "0OdUWJ0sBjDrqHygGUXeCF", "name": "Small Band" } ],
      "album": { "id": "1A2GTWGtFfWp7KSQTwWOyo", "name": "First EP", "images": [], "release_date": "2026-03-01" }
    }
    """

    static let likedTracksPage = """
    { "items": [ { "added_at": "2026-11-01T12:00:00Z", "track": \(track) } ],
      "total": 1, "limit": 50, "offset": 0, "next": null, "previous": null }
    """

    static let searchPage = """
    { "tracks": { "items": [ \(track) ], "total": 1 } }
    """

    static let notRegistered = """
    { "error": { "status": 403, "message": "Check settings on developer.spotify.com/dashboard, the user may not be registered." } }
    """

    static let forbidden = """
    { "error": { "status": 403, "message": "Forbidden" } }
    """
}

/// Stubs every request made through a session that registers it.
/// URLSession calls it on its own threads, so state is lock-protected and
/// the handler is @Sendable (nonisolated).
final class SpotifyStubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }
    typealias Handler = @Sendable (URLRequest) -> Reply

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _requestCount = 0

    static func stub(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _requestCount = 0
    }

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _requestCount
    }

    private static func next(for request: URLRequest) -> Reply {
        lock.lock()
        _requestCount += 1
        let current = _handler
        lock.unlock()
        return current?(request) ?? Reply(status: 500, body: "{}")
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.next(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// Swift Testing, not XCTest: XCTest waits for async tests by spinning the
// main run loop, which ran the host app's .task jobs re-entrantly and hit
// the known simulator host malloc abort (0x262543f40). Serialized because
// the URLProtocol stub is shared.
@Suite(.serialized)
@MainActor
struct SpotifyDevModeTests {

    // MARK: - Optional popularity

    @Test func testDevModeTrackWithoutPopularityDecodes() throws {
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: Data(DevModeJSON.track.utf8))
        #expect(track.name == "Deep Cut")
        #expect(track.popularity == nil, "Dev Mode omits popularity: it must decode as unknown")
        #expect(track.popularityOrNeutral == SpotifyTrack.neutralPopularity)
        #expect(track.isrc == "USABC2600001")
    }

    @Test func testDevModeLikedTracksPageDecodes() throws {
        let page = try JSONDecoder().decode(PagingObject<SavedTrack>.self, from: Data(DevModeJSON.likedTracksPage.utf8))
        #expect(page.items.count == 1)
        #expect(page.items[0].track.popularity == nil)
    }

    @Test func testUnknownPopularityIsNeverScoredAsRare() throws {
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: Data(DevModeJSON.track.utf8))
        // Neutral, not 0 ("ultra-rare").
        #expect(track.popularityOrNeutral >= 50)
        // Profile obscurity: unknown tracks don't count as obscure.
        #expect(TasteProfileGenerator.calculateObscurityScore(from: [track, track]) == 0)
        // Deck slider: unknown popularity adds no relaxation either way.
        #expect(GenreDeckBuilder.relaxationLevel(popularity: nil, followers: nil,
                                                        popularityCeiling: 15, followerCeiling: 2_000) == 0)
        #expect(GenreDeckBuilder.relaxationLevel(popularity: 45, followers: nil,
                                                        popularityCeiling: 15, followerCeiling: 2_000) == 3)
    }

    @Test func testTrackWithPopularityStillDecodes() throws {
        let json = DevModeJSON.track.replacingOccurrences(of: "\"name\": \"Deep Cut\",",
                                                          with: "\"name\": \"Deep Cut\", \"popularity\": 12,")
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: Data(json.utf8))
        #expect(track.popularity == 12)
        #expect(track.popularityOrNeutral == 12)
    }

    // MARK: - 403 classification

    @Test func testUserScoped403IsAccessDenied() {
        let me = URL(string: "https://api.spotify.com/v1/me/tracks?limit=50&offset=0")!
        let search = URL(string: "https://api.spotify.com/v1/search?q=x&type=track")!
        #expect(SpotifyAccessGate.isUserAccessDenied(status: 403, url: me))
        #expect(SpotifyAccessGate.isUserAccessDenied(status: 403, url: search))
        #expect(SpotifyAccessGate.isUserAccessDenied(
            status: 403, url: URL(string: "https://api.spotify.com/v1/me")!))
        #expect(!(SpotifyAccessGate.isUserAccessDenied(status: 200, url: me)))
        #expect(!(SpotifyAccessGate.isUserAccessDenied(status: 401, url: me)))
    }

    @Test func testEndpointGating403IsNotAccessDenied() {
        // Batch lookups and deprecated endpoints 403 for every Dev-Mode user.
        let batch = URL(string: "https://api.spotify.com/v1/artists?ids=a,b")!
        let related = URL(string: "https://api.spotify.com/v1/artists/a/related-artists")!
        let recs = URL(string: "https://api.spotify.com/v1/recommendations?seed_genres=rock")!
        #expect(!(SpotifyAccessGate.isUserAccessDenied(status: 403, url: batch, body: Data(DevModeJSON.forbidden.utf8))))
        #expect(!(SpotifyAccessGate.isUserAccessDenied(status: 403, url: related)))
        #expect(!(SpotifyAccessGate.isUserAccessDenied(status: 403, url: recs)))
        // ...unless Spotify says outright that the user isn't registered.
        #expect(SpotifyAccessGate.isUserAccessDenied(status: 403, url: batch, body: Data(DevModeJSON.notRegistered.utf8)))
    }

    // MARK: - 429 cap

    @Test func testRateLimitWaitIsCapped() {
        #expect(SpotifyAccessGate.rateLimitWait(retryAfterHeader: nil, attempt: 0) == 2)
        #expect(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "3", attempt: 0) == 4)
        #expect(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "20", attempt: 1) == SpotifyAccessGate.maxRateLimitWait)
        #expect(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "3600", attempt: 0) == nil, "long Retry-After fails fast")
        #expect(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "1", attempt: 3) == nil, "max 3 retries")
        #expect(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "garbage", attempt: 0) == 2)
    }

    @Test func testAPIServiceFailsFastOnLongRetryAfter() async {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 429, body: "{}", headers: ["Retry-After": "3600"]) }
        let started = Date()
        do {
            _ = try await api.getCurrentUser(token: "t")
            Issue.record("expected 429")
        } catch APIError.httpError(let status) {
            #expect(status == 429)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(Date().timeIntervalSince(started) < 3, "must not sleep for Retry-After: 3600")
        #expect(SpotifyStubURLProtocol.requestCount == 1)
        #expect(!monitor.isLimitedNow)
    }

    // MARK: - SpotifyAPIService (stubbed)

    @Test func testNotAllowlistedUser403FlipsMonitor() async {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 403, body: DevModeJSON.notRegistered) }
        do {
            _ = try await api.getAllLikedTracks(token: "t") { _, _ in }
            Issue.record("expected 403")
        } catch APIError.httpError(let status) {
            #expect(status == 403)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(monitor.isLimitedNow)
    }

    @Test func testBatchArtists403DoesNotFlipMonitor() async {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 403, body: DevModeJSON.forbidden) }
        let url = URL(string: "https://api.spotify.com/v1/artists?ids=a,b")!
        do {
            let _: [String: [SpotifyArtist]] = try await api.makeRequest(url: url, token: "t")
            Issue.record("expected 403")
        } catch {}
        #expect(!monitor.isLimitedNow, "endpoint gating is not a user-access problem")
    }

    @Test func testDevModeLikedTracksLoadThroughAPIService() async throws {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 200, body: DevModeJSON.likedTracksPage) }
        let tracks = try await api.getAllLikedTracks(token: "t") { _, _ in }
        #expect(tracks.count == 1, "liked tracks must not come back empty in Dev Mode")
        #expect(tracks.first?.popularity == nil)
        #expect(!monitor.isLimitedNow)
    }

    // MARK: - Deck catalog (stubbed)

    @Test func testDeckCatalogDecodesDevModeSearch() async {
        SpotifyStubURLProtocol.stub { _ in .init(status: 200, body: DevModeJSON.searchPage) }
        let catalog = SpotifyGenreDeckCatalog(token: "t", session: SpotifyStubURLProtocol.session())
        let page = await catalog.searchTracks(query: "genre:\"indie\"", offset: 0)
        #expect(page?.tracks.count == 1, "the Spotify deck must not be empty in Dev Mode")
        #expect(catalog.usablePages == 1)
        #expect(catalog.undecodablePages == 0)
        #expect(!catalog.accessDenied)
    }

    @Test func testDeckCatalogFlagsNotAllowlisted403AndStopsSearching() async {
        SpotifyStubURLProtocol.stub { _ in .init(status: 403, body: DevModeJSON.notRegistered) }
        let catalog = SpotifyGenreDeckCatalog(token: "t", session: SpotifyStubURLProtocol.session())
        let first = await catalog.searchTracks(query: "genre:\"indie\"", offset: 0)
        let second = await catalog.searchTracks(query: "genre:\"rock\"", offset: 0)
        #expect(first == nil)
        #expect(second == nil)
        #expect(catalog.accessDenied)
        #expect(SpotifyStubURLProtocol.requestCount == 1, "no more searches once Spotify said 403")
    }

    @Test func testDeckCatalogCountsUndecodablePages() async {
        // A page whose items can't decode (simulates the old required-field break).
        let broken = """
        { "tracks": { "items": [ { "id": "x", "name": "No album or uri" } ], "total": 1 } }
        """
        SpotifyStubURLProtocol.stub { _ in .init(status: 200, body: broken) }
        let catalog = SpotifyGenreDeckCatalog(token: "t", session: SpotifyStubURLProtocol.session())
        let page = await catalog.searchTracks(query: "genre:\"indie\"", offset: 0)
        #expect((page?.tracks.count ?? 0) == 0)
        #expect(catalog.undecodablePages == 1)
        #expect(catalog.usablePages == 0)
    }

    // MARK: - Monitor

    @Test func testRepeatedEmptyOrUndecodableResultsFlipMonitor() {
        let empty = SpotifyAccessMonitor()
        empty.recordEmptyResult()
        #expect(!empty.isLimitedNow, "one empty deck isn't enough")
        empty.recordEmptyResult()
        #expect(empty.isLimitedNow)

        let decode = SpotifyAccessMonitor()
        decode.recordDecodeFailure()
        #expect(!decode.isLimitedNow)
        decode.recordDecodeFailure()
        #expect(decode.isLimitedNow)

        let recovering = SpotifyAccessMonitor()
        recovering.recordEmptyResult()
        recovering.recordSuccess()
        recovering.recordEmptyResult()
        #expect(!recovering.isLimitedNow, "a good deck resets the streak")

        decode.reset()
        #expect(!decode.isLimitedNow, "a fresh Spotify sign-in tries Spotify again")
    }

    @Test func testEarlyAccessCopy() {
        #expect(SpotifyAccessGate.limitedMessage.contains("early access"))
        #expect(SpotifyAccessGate.limitedMessage.contains("Apple Music"))
        #expect(SpotifyAccessGate.continueButtonTitle == "Continue with Apple Music")
    }
}
