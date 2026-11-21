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

import XCTest
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

@MainActor
final class SpotifyDevModeTests: XCTestCase {

    // MARK: - Optional popularity

    func testDevModeTrackWithoutPopularityDecodes() throws {
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: Data(DevModeJSON.track.utf8))
        XCTAssertEqual(track.name, "Deep Cut")
        XCTAssertNil(track.popularity, "Dev Mode omits popularity: it must decode as unknown")
        XCTAssertEqual(track.popularityOrNeutral, SpotifyTrack.neutralPopularity)
        XCTAssertEqual(track.isrc, "USABC2600001")
    }

    func testDevModeLikedTracksPageDecodes() throws {
        let page = try JSONDecoder().decode(PagingObject<SavedTrack>.self, from: Data(DevModeJSON.likedTracksPage.utf8))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertNil(page.items[0].track.popularity)
    }

    func testUnknownPopularityIsNeverScoredAsRare() throws {
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: Data(DevModeJSON.track.utf8))
        // Neutral, not 0 ("ultra-rare").
        XCTAssertGreaterThanOrEqual(track.popularityOrNeutral, 50)
        // Profile obscurity: unknown tracks don't count as obscure.
        XCTAssertEqual(TasteProfileGenerator.calculateObscurityScore(from: [track, track]), 0)
        // Deck slider: unknown popularity adds no relaxation either way.
        XCTAssertEqual(GenreDeckBuilder.relaxationLevel(popularity: nil, followers: nil,
                                                        popularityCeiling: 15, followerCeiling: 2_000), 0)
        XCTAssertEqual(GenreDeckBuilder.relaxationLevel(popularity: 45, followers: nil,
                                                        popularityCeiling: 15, followerCeiling: 2_000), 3)
    }

    func testTrackWithPopularityStillDecodes() throws {
        let json = DevModeJSON.track.replacingOccurrences(of: "\"name\": \"Deep Cut\",",
                                                          with: "\"name\": \"Deep Cut\", \"popularity\": 12,")
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: Data(json.utf8))
        XCTAssertEqual(track.popularity, 12)
        XCTAssertEqual(track.popularityOrNeutral, 12)
    }

    // MARK: - 403 classification

    func testUserScoped403IsAccessDenied() {
        let me = URL(string: "https://api.spotify.com/v1/me/tracks?limit=50&offset=0")!
        let search = URL(string: "https://api.spotify.com/v1/search?q=x&type=track")!
        XCTAssertTrue(SpotifyAccessGate.isUserAccessDenied(status: 403, url: me))
        XCTAssertTrue(SpotifyAccessGate.isUserAccessDenied(status: 403, url: search))
        XCTAssertTrue(SpotifyAccessGate.isUserAccessDenied(
            status: 403, url: URL(string: "https://api.spotify.com/v1/me")!))
        XCTAssertFalse(SpotifyAccessGate.isUserAccessDenied(status: 200, url: me))
        XCTAssertFalse(SpotifyAccessGate.isUserAccessDenied(status: 401, url: me))
    }

    func testEndpointGating403IsNotAccessDenied() {
        // Batch lookups and deprecated endpoints 403 for every Dev-Mode user.
        let batch = URL(string: "https://api.spotify.com/v1/artists?ids=a,b")!
        let related = URL(string: "https://api.spotify.com/v1/artists/a/related-artists")!
        let recs = URL(string: "https://api.spotify.com/v1/recommendations?seed_genres=rock")!
        XCTAssertFalse(SpotifyAccessGate.isUserAccessDenied(status: 403, url: batch, body: Data(DevModeJSON.forbidden.utf8)))
        XCTAssertFalse(SpotifyAccessGate.isUserAccessDenied(status: 403, url: related))
        XCTAssertFalse(SpotifyAccessGate.isUserAccessDenied(status: 403, url: recs))
        // ...unless Spotify says outright that the user isn't registered.
        XCTAssertTrue(SpotifyAccessGate.isUserAccessDenied(status: 403, url: batch, body: Data(DevModeJSON.notRegistered.utf8)))
    }

    // MARK: - 429 cap

    func testRateLimitWaitIsCapped() {
        XCTAssertEqual(SpotifyAccessGate.rateLimitWait(retryAfterHeader: nil, attempt: 0), 2)
        XCTAssertEqual(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "3", attempt: 0), 4)
        XCTAssertEqual(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "20", attempt: 1), SpotifyAccessGate.maxRateLimitWait)
        XCTAssertNil(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "3600", attempt: 0), "long Retry-After fails fast")
        XCTAssertNil(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "1", attempt: 3), "max 3 retries")
        XCTAssertEqual(SpotifyAccessGate.rateLimitWait(retryAfterHeader: "garbage", attempt: 0), 2)
    }

    func testAPIServiceFailsFastOnLongRetryAfter() async {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 429, body: "{}", headers: ["Retry-After": "3600"]) }
        let started = Date()
        do {
            _ = try await api.getCurrentUser(token: "t")
            XCTFail("expected 429")
        } catch APIError.httpError(let status) {
            XCTAssertEqual(status, 429)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "must not sleep for Retry-After: 3600")
        XCTAssertEqual(SpotifyStubURLProtocol.requestCount, 1)
        XCTAssertFalse(monitor.isLimitedNow)
    }

    // MARK: - SpotifyAPIService (stubbed)

    func testNotAllowlistedUser403FlipsMonitor() async {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 403, body: DevModeJSON.notRegistered) }
        do {
            _ = try await api.getAllLikedTracks(token: "t") { _, _ in }
            XCTFail("expected 403")
        } catch APIError.httpError(let status) {
            XCTAssertEqual(status, 403)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(monitor.isLimitedNow)
    }

    func testBatchArtists403DoesNotFlipMonitor() async {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 403, body: DevModeJSON.forbidden) }
        let url = URL(string: "https://api.spotify.com/v1/artists?ids=a,b")!
        do {
            let _: [String: [SpotifyArtist]] = try await api.makeRequest(url: url, token: "t")
            XCTFail("expected 403")
        } catch {}
        XCTAssertFalse(monitor.isLimitedNow, "endpoint gating is not a user-access problem")
    }

    func testDevModeLikedTracksLoadThroughAPIService() async throws {
        let monitor = SpotifyAccessMonitor()
        let api = SpotifyAPIService(session: SpotifyStubURLProtocol.session(), accessMonitor: monitor)
        SpotifyStubURLProtocol.stub { _ in .init(status: 200, body: DevModeJSON.likedTracksPage) }
        let tracks = try await api.getAllLikedTracks(token: "t") { _, _ in }
        XCTAssertEqual(tracks.count, 1, "liked tracks must not come back empty in Dev Mode")
        XCTAssertNil(tracks.first?.popularity)
        XCTAssertFalse(monitor.isLimitedNow)
    }

    // MARK: - Deck catalog (stubbed)

    func testDeckCatalogDecodesDevModeSearch() async {
        SpotifyStubURLProtocol.stub { _ in .init(status: 200, body: DevModeJSON.searchPage) }
        let catalog = SpotifyGenreDeckCatalog(token: "t", session: SpotifyStubURLProtocol.session())
        let page = await catalog.searchTracks(query: "genre:\"indie\"", offset: 0)
        XCTAssertEqual(page?.tracks.count, 1, "the Spotify deck must not be empty in Dev Mode")
        XCTAssertEqual(catalog.usablePages, 1)
        XCTAssertEqual(catalog.undecodablePages, 0)
        XCTAssertFalse(catalog.accessDenied)
    }

    func testDeckCatalogFlagsNotAllowlisted403AndStopsSearching() async {
        SpotifyStubURLProtocol.stub { _ in .init(status: 403, body: DevModeJSON.notRegistered) }
        let catalog = SpotifyGenreDeckCatalog(token: "t", session: SpotifyStubURLProtocol.session())
        let first = await catalog.searchTracks(query: "genre:\"indie\"", offset: 0)
        let second = await catalog.searchTracks(query: "genre:\"rock\"", offset: 0)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertTrue(catalog.accessDenied)
        XCTAssertEqual(SpotifyStubURLProtocol.requestCount, 1, "no more searches once Spotify said 403")
    }

    func testDeckCatalogCountsUndecodablePages() async {
        // A page whose items can't decode (simulates the old required-field break).
        let broken = """
        { "tracks": { "items": [ { "id": "x", "name": "No album or uri" } ], "total": 1 } }
        """
        SpotifyStubURLProtocol.stub { _ in .init(status: 200, body: broken) }
        let catalog = SpotifyGenreDeckCatalog(token: "t", session: SpotifyStubURLProtocol.session())
        let page = await catalog.searchTracks(query: "genre:\"indie\"", offset: 0)
        XCTAssertEqual(page?.tracks.count ?? 0, 0)
        XCTAssertEqual(catalog.undecodablePages, 1)
        XCTAssertEqual(catalog.usablePages, 0)
    }

    // MARK: - Monitor

    func testRepeatedEmptyOrUndecodableResultsFlipMonitor() {
        let empty = SpotifyAccessMonitor()
        empty.recordEmptyResult()
        XCTAssertFalse(empty.isLimitedNow, "one empty deck isn't enough")
        empty.recordEmptyResult()
        XCTAssertTrue(empty.isLimitedNow)

        let decode = SpotifyAccessMonitor()
        decode.recordDecodeFailure()
        XCTAssertFalse(decode.isLimitedNow)
        decode.recordDecodeFailure()
        XCTAssertTrue(decode.isLimitedNow)

        let recovering = SpotifyAccessMonitor()
        recovering.recordEmptyResult()
        recovering.recordSuccess()
        recovering.recordEmptyResult()
        XCTAssertFalse(recovering.isLimitedNow, "a good deck resets the streak")

        decode.reset()
        XCTAssertFalse(decode.isLimitedNow, "a fresh Spotify sign-in tries Spotify again")
    }

    func testEarlyAccessCopy() {
        XCTAssertTrue(SpotifyAccessGate.limitedMessage.contains("early access"))
        XCTAssertTrue(SpotifyAccessGate.limitedMessage.contains("Apple Music"))
        XCTAssertEqual(SpotifyAccessGate.continueButtonTitle, "Continue with Apple Music")
    }
}
