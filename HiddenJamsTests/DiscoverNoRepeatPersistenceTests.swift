//
//  DiscoverNoRepeatPersistenceTests.swift
//  HiddenJamsTests
//
//  Discover never repeats a song or an artist, across Discover taps AND
//  across app launches (Chris, 2026-11-03). Earlier builds kept the
//  no-repeat memory only in RAM, so each relaunch replayed the same songs.
//  These tests simulate relaunches by reloading the memory from a fresh
//  UserDefaults suite between taps. Runs against the stub Spotify catalog
//  from GenreDeckBuilderTests, no network.
//

import XCTest
@testable import HiddenJams

@MainActor
final class DiscoverNoRepeatPersistenceTests: XCTestCase {

    private typealias Stub = GenreDeckBuilderTests.StubCatalog
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DiscoverNoRepeatPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// One Discover tap in a fresh app launch: load memory from disk, build,
    /// gate, save. Exactly what EnhancedHiddenGemsDiscovery does.
    private func tapAfterRelaunch(
        _ stub: Stub,
        genres: [String],
        ceiling: Int = 15,
        followers: Int = 10_000,
        target: Int = 50
    ) async -> [SpotifyTrack] {
        var memory = DiscoverySessionMemory.load(from: defaults)
        var request = GenreDeckRequest(genres: genres, popularityCeiling: ceiling, followerCeiling: followers)
        request.timeBudget = GenreDeckBuilderTests.testTimeBudget
        request.target = target
        memory.apply(to: &request)
        let deck = await GenreDeckBuilder(catalog: stub).build(request)
        let admitted = memory.admit(deck.tracks)
        XCTAssertEqual(admitted.map(\.id), deck.tracks.map(\.id),
                       "the builder itself must already exclude everything served before")
        memory.save(to: defaults)
        return admitted
    }

    private func assertNoRepeats(_ tracks: [SpotifyTrack], file: StaticString = #filePath, line: UInt = #line) {
        let ids = tracks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a track repeats", file: file, line: line)
        let songs = tracks.map(GenreDeckBuilder.songKey(for:))
        XCTAssertEqual(Set(songs).count, songs.count, "a song repeats", file: file, line: line)
        let artists = tracks.flatMap { GenreDeckBuilder.artistIds(of: $0) }
        XCTAssertEqual(Set(artists).count, artists.count, "an artist repeats", file: file, line: line)
    }

    // MARK: - Persistence

    func testMemoryRoundTripsThroughUserDefaults() {
        let a = GenreDeckBuilderTests.artist("a", genres: ["house"])
        let b = GenreDeckBuilderTests.artist("b", genres: ["house"])
        var memory = DiscoverySessionMemory.load(from: defaults)
        XCTAssertEqual(memory, DiscoverySessionMemory(), "first launch starts empty")
        _ = memory.admit([GenreDeckBuilderTests.track("t1", artist: a, popularity: 1, featuring: [b])])
        memory.save(to: defaults)

        let relaunched = DiscoverySessionMemory.load(from: defaults)
        XCTAssertEqual(relaunched, memory)
        XCTAssertTrue(relaunched.trackIds.contains("t1"))
        XCTAssertEqual(relaunched.artistIds, ["a", "b"], "every credited artist is remembered")
    }

    func testSingleGenreNeverRepeatsASongOrArtistAcrossRelaunches() async {
        var stub = Stub()
        stub.addGenre("house", idPrefix: "house", artistGenres: ["deep house"], artists: 600, perArtist: 2)

        var everything: [SpotifyTrack] = []
        for launch in 0..<5 {
            let deck = await tapAfterRelaunch(stub, genres: ["house"], ceiling: 90, followers: 500_000)
            XCTAssertEqual(deck.count, 50, "launch \(launch) still gets a full deck of new music")
            assertNoRepeats(deck)
            everything += deck
        }
        assertNoRepeats(everything)
    }

