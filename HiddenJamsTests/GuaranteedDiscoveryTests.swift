//
//  GuaranteedDiscoveryTests.swift
//  HiddenJamsTests
//
//  Proves the guaranteed-discovery contract: every Apple Music user gets
//  playable hidden-jam tracks whenever the device can reach Apple's catalog,
//  no matter what fails upstream (empty library, no profile, Last.fm outage,
//  no Spotify token). The iTunes Search API needs no key, so the genre
//  fallback in EnhancedHiddenGemsDiscovery is the layer that cannot
//  legitimately come back empty while the device is online.

import Testing
import Foundation
@testable import HiddenJams

struct GuaranteedDiscoveryTests {

    // MARK: - Stubs

    /// iTunes catalog stub: returns canned genre results, never touches network.
    struct StubCatalog: ItunesCatalog {
        var resultsByGenre: [String: [ItunesPreviewService.ItunesTrack]] = [:]

        func searchTrack(name: String, artist: String) async -> ItunesPreviewService.ItunesTrack? {
            nil
        }

        func searchGenreTracks(genre: String, limit: Int) async -> [ItunesPreviewService.ItunesTrack] {
            Array((resultsByGenre[genre.lowercased()] ?? []).prefix(limit))
        }
    }

    private func makeTrack(
        id: Int,
        name: String,
        artist: String,
        genre: String?,
        preview: Bool = true
    ) -> ItunesPreviewService.ItunesTrack {
        ItunesPreviewService.ItunesTrack(
            trackId: id,
            trackName: name,
            artistName: artist,
            previewUrl: preview ? "https://example.com/preview\(id).m4a" : nil,
            trackViewUrl: nil,
            artworkUrl100: nil,
            collectionName: "Test Album",
            primaryGenreName: genre,
            releaseDate: nil,
            trackTimeMillis: 180_000
        )
    }

    private func genreResults(
        genre: String,
        count: Int,
        idBase: Int = 0,
        primaryGenre: String? = nil
    ) -> [ItunesPreviewService.ItunesTrack] {
        (0..<count).map { i in
            makeTrack(
                id: idBase + i,
                name: "\(genre.capitalized) Song \(i)",
                artist: "\(genre.capitalized) Artist \(i)",
                genre: primaryGenre ?? genre.capitalized
            )
        }
    }

    private func libraryTrack(title: String, artist: String) -> LibraryTrack {
        LibraryTrack(
            id: "applemusic:song:\(title)",
            title: title,
            artistName: artist,
            albumName: "Album",
            releaseDate: nil,
            genreNames: [],
            durationMs: 180_000,
            artworkURL: nil,
            source: .appleMusic
        )
    }

    // MARK: - Selection logic

    @Test func fallbackSkipsTracksWithoutPreviews() {
        let results = [
            makeTrack(id: 1, name: "No Preview", artist: "A", genre: "Alternative", preview: false),
            makeTrack(id: 2, name: "Has Preview", artist: "B", genre: "Alternative")
        ]
        let picked = EnhancedHiddenGemsDiscovery.selectFallbackTracks(
            from: results, genre: "alternative",
            knownKeys: [], seenArtists: [], limit: 10
        )
        #expect(picked.count == 1)
        #expect(picked.first?.trackName == "Has Preview")
    }

    @Test func fallbackExcludesLibraryTracks() {
        let results = genreResults(genre: "alternative", count: 10)
        // First result mirrors a track the user already has.
        let owned = libraryTrack(title: "Alternative Song 0", artist: "Alternative Artist 0")
        let picked = EnhancedHiddenGemsDiscovery.selectFallbackTracks(
            from: results, genre: "alternative",
            knownKeys: [owned.dedupeKey], seenArtists: [], limit: 10
        )
        #expect(!picked.contains { $0.trackId == 0 })
        // 9 survive the library exclusion; the mainstream-head skip (9/4 = 2)
        // then drops the first two, leaving 7 hidden-jam candidates.
        #expect(picked.count == 7)
    }

