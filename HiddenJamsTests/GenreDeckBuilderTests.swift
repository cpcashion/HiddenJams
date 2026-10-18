//
//  GenreDeckBuilderTests.swift
//  HiddenJamsTests
//
//  The Discover deck contract (Chris, 2026-10-18): pick a genre and get 50
//  tracks, every one in that genre, the most obscure first per the slider.
//  When the slider leaves too few, popularity is raised in the background
//  to keep the deck at 50. Runs against a stub Spotify, no network.
//

import Testing
import Foundation
@testable import HiddenJams

@MainActor
struct GenreDeckBuilderTests {

    // MARK: - Stub Spotify

    /// Serves search pages per Spotify genre (popular head first, obscure
    /// tail last, like the real thing), full artists by id, and previews
    /// from a table.
    @MainActor
    struct StubCatalog: GenreDeckCatalog {
        var tracksByGenre: [String: [SpotifyTrack]] = [:]
        var artistsById: [String: SpotifyArtist] = [:]
        var previews: [String: String] = [:]

        func searchTracks(query: String, offset: Int) async -> GenreDeckSearchPage? {
            let all = tracksByGenre[Self.genre(in: query)] ?? []
            let start = min(max(offset, 0), all.count)
            let end = min(start + 50, all.count)
            return GenreDeckSearchPage(tracks: Array(all[start..<end]), total: all.count, limit: 50)
        }

        func artists(ids: [String]) async -> [SpotifyArtist] {
            ids.compactMap { artistsById[$0] }
        }

        func previewURL(for track: SpotifyTrack) async -> String? {
            previews[track.id]
        }

        /// `genre:"drum and bass" year:2024` -> `drum and bass`
        static func genre(in query: String) -> String {
            guard let open = query.range(of: "genre:\""),
                  let close = query[open.upperBound...].range(of: "\"") else { return "" }
            return String(query[open.upperBound..<close.lowerBound])
        }

        /// Adds `artists` artists with `perArtist` tracks each, spread over
        /// the Spotify genres `selection` searches. Popularity runs from 80
        /// (first) down to 0 (last).
        mutating func addGenre(
            _ selection: String,
            idPrefix: String,
            artistGenres: [String],
            artists: Int,
            perArtist: Int = 1,
            playable: (Int) -> Bool = { _ in true }
        ) {
            let searches = GenreMatcher.family(for: selection).searches
            let total = artists * perArtist
            var position = 0
            for round in 0..<perArtist {
                for index in 0..<artists {
                    let id = "\(idPrefix)-a\(index)"
                    let artist = artistsById[id] ?? GenreDeckBuilderTests.artist(id, genres: artistGenres)
                    artistsById[id] = artist
                    let popularity = 80 - (80 * position) / max(total - 1, 1)
                    let track = GenreDeckBuilderTests.track(
                        "\(idPrefix)-t\(position)", artist: artist, popularity: popularity,
                        name: "Song \(idPrefix) \(index)-\(round)")
                    tracksByGenre[searches[position % searches.count], default: []].append(track)
                    if playable(position) {
                        previews[track.id] = "https://cdn.example.com/\(track.id).mp3"
                    }
                    position += 1
                }
            }
        }

        /// Puts `track` in every list `selection` searches, with a preview.
        mutating func addEverywhere(_ track: SpotifyTrack, for selection: String) {
            for genre in GenreMatcher.family(for: selection).searches {
                tracksByGenre[genre, default: []].append(track)
            }
            previews[track.id] = "https://cdn.example.com/\(track.id).mp3"
        }
    }

    static func artist(_ id: String, genres: [String], followers: Int = 500) -> SpotifyArtist {
        SpotifyArtist(spotifyId: id, name: "Artist \(id)", genres: genres, popularity: 10,
                      images: nil, followers: SpotifyFollowers(total: followers))
    }

