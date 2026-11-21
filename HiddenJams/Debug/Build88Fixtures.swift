//
//  Build88Fixtures.swift
//  HiddenJams
//
//  DEBUG ONLY. Capture fixtures for the build 88 feedback fixes (rarity
//  sheet handle, Profile without the mini player, loading fun facts), used
//  by the parity snapshot test. Nothing here ships in Release.
//

#if DEBUG
import SwiftUI
import UIKit
import Combine

enum Build88Fixtures {
    struct Device { let key: String; let size: CGSize; let safeTop: CGFloat; let safeBottom: CGFloat }
    static let devices: [Device] = [
        Device(key: "se", size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0),
        Device(key: "promax", size: CGSize(width: 440, height: 956), safeTop: 62, safeBottom: 34),
    ]
    /// UIKit detent heights: .medium is half the screen, .large stops 10pt
    /// below the top safe area.
    static func detentHeight(_ d: Device, _ detent: String) -> CGFloat {
        detent == "large" ? d.size.height - d.safeTop - 10 : (d.size.height / 2).rounded()
    }

    /// The artist in Chris's build 88 screenshot.
    static let rarity = ArtistRarity(tier: .ultraRare, score: 94, followers: 871, popularity: 6,
                                     lastFmListeners: 19_800, lastFmPlaycount: 79_200,
                                     genres: ["minimal techno"], artistName: "Earthrumental")

    // MARK: Real player + real presented sheet (Liquid Glass)

    /// A generated cover (the onboarding art), written to a file so the
    /// player's AsyncImage loads it like a remote cover.
    static let coverURL: URL? = {
        guard let img = UIImage(named: "obcover-ember"), let data = img.jpegData(compressionQuality: 0.9) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("b88-cover.jpg")
        try? data.write(to: url)
        return url
    }()

    /// Three Spotify-style deck tracks by the artist in Chris's screenshot.
    /// Popularity 6 + 871 followers make the player's own rarity lookup
    /// land on ULTRA RARE 94 without a Spotify token.
    static let deck: [RecommendedTrack] = (1...3).map { i in
        let artist = SpotifyArtist(
            spotifyId: "b88artist", name: "Earthrumental", genres: ["minimal techno"],
            popularity: 6, images: nil, followers: SpotifyFollowers(total: 871))
        let images: [SpotifyImage] = coverURL.map { [SpotifyImage(url: $0, height: 640, width: 640)] } ?? []
        let album = SpotifyAlbum(
            spotifyId: "b88album", name: "Earthrumental Music", images: images,
            releaseDate: nil, tracks: nil, artists: nil)
        let track = SpotifyTrack(
            spotifyId: "b88track\(i)", name: "Track \(i)", artists: [artist],
            album: album, popularity: 6, previewUrl: nil,
            uri: "spotify:track:b88track\(i)", durationMs: 180_000)
        return RecommendedTrack(
            id: "b88track\(i)", spotifyURI: "spotify:track:b88track\(i)", track: track,
            matchScore: 0.9, obscurityScore: 0.9, recencyScore: 0.5,
            totalScore: 0.8, obscurityReason: "capture",
            matchExplanation: "capture", similarToTrack: nil, similarityReasons: [])
    }

    /// Player state on deck track 2 (no playback: the queue is preset, so
    /// the player's syncQueue sees no change and never calls loadQueue).
    /// Static so these objects are never torn down during the test run.
    static let playerEnv: PlayerEnv = {
        let e = PlayerEnv()
        e.audio.queue = deck
        e.audio.currentIndex = 1
        e.audio.currentTrack = deck[1]
        let quota = DiscoveryQuotaManager.shared
        if quota.isUnlimited { quota.simulateFreeTier = true }
        quota.setUsedThisMonthForCapture(2)
        return e
    }()

    static let quiz = "Which of these songs was released in 1996?\n✓ Smashing Pumpkins - 1979"

    static let factPins = [
        "A John Cage organ piece began playing in Halberstadt, Germany, in 2001. It's due to end in 2640.",
        "Dolly Parton wrote \"Jolene\" and \"I Will Always Love You\" on the same day.",
    ]

    private static func pinFacts(_ f: [String], freeze: Bool) -> Bool {
        OnboardingParityFixtures.factsPin = f
        OnboardingParityFixtures.factsFreeze = freeze
        return true
    }

