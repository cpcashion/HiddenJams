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

    /// Canned artist verification: obscure artists pass, famous ones don't.
    /// Tags default to empty — the genre-tag gate lets artists with no tag
    /// data through (can't-verify ≠ wrong genre).
    private func artistCheck(
        listeners: [String: Int] = [:],
        tags: [String: Set<String>] = [:],
        defaultListeners: Int = 40
    ) -> (String) async throws -> VerifiedArtist? {
        { artist in
            if artist.lowercased().contains("famous") {
                return VerifiedArtist(listeners: 2_000_000, tags: [])
            }
            return VerifiedArtist(
                listeners: listeners[artist] ?? defaultListeners,
                tags: tags[artist] ?? []
            )
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
            artistCheck: artistCheck(),
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
            artistCheck: artistCheck(),
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
            artistCheck: artistCheck(),
            itunesService: stub
        )

        #expect(!tracks.isEmpty)
        // Case-insensitive: Swift's `capitalized` renders "hip-hop" as
        // "Hip-Hop" (hyphen is a word boundary) — don't depend on that.
        #expect(tracks.allSatisfy { $0.name.lowercased().hasPrefix("hip-hop song") })
        #expect(!tracks.contains { $0.name.lowercased().hasPrefix("rock song") })
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
            artistCheck: artistCheck(),
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
            artistCheck: { _ in VerifiedArtist(listeners: 1_000, tags: []) },
            itunesService: stub
        )

        #expect(!tracks.isEmpty)
        // 1k listeners → pseudo-popularity from the band inverse (≈18), never
        // a hardcoded estimate.
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
                artistCheck: { _ in throw ServiceDown() },
                itunesService: stub
            )
            #expect(Bool(false), "expected popularityUnavailable to be thrown")
        } catch let error as AppleMusicError {
            if case .popularityUnavailable = error { /* expected */ }
            else { #expect(Bool(false), "wrong error: \(error)") }
        }
    }

    @Test func itunesFallbackThrowsFetchFailedWhenCatalogUnreachable() async throws {
        // Stub returns nothing for every genre = iTunes Search unreachable.
        // This is the ONLY path that may report a catalog-connection failure —
        // it must throw honestly, never return a silent empty that a caller
        // could misdiagnose.
        let discovery = EnhancedHiddenGemsDiscovery()
        do {
            _ = try await discovery.itunesGenreFallbackCandidates(
                profile: ListeningProfile(),
                seedTracks: [],
                artistCheck: artistCheck(),
                itunesService: StubCatalog()
            )
            #expect(Bool(false), "expected fetchFailed to be thrown")
        } catch let error as AppleMusicError {
            if case .fetchFailed(let message) = error {
                #expect(message.contains("catalog"))
            } else {
                #expect(Bool(false), "wrong error: \(error)")
            }
        }
    }

    @Test func itunesFallbackRelaxesStrictCapInsteadOfFailing() async throws {
        // Chris's exact failure: Deep Cuts (threshold 15) with a genre whose
        // catalog artists all sit above the strict band. The old code threw
        // "Couldn't reach Apple's music catalog" — a lie. The fallback must
        // relax the band and return tracks.
        var stub = StubCatalog()
        stub.resultsByGenre["reggae"] = genreResults(genre: "reggae", count: 30)

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            maxCandidates: 10,
            sessionGenres: ["reggae"],
            popularityThreshold: 15, // Deep Cuts: strict cap ≈ 500 listeners
            artistCheck: { _ in VerifiedArtist(listeners: 3_000, tags: []) }, // every artist above the strict band
            itunesService: stub
        )

        #expect(!tracks.isEmpty, "strict band must relax, not fail")
        #expect(tracks.count <= 10)
    }

    @Test func itunesFallbackStrictCapWinsWhenPossible() async throws {
        // When artists DO fit the strict band, no relaxation happens — the
        // first rung of the ladder is the user's own cap.
        var stub = StubCatalog()
        stub.resultsByGenre["reggae"] = genreResults(genre: "reggae", count: 30)

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            maxCandidates: 10,
            sessionGenres: ["reggae"],
            popularityThreshold: 15,
            artistCheck: { _ in VerifiedArtist(listeners: 200, tags: []) }, // comfortably under the 500 cap
            itunesService: stub
        )

        #expect(!tracks.isEmpty)
        // 200 listeners → pseudo-popularity well under the 15 threshold.
        #expect(tracks.allSatisfy { $0.popularity < 15 })
    }

    @Test func listenerCapLadderShape() {
        // Starts at the user's strict cap, climbs the anchor bands, and tops
        // out at the 1M "Mainstream" band — never uncapped.
        let ladder = EnhancedHiddenGemsDiscovery.listenerCapLadder(startingAt: 499)
        #expect(ladder.first == 499)
        #expect(ladder.last == 1_000_000)
        #expect(ladder == ladder.sorted())
        #expect(ladder.contains(5_000) && ladder.contains(20_000))

        let topLadder = EnhancedHiddenGemsDiscovery.listenerCapLadder(startingAt: 1_000_000)
        #expect(topLadder == [1_000_000])
    }

    // MARK: - Genre-name matching regression (Chris 2026-09-30)

    /// Selecting Drum and Bass must never play songs that merely *match the
    /// genre word* in their title or artist name (Chris 2026-09-30: the app
    /// played "Jungle (feat. Mendy Worch)" and Drake's "Jungle" for a DnB
    /// session). The iTunes `term` parameter is pure text search, so the
    /// fallback verifies every candidate artist's Last.fm genre TAGS — a
    /// real genre taxonomy independent of names.
    ///
    /// The stub catalog serves 12 genuine DnB tracks plus 2 name-bait tracks
    /// titled "Jungle" whose *catalog* genre claims DnB but whose Last.fm
    /// tags say hip-hop. Both must be dropped by tag verification.
    @Test func dnbFallbackRejectsTracksMatchedOnlyByName() async throws {
        var stub = StubCatalog()
        var results: [ItunesPreviewService.ItunesTrack] = []
        // 12 genuine DnB tracks (catalog genre + Last.fm tags agree).
        for i in 0..<12 {
            results.append(makeTrack(
                id: i,
                name: "Roller \(i)",
                artist: "DnB Producer \(i)",
                genre: "Jungle/Drum'n'bass"
            ))
        }
        // 2 name-bait tracks: titled "Jungle", catalog genre claims DnB,
        // but the artists are hip-hop by Last.fm's taxonomy.
        results.append(makeTrack(id: 100, name: "Jungle", artist: "Name Bait A", genre: "Jungle/Drum'n'bass"))
        results.append(makeTrack(id: 101, name: "Jungle (Remix)", artist: "Name Bait B", genre: "Jungle/Drum'n'bass"))
        stub.resultsByGenre["drum-and-bass"] = results

        var tagMap: [String: Set<String>] = [:]
        for i in 0..<12 {
            tagMap["DnB Producer \(i)"] = ["drumandbass", "liquidfunk"]
        }
        tagMap["Name Bait A"] = ["hiphop", "rap"]
        tagMap["Name Bait B"] = ["hiphop", "trap"]

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.itunesGenreFallbackCandidates(
            profile: ListeningProfile(),
            seedTracks: [],
            maxCandidates: 20,
            sessionGenres: ["drum-and-bass"],
            popularityThreshold: 45,
            artistCheck: artistCheck(tags: tagMap),
            itunesService: stub
        )

        // 14 picked, head-skip drops 3, tag gate drops the 2 name-baits.
        let artists = Set(tracks.compactMap { $0.artists.first?.name })
        #expect(tracks.count == 9, "expected 9 genuine DnB tracks, got \(tracks.count)")
        #expect(!artists.contains("Name Bait A") && !artists.contains("Name Bait B"),
                "name-bait artists must not survive genre-tag verification")
        #expect(!tracks.contains { $0.name.lowercased().contains("jungle") },
                "no track may be selected merely for matching the genre word")
    }

    @Test func maxListenersUsesUnderstandableBands() {
        // Slider 15 ("Deep Cuts") ≈ under 500 listeners; 30 ≈ under 5,000;
        // 45 ≈ under 20,000. The verified popularity must pass the
        // downstream `popularity < threshold` filter by construction.
        for threshold in [15, 30, 45, 60, 90] {
            let cap = EnhancedHiddenGemsDiscovery.maxListeners(forPopularityThreshold: threshold)
            #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: cap) < threshold)
        }
        #expect(abs(EnhancedHiddenGemsDiscovery.maxListeners(forPopularityThreshold: 15) - 500) <= 1)
        #expect(abs(EnhancedHiddenGemsDiscovery.maxListeners(forPopularityThreshold: 30) - 5_000) <= 2)
        #expect(abs(EnhancedHiddenGemsDiscovery.maxListeners(forPopularityThreshold: 45) - 20_000) <= 5)
    }

    // MARK: - Apple Music full batches (Chris 2026-10-01: Apple Music users
    // saw ~5 songs per batch and had to keep hitting Discover)

    @Test func appleMusicBatchTopsUpToFullBatch() async throws {
        // The personalized pipeline yields only 5 — the old experience.
        let pipeline = (0..<5).map { i in
            makeTrack(id: 9000 + i, name: "Pipeline Song \(i)", artist: "Pipeline Artist \(i)", genre: "Rock")
                .toSpotifyTrack(previewURL: "https://example.com/p\(i).m4a", popularity: 5)
        }
        // The fallback catalog holds 40 fresh rock tracks.
        var stub = StubCatalog()
        stub.resultsByGenre["rock"] = (0..<40).map { i in
            makeTrack(id: i, name: "TopUp Song \(i)", artist: "TopUp Artist \(i)", genre: "Rock")
        }

        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.discoverViaLastFmAppleMusic(
            profile: ListeningProfile(),
            seedTracks: [],
            sessionGenres: ["rock"],
            pipelineTracks: pipeline,
            artistCheck: artistCheck(),
            itunesService: stub
        )

        // Full batch: 5 personalized + 25 top-up, no duplicate artists.
        #expect(tracks.count == EnhancedHiddenGemsDiscovery.appleMusicBatchTarget,
                "expected a full \(EnhancedHiddenGemsDiscovery.appleMusicBatchTarget)-song batch, got \(tracks.count)")
        let artists = tracks.map { $0.artistNames.lowercased() }
        #expect(Set(artists).count == artists.count, "duplicate artists in batch")
        #expect(tracks.prefix(5).allSatisfy { $0.artistNames.hasPrefix("Pipeline Artist") },
                "personalized pipeline tracks must come first")
        let pipelineArtists = Set(artists.prefix(5))
        let topUpArtists = Set(artists.dropFirst(5))
        #expect(pipelineArtists.isDisjoint(with: topUpArtists),
                "top-up must not repeat pipeline artists")
    }

    @Test func appleMusicBatchSkipsTopUpWhenFull() async throws {
        // Pipeline already meets the target — the fallback must not run.
        // (The stub catalog is empty, so any fallback call would throw.)
        let pipeline = (0..<30).map { i in
            makeTrack(id: 9000 + i, name: "Pipeline Song \(i)", artist: "Pipeline Artist \(i)", genre: "Rock")
                .toSpotifyTrack(previewURL: "https://example.com/p\(i).m4a", popularity: 5)
        }
        let discovery = EnhancedHiddenGemsDiscovery()
        let tracks = try await discovery.discoverViaLastFmAppleMusic(
            profile: ListeningProfile(),
            seedTracks: [],
            sessionGenres: ["rock"],
            pipelineTracks: pipeline,
            artistCheck: artistCheck(),
            itunesService: StubCatalog()
        )
        #expect(tracks.count == EnhancedHiddenGemsDiscovery.appleMusicBatchTarget)
    }
}

