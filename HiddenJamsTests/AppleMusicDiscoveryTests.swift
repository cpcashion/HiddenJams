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
        // Boundaries of the Last.fm-listener → pseudo-popularity mapping.
        #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 0) == 10)
        #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 999) == 10)
        #expect(EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 1_000) == 25)
        let at100k = EnhancedHiddenGemsDiscovery.pseudoPopularity(listeners: 100_000)
        #expect(at100k >= 40 && at100k <= 44)
    }

    @Test func emptyAppleSeedsSurfaceAnError() async {
        // Regression: empty Apple Music seeds used to return [] silently,
        // which looked like discovery "glitched" back to the dashboard.
        // Now the failure must be visible via errorMessage.
        let engine = EnhancedHiddenGemsDiscovery()
        await engine.discoverHiddenGems(
            profile: ListeningProfile(),
            userTracks: [],
            userLibrary: [],
            token: nil,
            appleMusicSeeds: []
        )
        #expect(engine.errorMessage != nil)
        #expect(engine.discoveredGems.isEmpty)
    }
}
