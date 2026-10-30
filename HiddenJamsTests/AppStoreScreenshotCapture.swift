//
//  AppStoreScreenshotCapture.swift
//  HiddenJamsTests
//
//  App Store screenshot capture (build 80). Hosts the app's real SwiftUI
//  screens with demo data in a full-screen window on the simulator, then
//  prints each capture as base64 PNG chunks to the test log so it can be
//  pulled from CI. Lives only on the asc-screenshots branch (not merged).
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import HiddenJams

@MainActor
struct AppStoreScreenshotCapture {

    // Real tracks (iTunes Search API IDs) — artwork + previews fetched live.
    private static let deck: [(id: String, genre: String, popularity: Int, followers: Int, genres: [String])] = [
        ("6796833152", "house", 18, 6_240, ["deep house", "house"]),
        ("1549123784", "drum and bass", 12, 3_870, ["liquid funk", "drum and bass"]),
        ("1786417971", "house", 27, 41_300, ["deep house", "house", "jazz house"]),
        ("6766618932", "techno", 31, 88_900, ["techno", "breakbeat"]),
        ("1724949276", "jungle", 34, 120_400, ["jungle", "drum and bass"]),
        ("1383848676", "drum and bass", 29, 75_200, ["liquid funk", "drum and bass"]),
        ("1558499199", "house", 25, 41_300, ["deep house", "house"]),
        ("1798245648", "electronic", 33, 96_500, ["electronic", "house"]),
    ]

    private struct ITunesLookup: Decodable {
        struct R: Decodable {
            let trackId: Int
            let trackName: String
            let artistName: String
            let artistId: Int?
            let collectionName: String?
            let artworkUrl100: String?
            let previewUrl: String?
            let releaseDate: String?
            let trackTimeMillis: Int?
        }
        let results: [R]
    }

    private func fetchDeck() async throws -> [RecommendedTrack] {
        let ids = Self.deck.map(\.id).joined(separator: ",")
        let url = URL(string: "https://itunes.apple.com/lookup?id=\(ids)&country=US")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let results = try JSONDecoder().decode(ITunesLookup.self, from: data).results
        var out: [RecommendedTrack] = []
        for (i, d) in Self.deck.enumerated() {
            guard let r = results.first(where: { String($0.trackId) == d.id }) else { continue }
            let art = (r.artworkUrl100 ?? "").replacingOccurrences(of: "100x100bb", with: "1000x1000bb")
            let artist = SpotifyArtist(
                spotifyId: "artist\(r.artistId ?? i)", name: r.artistName.components(separatedBy: " & ").first ?? r.artistName,
                genres: d.genres, popularity: d.popularity, images: nil,
                followers: SpotifyFollowers(total: d.followers))
            let album = SpotifyAlbum(
                spotifyId: "album\(d.id)", name: r.collectionName ?? r.trackName,
                images: [SpotifyImage(url: URL(string: art)!, height: 1000, width: 1000)],
                releaseDate: r.releaseDate.map { String($0.prefix(10)) }, tracks: nil, artists: [artist])
            let track = SpotifyTrack(
                spotifyId: "hj\(d.id)", name: r.trackName, artists: [artist], album: album,
                popularity: d.popularity, previewUrl: r.previewUrl, uri: "spotify:track:hj\(d.id)",
                durationMs: r.trackTimeMillis ?? 200_000)
            out.append(RecommendedTrack(
                id: track.id, spotifyURI: track.uri, track: track,
                matchScore: 0.9 - Double(i) * 0.03, obscurityScore: Double(100 - d.popularity) / 100,
                recencyScore: 0.8, totalScore: 0.92 - Double(i) * 0.03,
                obscurityReason: "Under the radar",
                matchExplanation: "Matches your \(d.genre) taste",
                similarToTrack: nil, similarityReasons: [d.genre.capitalized]))
        }
        return out
    }

    // MARK: - Capture