    func testArtistsAreDedupedAcrossSessionsIncludingFeaturedArtists() async {
        var stub = Stub()
        stub.addGenre("house", idPrefix: "house", artistGenres: ["deep house"], artists: 150)
        let guest = GenreDeckBuilderTests.artist("guest", genres: ["deep house"])
        let host = GenreDeckBuilderTests.artist("host", genres: ["deep house"])
        stub.artistsById["guest"] = guest
        stub.artistsById["host"] = host
        stub.addEverywhere(GenreDeckBuilderTests.track("guest-solo", artist: guest, popularity: 1), for: "house")
        stub.addEverywhere(GenreDeckBuilderTests.track("host-feat-guest", artist: host, popularity: 1,
                                                       featuring: [guest]), for: "house")
        stub.addEverywhere(GenreDeckBuilderTests.track("guest-solo-2", artist: guest, popularity: 1,
                                                       name: "Another Guest Song"), for: "house")

        var all: [SpotifyTrack] = []
        for _ in 0..<3 {
            all += await tapAfterRelaunch(stub, genres: ["house"], ceiling: 90, followers: 500_000)
        }
        assertNoRepeats(all)
        let guestTracks = all.filter { GenreDeckBuilder.artistIds(of: $0).contains("guest") }
        XCTAssertLessThanOrEqual(guestTracks.count, 1, "the guest artist appears at most once, ever")
    }

    func testLegacyHistoryIsFoldedIn() async {
        var stub = Stub()
        stub.addGenre("jungle", idPrefix: "jungle", artistGenres: ["jungle"], artists: 40)
        var memory = DiscoverySessionMemory()
        memory.absorb(trackIds: ["jungle-t0", "jungle-t1"], artistIds: ["jungle-a2"])
        memory.save(to: defaults)

        let deck = await tapAfterRelaunch(stub, genres: ["jungle"], ceiling: 90, followers: 500_000)
        XCTAssertFalse(deck.contains { ["jungle-t0", "jungle-t1"].contains($0.id) })
        XCTAssertFalse(deck.contains { GenreDeckBuilder.artistIds(of: $0).contains("jungle-a2") })
        XCTAssertEqual(deck.count, 37)
    }

    func testAnExhaustedGenreGivesNothingRatherThanRepeats() async {
        var stub = Stub()
        stub.addGenre("jungle", idPrefix: "jungle", artistGenres: ["jungle"], artists: 20, perArtist: 3)
        let first = await tapAfterRelaunch(stub, genres: ["jungle"], ceiling: 90, followers: 500_000)
        XCTAssertEqual(first.count, 20)
        let second = await tapAfterRelaunch(stub, genres: ["jungle"], ceiling: 90, followers: 500_000)
        XCTAssertTrue(second.isEmpty, "every artist was served already, so nothing comes back")
    }

    // MARK: - Reading the full pool

    func testSearchPlansVaryBetweenTaps() {
        let families = GenreMatcher(selections: ["house"]).families
        let plans = (0..<6).map { _ in
            GenreDeckBuilder.searchPlan(families: families, slider: 0, pages: 12,
                                        only: Set(families.indices), broaden: [], skipping: [])
        }
        let keys = plans.map { Set($0.map(\.key)) }
        XCTAssertEqual(Set(keys).count, keys.count, "no two taps read the same pages")
        let offsets = Set(plans.flatMap { $0.map(\.offset) })
        XCTAssertGreaterThan(offsets.count, 10, "offsets are spread, not fixed")
        let queries = Set(plans.flatMap { $0.map(\.query) })
        XCTAssertTrue(queries.contains { $0.contains("year:") }, "query terms vary with release-year slices")
        XCTAssertTrue(plans.allSatisfy { $0.count == 12 })
    }

    func testDeepSliderReadsTheTailAndHotTheHead() {
        let families = GenreMatcher(selections: ["house"]).families
        func meanDepth(_ slider: Double) -> Double {
            let pages = (0..<20).flatMap { _ in
                GenreDeckBuilder.searchPlan(families: families, slider: slider, pages: 12,
                                            only: Set(families.indices), broaden: [], skipping: [])
            }
            return pages.map(\.depth).reduce(0, +) / Double(pages.count)
        }
        XCTAssertGreaterThan(meanDepth(0), 0.7)
        XCTAssertLessThan(meanDepth(1), 0.3)
    }

    // MARK: - Slider

    func testFollowerCeilingRunsFromBarelyListenedToMainstream() {
        XCTAssertEqual(PopularitySliderSettings.followerThreshold(for: 0), 10_000)
        XCTAssertEqual(PopularitySliderSettings.followerThreshold(for: 1), 500_000)
        let steps = stride(from: 0.0, through: 1.0, by: 0.1).map(PopularitySliderSettings.followerThreshold(for:))
        XCTAssertEqual(steps, steps.sorted(), "monotonic")
        XCTAssertLessThan(PopularitySliderSettings.followerThreshold(for: 0.5), 100_000,
                          "most of the slider stays obscure")
    }
}