    @ViewBuilder
    static func screen(_ name: String) -> some View {
        let p = name.split(separator: ":").map(String.init)
        if p.first == "sheet", p.count == 4, let d = devices.first(where: { $0.key == p[2] }) {
            SheetCanvas(device: d, height: detentHeight(d, p[3]), legacy: p[1] == "old")
        } else if p.first == "facts", p.count == 3 {
            let i = Int(p[2]) ?? 0
            let _ = pinFacts([factPins[i % factPins.count]], freeze: true)
            FactsCanvas(legacy: p[1] == "old")
        } else if name == "facts-live" {
            let _ = pinFacts(factPins, freeze: false)
            FactsCanvas(legacy: false)
        } else if name == "profile-after" {
            ProfileCanvas()
        } else if name == "paywall" {
            // Full-screen paywall (same view the app presents), wired to
            // the real SubscriptionManager so the price comes from StoreKit.
            PaywallView()
                .environmentObject(SubscriptionManager.shared)
        } else if p.first == "glass", p.count == 2 {
            PlayerSheetCanvas(legacy: p[1] == "old")
        } else {
            Color.red
        }
    }
}

/// A device-sized canvas: the player backdrop, the sheet at a detent
/// height with the system grabber where UIKit draws it (5pt from the top,
/// 36x5), and the real sheet content (current or pre-fix). Scaled to fit
/// the capture window, anchored top-left (crop to size x scale).
private struct SheetCanvas: View {
    let device: Build88Fixtures.Device
    let height: CGFloat
    let legacy: Bool
    var body: some View {
        let s = min(1, 402 / device.size.width, 874 / device.size.height)
        ZStack(alignment: .bottom) {
            Theme.Colors.backgroundGradient
            Color.black.opacity(0.35)
            ZStack(alignment: .top) {
                Group {
                    if legacy {
                        RaritySheetLegacy(rarity: Build88Fixtures.rarity, trackName: "Track")
                    } else {
                        RaritySheet(rarity: Build88Fixtures.rarity, trackName: "Track")
                    }
                }
                .padding(.bottom, device.safeBottom)
                .frame(width: device.size.width, height: height)
                .clipped()
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 5)
            }
            .frame(width: device.size.width, height: height)
            .background(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38).fill(Color(white: 0.11)))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38))
        }
        .frame(width: device.size.width, height: device.size.height)
        .environment(\.colorScheme, .dark)
        .scaleEffect(s, anchor: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

final class PlayerEnv: ObservableObject {
    let audio = AudioPreviewManager()
    let auth = SpotifyAuthManager()
}

/// The real discovery player (PlaylistPlayerView, "Track 2 of 50") with the
/// real RaritySheet presented over it by SwiftUI's .sheet, so UIKit draws
/// the actual Liquid Glass sheet, its corner radius and the system grab
/// handle at the .medium detent. Presented without animation shortly after
/// the player appears.
private struct PlayerSheetCanvas: View {
    let legacy: Bool
    @ObservedObject private var env = Build88Fixtures.playerEnv
    @State private var showSheet = false
    var body: some View {
        // Laid out as MainTabView does on the Play tab: the player, then
        // the Liquid tab bar on top.
        ZStack(alignment: .bottom) {
            PlaylistPlayerView(recommendations: Build88Fixtures.deck, onSave: { _ in })
            LiquidTabBar(selectedTab: .constant(.player))
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 20)
        }
        .ignoresSafeArea()
            .environmentObject(env.audio)
            .environmentObject(env.auth)
            .sheet(isPresented: $showSheet) {
                if legacy {
                    RaritySheetLegacy(rarity: Build88Fixtures.rarity, trackName: Build88Fixtures.deck[1].track.name)
                } else {
                    RaritySheet(rarity: Build88Fixtures.rarity, trackName: Build88Fixtures.deck[1].track.name)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { showSheet = true }
            }
    }
}

/// The Home "Analyzing Your Music" card (DashboardView.analysisProgressCard)
/// with the facts card pinned to one fact (or the pre-fix quiz item).
private struct FactsCanvas: View {
    let legacy: Bool
    @StateObject private var facts = MusicFactsService()
    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Analyzing Your Music")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Finding hidden gems in your library...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                ProgressView(value: 0.62)
                    .tint(Theme.Colors.lime)
                    .scaleEffect(x: 1, y: 1.5)
                Text("62%")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Group {
                    if legacy {
                        LegacyFactsCard(text: Build88Fixtures.quiz)
                    } else {
                        RotatingFactsView().environmentObject(facts)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .surfaceCard(radius: Theme.CornerRadius.card)
            .padding(.horizontal, 20)
            .padding(.top, 120)
        }
    }
}

/// The pre-fix facts card: the trivia item fully typed out.
private struct LegacyFactsCard: View {
    let text: String
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(text)
                .font(Theme.Typography.body2)
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 60, alignment: .topLeading)
        }
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: Theme.CornerRadius.md).fill(Theme.Colors.textPrimary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: Theme.CornerRadius.md).stroke(Theme.Colors.textPrimary.opacity(0.05), lineWidth: 1))
    }
}

