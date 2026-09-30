//
//  AppleMusicDiscoveryTests.swift
//  HiddenJamsTests
//
//  Regression tests for the Apple Music discovery "silent glitch":
//  discovery used to return to the dashboard with no tracks and no error.

import Testing
import Foundation
@testable import HiddenJams

struct AppleMusicDiscoveryTests {

    private func sampleLibraryTracks() -> [LibraryTrack] {
        [
            LibraryTrack(
                id: "applemusic:song:1",
                title: "Test Song",
                artistName: "Test Artist",
                albumName: "Test Album",
                releaseDate: "2020-01-01",
                genreNames: ["Alternative"],
                durationMs: 180_000,
                artworkURL: nil,
                source: .appleMusic
            ),
            LibraryTrack(
                id: "spotify:track:2",
                title: "Other Song",
                artistName: "Other Artist",
                albumName: "Other Album",
                releaseDate: nil,
                genreNames: [],
                durationMs: 200_000,
                artworkURL: nil,
                source: .spotify
            )
        ]
    }

    @Test func sourceLibraryRoundTrip() {
        // The Apple discovery seeds must survive a save/load cycle so a
        // cached profile still has seeds after an app restart.
        let tracks = sampleLibraryTracks()
        UserDataManager.shared.saveSourceLibrary(tracks)

        let loaded = UserDataManager.shared.loadSourceLibrary()
        #expect(loaded == tracks)
        #expect(loaded?.first?.source == .appleMusic)
        #expect(loaded?.last?.source == .spotify)
    }

    @Test func pseudoPopularityMapping() {
        // Spot-checks of the Last.fm-listener → pseudo-popularity mapping
        // (inverse of the understandable listener bands).
        #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 0) == 0)
        #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 500) == 14)
        #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 1_000) == 18)
        let at100k = EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 100_000)
        #expect(at100k >= 60 && at100k <= 64)
    }

    @Test func tagTopTracksDecoding() throws {
        // The genre fallback (empty Apple library → Last.fm tag tops) must
        // parse tag.gettoptracks responses. Tag tracks carry no "match" score.
        let json = """
        {"tracks":{"track":[
            {"name":"Obscure Gem","artist":{"name":"Unknown Band"},"url":"https://example.com"},
            {"name":"","artist":{"name":"No Title"},"url":"https://example.com"}
        ]}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LastFmTagTopTracksResponse.self, from: json)
        #expect(decoded.tracks.track.count == 2)
        #expect(decoded.tracks.track[0].name == "Obscure Gem")
        #expect(decoded.tracks.track[0].artist.name == "Unknown Band")
    }

    @Test func appleAnalysisWithoutAuthorizationFailsGracefully() async {
        // The dashboard's Discover button now auto-analyzes when Apple Music
        // is connected but no Apple tracks were read yet. If authorization is
        // actually missing (e.g. revoked in Settings), the analysis must
        // surface an error instead of hanging or crashing.
        let analyzer = AIProfileAnalyzer(appleMusicService: AppleMusicService())
        await analyzer.analyzeAllConnectedSources(spotifyToken: nil)
        #expect(analyzer.errorMessage != nil)
        #expect(analyzer.isAnalyzing == false)
        #expect(analyzer.libraryTracks.isEmpty)
    }
}
