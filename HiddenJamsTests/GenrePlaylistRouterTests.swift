//
//  GenrePlaylistRouterTests.swift
//  HiddenJamsTests
//
//  Swipe-right now routes into per-genre playlists ("HJ - Rock", ...).
//  These tests pin the genre -> bucket mapping, the session/artist signal
//  priority, and the playlist naming.
//

import Testing
import Foundation
@testable import HiddenJams

struct GenrePlaylistRouterTests {

    private func makeTrack(artistGenres: [String]) -> RecommendedTrack {
        let artist = SpotifyArtist(
            spotifyId: nil, name: "Test Artist", genres: artistGenres,
            popularity: nil, images: nil, followers: nil)
        let album = SpotifyAlbum(
            spotifyId: nil, name: "Test Album", images: [],
            releaseDate: nil, tracks: nil, artists: nil)
        let track = SpotifyTrack(
            spotifyId: "test:1", name: "Test Song", artists: [artist],
            album: album, popularity: 5, previewUrl: nil,
            uri: "test:1", durationMs: 180_000)
        return RecommendedTrack(
            id: "test:1", spotifyURI: "test:1", track: track,
            matchScore: 0.9, obscurityScore: 0.9, recencyScore: 0.5,
            totalScore: 0.8, obscurityReason: "test",
            matchExplanation: "test", similarToTrack: nil, similarityReasons: [])
    }

    // MARK: - Genre string -> bucket

    @Test("genre strings map to coarse buckets")
    func genreMapping() {
        let cases: [(String, String)] = [
            ("liquid funk", "Drum and Bass"),
            ("neurofunk", "Drum and Bass"),
            ("jungle", "Drum and Bass"),
            ("drum and bass", "Drum and Bass"),
            ("Hip-Hop/Rap", "Hip-Hop"),
            ("trap soul", "Hip-Hop"),
            ("r&b", "R&B"),
            ("indie rock", "Rock"),
            ("k-pop", "Pop"),
            ("dance", "Electronic"),
            ("deep house", "House"),
            ("bossa nova", "Jazz"),
            ("singer-songwriter", "Folk"),
            ("afrobeats", "Afrobeats"),
        ]
        for (genre, bucket) in cases {
            #expect(GenrePlaylistRouter.bucket(forGenre: genre) == bucket,
                    "'\(genre)' should map to '\(bucket)'")
        }
    }

    @Test("longest matcher wins over shorter ones")
    func longestMatcherWins() {
        // "pop punk" contains both "pop" and "punk" — the full phrase decides.
        #expect(GenrePlaylistRouter.bucket(forGenre: "pop punk") == "Punk")
        #expect(GenrePlaylistRouter.bucket(forGenre: "dance pop") == "Pop")
    }

    @Test("unmappable and empty genres return nil")
    func unmappableReturnsNil() {
        #expect(GenrePlaylistRouter.bucket(forGenre: "medieval chant") == nil)
        #expect(GenrePlaylistRouter.bucket(forGenre: "") == nil)
        #expect(GenrePlaylistRouter.bucket(forGenre: "   ") == nil)
    }

    // MARK: - Signal priority

    @Test("single-genre session beats artist genres")
    func sessionBeatsArtistGenres() {
        let track = makeTrack(artistGenres: ["dance pop"])
        let bucket = GenrePlaylistRouter.bucket(
            for: track, sessionGenres: ["drum and bass"])
        #expect(bucket == "Drum and Bass")
    }

    @Test("artist genres used when session is broad or empty")
    func artistGenresAsFallback() {
        let track = makeTrack(artistGenres: ["indie rock", "alternative"])
        #expect(GenrePlaylistRouter.bucket(for: track, sessionGenres: []) == "Rock")
        #expect(GenrePlaylistRouter.bucket(
            for: track, sessionGenres: ["rock", "pop", "jazz"]) == "Rock")
    }

    @Test("no signal anywhere returns nil")
    func noSignalReturnsNil() {
        let track = makeTrack(artistGenres: ["medieval chant"])
        #expect(GenrePlaylistRouter.bucket(for: track, sessionGenres: []) == nil)
    }

    // MARK: - Playlist naming

    @Test("playlist names use the HJ prefix, misc falls back")
    func playlistNaming() {
        #expect(GenrePlaylistRouter.playlistName(
            for: makeTrack(artistGenres: ["indie rock"]),
            sessionGenres: []) == "HJ - Rock")
        #expect(GenrePlaylistRouter.playlistName(
            for: makeTrack(artistGenres: ["liquid funk"]),
            sessionGenres: []) == "HJ - Drum and Bass")
        #expect(GenrePlaylistRouter.playlistName(
            for: makeTrack(artistGenres: ["medieval chant"]),
            sessionGenres: []) == "Hidden Gems")
    }
}
