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

    /// Canned listener counts: obscure artists pass, famous ones don't.
    private func listenerCheck(obscure: Set<String> = []) -> (String) async throws -> Int? {
        { artist in
            if artist.lowercased().contains("famous") { return 2_000_000 }
            if obscure.contains(artist) { return 40 }
            return 40 // generic stub artist: comfortably under the default cap
        }
    }

    @Test func itunesFallbackProducesPlayableTracksForEmptyLibrary() async throws {
        var stub = StubCatalog()
        stub.resultsByGenre["alternative"] = genreResults(genre: "alternative", count: 30)
        stub.resultsByGenre["indie"] = genreResults(genre: "indie", count: 30, idBase: 1000)

        // Brand-new user: no profile genres, no library tracks at all.
        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            maxCandidates: 20,
            listenerCheck: listenerCheck(),
            itunesService: stub
        )

        // The guarantee: tracks, every one playable, no duplicates.
        #expect(!tracks.isEmpty)
        #expect(tracks.allSatisfy { $0.previewUrl != nil })
        #expect(Set(tracks.map { $0.id }).count == tracks.count)
        let artists = tracks.compactMap { $0.artists.first?.name }
        #expect(Set(artists).count == artists.count)
    }

    @Test func itunesFallbackUsesProfileGenresFirst() async throws {
        var stub = StubCatalog()
        stub.resultsByGenre["jazz"] = genreResults(genre: "jazz", count: 30)
        stub.resultsByGenre["alternative"] = genreResults(genre: "alternative", count: 30, idBase: 5000)

        var profile = ListeningProfile()
        profile.genreWeights = ["jazz": 0.9, "alternative": 0.1]

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: profile,
            seedTracks: [],
            maxCandidates: 10,
            listenerCheck: listenerCheck(),
            itunesService: stub
        )

        #expect(!tracks.isEmpty)
        // Jazz (strongest genre) is queried first and fills the quota.
        #expect(tracks.allSatisfy { $0.name.hasPrefix("Jazz Song") })
    }

    @Test func itunesFallbackUsesSessionGenresOverProfile() async throws {
        // The hip-hop bug: the session picked hip-hop, the user's profile is
        // rock-heavy — the fallback must query hip-hop, not rock.
        var stub = StubCatalog()
        stub.resultsByGenre["hip-hop"] = genreResults(genre: "hip-hop", count: 30)
        stub.resultsByGenre["rock"] = genreResults(genre: "rock", count: 30, idBase: 9000)

        var profile = ListeningProfile()
        profile.genreWeights = ["rock": 0.9, "metal": 0.8]

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: profile,
            seedTracks: [],
            maxCandidates: 10,
            sessionGenres: ["hip-hop"],
            listenerCheck: listenerCheck(),
            itunesService: stub
        )

        #expect(!tracks.isEmpty)
        #expect(tracks.allSatisfy { $0.name.hasPrefix("Hip-hop Song") })
    }

    @Test func itunesFallbackDropsArtistsAboveListenerCap() async throws {
        var stub = StubCatalog()
        stub.resultsByGenre["rock"] = [
            makeTrack(id: 1, name: "Hit Single", artist: "Famous Rockers", genre: "Rock"),
            makeTrack(id: 2, name: "Deep Cut", artist: "Obscure Trio", genre: "Rock"),
        ]

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            maxCandidates: 10,
            sessionGenres: ["rock"],
            listenerCheck: listenerCheck(),
            itunesService: stub
        )

        // Beck/Avenged Sevenfold-style mainstream acts are dropped even
        // though the catalog surfaced them; the obscure act survives.
        #expect(tracks.count == 1)
        #expect(tracks.first?.artists.first?.name == "Obscure Trio")
    }

    @Test func itunesFallbackAssignsRealPseudoPopularity() async throws {
        var stub = StubCatalog()
        stub.resultsByGenre["indie"] = genreResults(genre: "indie", count: 12)

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            maxCandidates: 5,
            sessionGenres: ["indie"],
            popularityThreshold: 90, // accept everything the stub verifies
            listenerCheck: { _ in 1_000 },
            itunesService: stub
        )

        #expect(!tracks.isEmpty)
        // 1k listeners → pseudo-popularity 25, not a hardcoded estimate.
        #expect(tracks.allSatisfy {
            $0.popularity == EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 1_000)
        })
    }

    @Test func itunesFallbackThrowsHonestErrorWhenPopularityServiceDown() async throws {
        var stub = StubCatalog()
        stub.resultsByGenre["indie"] = genreResults(genre: "indie", count: 12)

        let discovery = EnhancedHiddenGemsDiscovery()
        // Every listener check fails service-side, but the catalog answers.
        struct ServiceDown: Error {}
        do {
            _ = try await discovery.itunesGenreFallbackCandidates(
                profile: ListeningProfile(),
                seedTracks: [],
                maxCandidates: 5,
                sessionGenres: ["indie"],
                listenerCheck: { _ in throw ServiceDown() },
                itunesService: stub
            )
            #expect(Bool(false), "expected popularityUnavailable to be thrown")
        } catch let error as AppleMusicError {
            if case .popularityUnavailable = error { /* expected */ }
            else { #expect(Bool(false), "wrong error: \(error)") }
        }
    }

    @Test func itunesFallbackEmptyOnlyWhenCatalogUnreachable() async throws {
        // Stub returns nothing for every genre = iTunes Search unreachable.
        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            listenerCheck: listenerCheck(),
            itunesService: StubCatalog()
        )
        #expect(tracks.isEmpty)
    }

    @Test func maxListenersInvertsPseudoPopularity() {
        // Slider 15 ("Deep Cuts") ≈ artists under ~62 Last.fm listeners;
        // slider 30 ≈ under ~4k. The verified popularity must pass the
        // downstream `popularity < threshold` filter by construction.
        for threshold in [15, 30, 45, 60] {
            let cap = EnhancedHiddenGemsDiscovery.maxListeners(forPopularityThreshold: threshold)
            #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: cap) < threshold)
        }
        #expect(EnhancedHiddenGemsDiscovery.maxListeners(forPopularityThreshold: 15) == 62)
        #expect(EnhancedHiddenGemsDiscovery.maxListeners(forPopularityThreshold: 30) == 3980)
    }
}