    @Test func fallbackOneTrackPerArtist() {
        let results = [
            makeTrack(id: 1, name: "Song A1", artist: "Same Artist", genre: "Alternative"),
            makeTrack(id: 2, name: "Song A2", artist: "Same Artist", genre: "Alternative"),
            makeTrack(id: 3, name: "Song B1", artist: "Other Artist", genre: "Alternative")
        ]
        let picked = EnhancedHiddenGemsDiscovery.selectFallbackTracks(
            from: results, genre: "alternative",
            knownKeys: [], seenArtists: [], limit: 10
        )
        #expect(picked.count == 2)
        #expect(Set(picked.map { $0.artistName }).count == 2)
    }

    @Test func fallbackPrefersTailOverMainstreamHead() {
        // 12 results: the head (first 3 = 25%) is the mainstream the genre
        // search ranks first. With a limit that fits the tail, no head track
        // may be selected.
        let results = genreResults(genre: "indie", count: 12)
        let picked = EnhancedHiddenGemsDiscovery.selectFallbackTracks(
            from: results, genre: "indie",
            knownKeys: [], seenArtists: [], limit: 9
        )
        #expect(picked.count == 9)
        let pickedIds = Set(picked.map { $0.trackId })
        #expect(pickedIds.isDisjoint(with: [0, 1, 2]))
    }

    @Test func fallbackGenreMismatchNeverZeroesOut() {
        // Catalog genre naming ("Shoegaze" vs profile genre "shoegaze-dream")
        // must not wipe the pool — an unfiltered pool beats no tracks.
        let results = genreResults(genre: "Alternative", count: 8)
        let picked = EnhancedHiddenGemsDiscovery.selectFallbackTracks(
            from: results, genre: "shoegaze-dream",
            knownKeys: [], seenArtists: [], limit: 10
        )
        #expect(picked.count == 8)
    }

    @Test func fallbackHonorsLimit() {
        let results = genreResults(genre: "electronic", count: 20)
        let picked = EnhancedHiddenGemsDiscovery.selectFallbackTracks(
            from: results, genre: "electronic",
            knownKeys: [], seenArtists: [], limit: 5
        )
        #expect(picked.count == 5)
    }

    // MARK: - End-to-end fallback

    @Test func itunesFallbackProducesPlayableTracksForEmptyLibrary() async {
        var stub = StubCatalog()
        stub.resultsByGenre["alternative"] = genreResults(genre: "alternative", count: 30)
        stub.resultsByGenre["indie"] = genreResults(genre: "indie", count: 30, idBase: 1000)

        // Brand-new user: no profile genres, no library tracks at all.
        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            maxCandidates: 20,
            itunesService: stub
        )

        // The guarantee: tracks, every one playable, no duplicates.
        #expect(!tracks.isEmpty)
        #expect(tracks.allSatisfy { $0.previewUrl != nil })
        #expect(Set(tracks.map { $0.id }).count == tracks.count)
        let artists = tracks.compactMap { $0.artists.first?.name }
        #expect(Set(artists).count == artists.count)
    }

    @Test func itunesFallbackUsesProfileGenresFirst() async {
        var stub = StubCatalog()
        stub.resultsByGenre["jazz"] = genreResults(genre: "jazz", count: 30)
        stub.resultsByGenre["alternative"] = genreResults(genre: "alternative", count: 30, idBase: 5000)

        var profile = ListeningProfile()
        profile.genreWeights = ["jazz": 0.9, "alternative": 0.1]

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = await discovery.itunesGenreFallbackCandidates(
            profile: profile,
            seedTracks: [],
            maxCandidates: 10,
            itunesService: stub
        )

        #expect(!tracks.isEmpty)
        // Jazz (strongest genre) is queried first and fills the quota.
        #expect(tracks.allSatisfy { $0.name.hasPrefix("Jazz Song") })
    }

    @Test func itunesFallbackEmptyOnlyWhenCatalogUnreachable() async {
        // Stub returns nothing for every genre = iTunes Search unreachable.
        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            itunesService: StubCatalog()
        )
        #expect(tracks.isEmpty)
    }

    @Test func fallbackPopularityPassesDefaultSlider() {
        // Downstream filters drop tracks with popularity >= the slider
        // threshold (default 15 in the UI). The fallback estimate must pass.
        #expect(EnhancedHiddenGemsDiscovery.itunesFallbackPopularity < 15)
    }
}