    /// A track as Spotify search returns it: simplified artists, without
    /// genres or followers (the builder looks those up).
    static func track(
        _ id: String,
        artist: SpotifyArtist,
        popularity: Int,
        name: String? = nil,
        featuring: [SpotifyArtist] = []
    ) -> SpotifyTrack {
        let credits = ([artist] + featuring).map {
            SpotifyArtist(spotifyId: $0.spotifyId, name: $0.name, genres: nil, popularity: nil,
                          images: nil, followers: nil)
        }
        return SpotifyTrack(
            spotifyId: id,
            name: name ?? "Song \(id)",
            artists: credits,
            album: SpotifyAlbum(spotifyId: "album-\(id)", name: "Album \(id)", images: [],
                                releaseDate: "2025-06-01", tracks: nil, artists: nil),
            popularity: popularity,
            previewUrl: nil,
            uri: "spotify:track:\(id)",
            durationMs: 200_000,
            externalIds: SpotifyTrack.ExternalIds(isrc: "TEST\(id)")
        )
    }

    /// The app gives a deck about 9 seconds. Tests run in parallel on a
    /// shared main actor (slowly, on CI simulators), so they get a long
    /// budget: these tests check what lands in the deck, not wall-clock speed.
    static let testTimeBudget: TimeInterval = 60

    private func build(
        _ stub: StubCatalog,
        genres: [String],
        ceiling: Int,
        followers: Int = 2_000,
        configure: (inout GenreDeckRequest) -> Void = { _ in }
    ) async -> GenreDeckResult {
        var request = GenreDeckRequest(genres: genres, popularityCeiling: ceiling, followerCeiling: followers)
        request.timeBudget = Self.testTimeBudget
        configure(&request)
        return await GenreDeckBuilder(catalog: stub).build(request)
    }

    private func isIn(_ genres: [String], _ track: SpotifyTrack) -> Bool {
        GenreMatcher(selections: genres).match(track.artists.first?.genres ?? []) != nil
    }

    // MARK: - Always 50, always the genre

    @Test func drumAndBassDeckIsFiftyTracksAllDrumAndBass() async {
        var stub = StubCatalog()
        stub.addGenre("drum and bass", idPrefix: "dnb", artistGenres: ["drum and bass", "liquid funk"],
                      artists: 70, perArtist: 2)
        // Side Effect, an indie rock band, turning up in DnB search results
        // as the most obscure track there is.
        let sideEffect = Self.artist("side-effect", genres: ["indie rock", "garage rock"])
        stub.artistsById["side-effect"] = sideEffect
        stub.addEverywhere(
            Self.track("bandshirt", artist: sideEffect, popularity: 0, name: "Bandshirt And A Cap"),
            for: "drum and bass")

        let deck = await build(stub, genres: ["drum and bass"], ceiling: 15)

        #expect(deck.tracks.count == 50)
        #expect(!deck.tracks.contains { $0.id == "bandshirt" }, "indie rock must never reach a DnB deck")
        #expect(deck.tracks.allSatisfy { isIn(["drum and bass"], $0) })
        #expect(deck.playableCount == 50)
        #expect(Set(deck.tracks.map(\.id)).count == 50, "no duplicate tracks")
    }