/// Profile tab as MainTabView + ContentView compose it: the Profile list,
/// the mini player only if ContentView would show it on Profile, then the
/// tab bar.
private struct ProfileCanvas: View {
    @StateObject private var env = Build88Env()
    @State private var focus: ProfileStatFocus?
    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.Colors.backgroundGradient.ignoresSafeArea()
            ZStack(alignment: .bottom) {
                ProfileView(statFocus: $focus)
                LiquidTabBar(selectedTab: .constant(.profile))
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, 20)
            }
            .ignoresSafeArea()
            if ContentView.showsMiniPlayer(on: .profile) {
                // Stand-in for the mini player shelf (never drawn after the fix).
                Capsule().fill(Color.red.opacity(0.6)).frame(height: 64).padding(.horizontal, 16).padding(.bottom, 92)
            }
        }
        .environmentObject(env.auth)
        .environmentObject(env.apple)
        .environmentObject(env.sources)
        .environmentObject(env.analyzer)
        .environmentObject(env.audio)
        .environmentObject(env.api)
        .environmentObject(ThemeManager.shared)
        .environmentObject(SubscriptionManager.shared)
    }
}

private final class Build88Env: ObservableObject {
    let auth = SpotifyAuthManager()
    let apple = AppleMusicService()
    lazy var sources = MusicSourceManager(spotifyAuth: auth, appleMusic: apple)
    lazy var analyzer = AIProfileAnalyzer(appleMusicService: apple)
    let audio = AudioPreviewManager()
    let api = SpotifyAPIService()
}

/// RaritySheet exactly as it shipped in build 88 (pre-fix), for the
/// "before" captures.
struct RaritySheetLegacy: View {
    let rarity: ArtistRarity
    let trackName: String

    var body: some View {
        // Native sheet + system drag indicator: a custom grabber inside the
        // VStack was clipped (or sat above the visible area) whenever the
        // sheet sat between detents / was only partially raised. The system
        // indicator is drawn by UIKit above the clipped content, so it stays
        // visible at every detent. Extra top padding keeps the title clear
        // of the indicator.
        VStack(spacing: 20) {
            // Tier header
            VStack(spacing: 8) {
                Text(rarity.tier.label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(rarity.tier.tagline)
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            // Rarity score meter
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(rarity.score)")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("/ 100")
                        .font(.title3)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Text("RARITY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .tracking(4)

                // Meter bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(rarityGradient)
                            .frame(width: geo.size.width * CGFloat(rarity.score) / 100, height: 12)
                    }
                }
                .frame(height: 12)

                Text(String(format: "Rarer than %.1f%% of artists on Spotify", rarity.rarerThanPercent))
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            Divider().background(Color.white.opacity(0.1))

            // Stat rows
            VStack(spacing: 14) {
                if let followers = rarity.formattedFollowers {
                    statRow(label: "Spotify followers", value: followers)
                }
                if let popularity = rarity.popularity {
                    statRow(label: "Spotify popularity", value: "\(popularity)/100")
                }
                if let listeners = rarity.lastFmListeners {
                    statRow(label: "Last.fm listeners", value: formatNumber(listeners))
                }
                if let plays = rarity.lastFmPlaycount {
                    statRow(label: "Last.fm plays", value: formatNumber(plays))
                }
                if !rarity.genres.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Genres", systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text(rarity.genres.prefix(6).joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)   // clear of the system drag indicator
        .padding(.bottom, 24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var rarityGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.Colors.lavender, Theme.Colors.pink, Theme.Colors.peach],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
#endif