    private func capture(_ name: String, wait seconds: Double, @ViewBuilder _ content: () -> some View,
                         env: Env, keep: inout [UIWindow]) async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        keep.forEach { $0.isHidden = true }
        let window = UIWindow(windowScene: scene)
        let root = content()
            .environmentObject(env.auth).environmentObject(env.api).environmentObject(env.analyzer)
            .environmentObject(env.facts).environmentObject(env.audio).environmentObject(env.apple)
            .environmentObject(env.sources).environmentObject(ThemeManager.shared)
            .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: root)
        window.rootViewController = host
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        keep.append(window)
        try await Task.sleep(for: .seconds(seconds))

        let bounds = window.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        let data = image.pngData()!
        let b64 = data.base64EncodedString()
        let out = FileHandle.standardOutput
        func emit(_ s: String) { out.write((s + "\n").data(using: .utf8)!) }
        emit("HJSHOT-BEGIN \(name) \(Int(bounds.width))x\(Int(bounds.height))@\(window.screen.scale) bytes=\(data.count)")
        var idx = 0
        var start = b64.startIndex
        while start < b64.endIndex {
            let end = b64.index(start, offsetBy: 3000, limitedBy: b64.endIndex) ?? b64.endIndex
            emit("HJSHOT \(name) \(idx) \(b64[start..<end])")
            idx += 1
            start = end
        }
        emit("HJSHOT-END \(name) chunks=\(idx)")
    }

    @MainActor final class Env {
        let auth = SpotifyAuthManager()
        let api = SpotifyAPIService()
        let apple = AppleMusicService()
        lazy var analyzer = AIProfileAnalyzer(appleMusicService: apple)
        let facts = MusicFactsService()
        let audio = AudioPreviewManager()
        lazy var sources = MusicSourceManager(spotifyAuth: auth, appleMusic: apple)
        let engine = EnhancedHiddenGemsDiscovery()
    }

    private struct TabChrome<Content: View>: View {
        let tab: MainTabView.Tab
        @ViewBuilder let content: Content
        @EnvironmentObject var audio: AudioPreviewManager
        var body: some View {
            ZStack(alignment: .bottom) {
                Theme.Colors.backgroundGradient.ignoresSafeArea()
                ZStack(alignment: .bottom) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    LiquidTabBar(selectedTab: .constant(tab))
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, 20)
                }
                .ignoresSafeArea()
                MiniPlayerView()
                    .zIndex(2)
                    .padding(.bottom, 92)
            }
        }
    }

    private struct ProfileStatHost: View {
        let focus: ProfileStatFocus
        let deckCount: Int
        @State private var f: ProfileStatFocus?
        var body: some View {
            ProfileView(statFocus: $f, deckGemCount: deckCount)
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    f = focus
                }
        }
    }

    @Test(.timeLimit(.minutes(10)))
    func captureAppStoreScreenshots() async throws {
        print("HJSHOT-INFO screen=\(UIScreen.main.bounds) scale=\(UIScreen.main.scale)")
        let gems = try await fetchDeck()
        #expect(gems.count >= 6)

        // Demo state
        let defaults = UserDefaults.standard
        defaults.set(try JSONEncoder().encode(Set(["House", "Drum and Bass", "Techno"])), forKey: "selectedGenres")
        let env = Env()
        let user = SpotifyUser(id: "hj-demo", displayName: "Chris", email: nil, images: nil, product: "premium")
        env.auth.user = user
        env.auth.isAuthenticated = true
        UserProfileManager.shared.linkSpotify(user: user)
        UserProfileManager.shared.setDisplayName("Chris")

        var profile = ListeningProfile()
        let weights: [String: Double] = [
            "house": 0.24, "drum and bass": 0.19, "techno": 0.13, "jungle": 0.09,
            "electronic": 0.08, "indie": 0.07, "deep house": 0.06, "breakbeat": 0.05,
            "uk garage": 0.04, "ambient": 0.03, "hip hop": 0.02,
        ]
        profile.genreWeights = weights
        profile.topGenresFormatted = weights.sorted { $0.value > $1.value }
            .map { GenreItem(name: $0.key.capitalized, percentage: $0.value * 100) }
        profile.totalTracksAnalyzed = 1_248
        profile.lastAnalyzed = Date().addingTimeInterval(-2 * 3600)
        profile.profileStrength = 0.86
        profile.obscurityScore = 72
        var library: [LibraryTrack] = []
        for (g, w) in weights {
            for n in 0..<Int(w * 1_248) {
                library.append(LibraryTrack(id: "spotify:track:\(g)-\(n)", title: "\(g) \(n)", artistName: "a",
                                            albumName: "b", releaseDate: "2024-01-01", genreNames: [g],
                                            durationMs: 200_000, artworkURL: nil, source: .spotify))
            }
        }
        env.analyzer.libraryTracks = library
        env.analyzer.profile = profile
        env.engine.discoveredGems = gems

        for (i, g) in gems.enumerated() {
            ListeningStatsStore.shared.recordPlay(g)
            if i % 2 == 1 || i == 0 {
                SavedGemsStore.shared.save(g)
                SavedGemsStore.shared.markSaved(trackId: g.id)
                ListeningStatsStore.shared.recordSave(g, method: i == 3 ? .watch : .swipe)
            }
        }
        env.audio.loadQueue(gems, autoPlay: true, isDiscoveryDeck: true)

        var windows: [UIWindow] = []
        let engine = env.engine

        try await capture("01-home", wait: 10, {
            TabChrome(tab: .home) {
                DashboardView(discoveryEngine: engine, onShowPlayer: {}, onShowProfile: {}, onShowStat: { _ in })
            }
        }, env: env, keep: &windows)

        try await capture("02-swipe", wait: 8, {
            TabChrome(tab: .player) {
                PlaylistPlayerView(recommendations: gems, onSave: { _ in })
            }
        }, env: env, keep: &windows)

        let first = gems[0]
        let rarity = await RarityService.shared.rarity(for: first.track.artists[0], spotifyToken: nil)
        try await capture("03-rarity", wait: 8, {
            TabChrome(tab: .player) {
                PlaylistPlayerView(recommendations: gems, onSave: { _ in })
            }
            .sheet(isPresented: .constant(true)) {
                RaritySheet(rarity: rarity, trackName: first.track.name)
                    .environmentObject(env.audio)
                    .preferredColorScheme(.dark)
            }
        }, env: env, keep: &windows)

        try await capture("04-profile", wait: 6, {
            TabChrome(tab: .profile) { ProfileView(deckGemCount: gems.count) }
        }, env: env, keep: &windows)

        for focus in [ProfileStatFocus.gems, .genres, .tracks] {
            try await capture("05-stat-\(focus.rawValue)", wait: 6, {
                TabChrome(tab: .profile) { ProfileStatHost(focus: focus, deckCount: gems.count) }
            }, env: env, keep: &windows)
        }
        windows.forEach { $0.isHidden = true }
        env.audio.stop()
    }
}