    @Test func mostObscureComeFirstAndPopularityIsRaisedOnlyToFill() async {
        var stub = StubCatalog()
        stub.addGenre("drum and bass", idPrefix: "dnb", artistGenres: ["neurofunk"], artists: 120)

        let deck = await build(stub, genres: ["drum and bass"], ceiling: 15)

        #expect(deck.tracks.count == 50, "popularity is raised in the background to keep the deck full")
        let levels = deck.tracks.map {
            GenreDeckBuilder.relaxationLevel(popularity: $0.popularity, followers: 500,
                                             popularityCeiling: 15, followerCeiling: 2_000)
        }
        #expect(levels.first == 0, "the deck opens with tracks inside the slider")
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 },
                "every track inside the slider comes before any relaxed one")
        #expect(deck.relaxedCount == levels.filter { $0 > 0 }.count)
    }

    @Test func hotSliderReadsThePopularEnd() async {
        var stub = StubCatalog()
        stub.addGenre("drum and bass", idPrefix: "dnb", artistGenres: ["drum and bass"], artists: 150)

        let deck = await build(stub, genres: ["drum and bass"], ceiling: 90, followers: 500_000)

        #expect(deck.tracks.count == 50)
        let average = Double(deck.tracks.map(\.popularity).reduce(0, +)) / Double(deck.tracks.count)
        #expect(average > 40, "Hot should lead with popular tracks, got an average of \(average)")
    }

    @Test func twoGenresShareTheDeck() async {
        var stub = StubCatalog()
        stub.addGenre("drum and bass", idPrefix: "dnb", artistGenres: ["drum and bass"], artists: 120)
        stub.addGenre("house", idPrefix: "house", artistGenres: ["deep house"], artists: 120)

        let deck = await build(stub, genres: ["drum and bass", "house"], ceiling: 50, followers: 250_000)

        let dnb = deck.tracks.filter { isIn(["drum and bass"], $0) }.count
        let house = deck.tracks.filter { isIn(["house"], $0) }.count
        #expect(deck.tracks.count == 50)
        #expect(dnb + house == 50, "nothing outside the two picks")
        #expect(dnb >= 20 && house >= 20, "both genres get a fair share (dnb \(dnb), house \(house))")
    }

    // MARK: - Variety and playability

    @Test func noArtistGetsMoreThanTwoTracksWhenOthersAreAvailable() async {
        var stub = StubCatalog()
        stub.addGenre("house", idPrefix: "house", artistGenres: ["deep house"], artists: 120)
        let prolific = Self.artist("prolific", genres: ["house"])
        stub.artistsById["prolific"] = prolific
        for index in 0..<30 {
            stub.addEverywhere(Self.track("flood\(index)", artist: prolific, popularity: 1), for: "house")
        }

        let deck = await build(stub, genres: ["house"], ceiling: 15)

        #expect(deck.tracks.count == 50)
        #expect(deck.tracks.filter { $0.artists.first?.spotifyId == "prolific" }.count <= 2)
    }

    @Test func tracksWithoutPreviewsAreSwappedOut() async {
        var stub = StubCatalog()
        stub.addGenre("techno", idPrefix: "techno", artistGenres: ["minimal techno"], artists: 150,
                      playable: { $0 % 3 != 0 })

        let deck = await build(stub, genres: ["techno"], ceiling: 90, followers: 500_000)

        #expect(deck.tracks.count == 50)
        #expect(deck.playableCount == 50)
        #expect(deck.tracks.allSatisfy { !($0.previewUrl ?? "").isEmpty })
    }

    @Test func libraryAndSessionTracksNeverAppear() async {
        var stub = StubCatalog()
        stub.addGenre("house", idPrefix: "house", artistGenres: ["deep house"], artists: 150)
        let excluded = Set((0..<150).filter { $0 % 3 == 0 }.map { "house-t\($0)" })

        let deck = await build(stub, genres: ["house"], ceiling: 90, followers: 500_000) {
            $0.excludedTrackIds = excluded
        }

        #expect(deck.tracks.count == 50)
        #expect(!deck.tracks.contains { excluded.contains($0.id) })
    }

    @Test func recentlyServedTracksOnlyAsALastResort() async {
        var stub = StubCatalog()
        stub.addGenre("jungle", idPrefix: "jungle", artistGenres: ["jungle"], artists: 30)
        let seen = Set((0..<30).filter { $0 % 2 == 0 }.map { "jungle-t\($0)" })

        let deck = await build(stub, genres: ["jungle"], ceiling: 90, followers: 500_000) {
            $0.isTrackSeen = { seen.contains($0) }
        }

        // Only 30 jungle tracks exist, so repeats fill the deck, last.
        #expect(deck.tracks.count == 30)
        let firstRepeat = deck.tracks.firstIndex { seen.contains($0.id) } ?? deck.tracks.count
        #expect(firstRepeat == 15)
        #expect(deck.tracks[firstRepeat...].allSatisfy { seen.contains($0.id) })
    }

    // MARK: - Who decides the genre

    @Test func mainArtistDecidesTheGenre() async {
        var stub = StubCatalog()
        stub.addGenre("drum and bass", idPrefix: "dnb", artistGenres: ["drum and bass"], artists: 60)
        let mc = Self.artist("mc", genres: ["drum and bass"])
        let newcomer = Self.artist("newcomer", genres: [])  // Spotify lists no genres yet
        let rockBand = Self.artist("rock-band", genres: ["indie rock"])
        for artist in [mc, newcomer, rockBand] {
            stub.artistsById[artist.spotifyId!] = artist
        }
        stub.addEverywhere(Self.track("feat-ok", artist: newcomer, popularity: 1, featuring: [mc]),
                           for: "drum and bass")
        stub.addEverywhere(Self.track("feat-wrong", artist: rockBand, popularity: 1, featuring: [mc]),
                           for: "drum and bass")

        let deck = await build(stub, genres: ["drum and bass"], ceiling: 15)

        // A genre-less newcomer featuring a DnB MC is DnB...
        #expect(deck.tracks.contains { $0.id == "feat-ok" })
        // ...but an indie rock band's song doesn't become DnB by featuring one.
        #expect(!deck.tracks.contains { $0.id == "feat-wrong" })
    }

    @Test func nothingInTheGenreMeansAnEmptyDeckNotAWrongOne() async {
        var stub = StubCatalog()
        // DnB searches only turn up rock bands.
        stub.addGenre("drum and bass", idPrefix: "rock", artistGenres: ["indie rock"], artists: 40)

        let deck = await build(stub, genres: ["drum and bass"], ceiling: 15)

        #expect(deck.tracks.isEmpty)
        #expect(deck.stats["wrong_genre", default: 0] > 0)
    }

    // MARK: - Speed and the slider math

    @Test func buildingFinishesWithoutWaitingOutItsBudget() async {
        var stub = StubCatalog()
        stub.addGenre("ambient", idPrefix: "ambient", artistGenres: ["dark ambient"], artists: 120)

        let started = Date()
        let deck = await build(stub, genres: ["ambient"], ceiling: 15)

        #expect(deck.tracks.count == 50)
        // The stub answers instantly, so a build that sits until its time
        // budget runs out (a stuck wait or a sleep) shows up here.
        #expect(Date().timeIntervalSince(started) < Self.testTimeBudget / 3)
    }

    @Test func titleMatchingIgnoresStoreTagsButNotVersions() {
        #expect(DeezerPreviewService.coreTitle("Roller - Original Mix") == DeezerPreviewService.coreTitle("Roller"))
        #expect(DeezerPreviewService.coreTitle("Roller (feat. MC Fox)") == "roller")
        #expect(DeezerPreviewService.coreTitle("Roller feat. MC Fox") == "roller")
        #expect(DeezerPreviewService.coreTitle("Roller - 2011 Remaster") == "roller")
        #expect(DeezerPreviewService.coreTitle("Café Del Mar") == "cafedelmar")
        // A remix is a different recording.
        #expect(DeezerPreviewService.coreTitle("Roller - Calibre Remix") != DeezerPreviewService.coreTitle("Roller"))
        #expect(DeezerPreviewService.titlesMatch("Roller (VIP)", "Roller - VIP"))
        #expect(DeezerPreviewService.artistsMatch("The Side Effect", "Side Effect"))
        #expect(!DeezerPreviewService.artistsMatch("Side", "Side Effect"))
    }

    @Test func relaxationSteps() {
        func level(_ popularity: Int, _ followers: Int?) -> Int {
            GenreDeckBuilder.relaxationLevel(popularity: popularity, followers: followers,
                                             popularityCeiling: 15, followerCeiling: 2_000)
        }
        #expect(level(10, 500) == 0)
        #expect(level(15, nil) == 0)
        #expect(level(16, nil) == 1)
        #expect(level(35, nil) == 2)
        #expect(level(5, 5_000) == 1)
        #expect(level(5, 50_000) == 3)  // 2k -> 6k -> 18k -> 54k
    }
}
