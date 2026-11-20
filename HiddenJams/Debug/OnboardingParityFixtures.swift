//
//  OnboardingParityFixtures.swift
//  HiddenJams
//
//  DEBUG ONLY. Fixture data and a scripted clock so the parity snapshot
//  test can render the after-sign-in screens without a real library, using
//  the prototype's demo timeline (screens/Analyze.tsx `T`) and demo numbers
//  (demo.ts; rarity moved to 72 so it sits in the app's RARE tier).
//  Artwork is the bundled original covers (`obcover://` URLs resolve to
//  asset images in DEBUG only). Nothing here ships in Release.
//

#if DEBUG
import SwiftUI

enum OnboardingParityFixtures {
    static let picks: Set<String> = ["soul", "jazz", "funk", "ambient"]

    static let loadingGenres = ["soul", "jazz", "funk", "indie", "ambient", "folk", "electronic", "blues", "latin", "alternative"]

    static func profile(empty: Bool = false) -> TasteProfile {
        var p = TasteProfile()
        if empty { p.librarySize = 0; return p }
        p.librarySize = 1284
        p.topGenres = [.init(genre: "soul", share: 0.34), .init(genre: "jazz", share: 0.22),
                       .init(genre: "funk", share: 0.14), .init(genre: "indie", share: 0.11),
                       .init(genre: "ambient", share: 0.08)]
        p.rarityScore = 72
        p.ratedArtistCount = 23
        p.signatureArtists = [
            .init(name: "Tierra Swim", imageURL: URL(string: "obcover://mesa"), savedSongs: 31),
            .init(name: "Sela Moon", imageURL: URL(string: "obcover://rosewater"), savedSongs: 24),
            .init(name: "Ilse Marrow", imageURL: URL(string: "obcover://orbit"), savedSongs: 19),
        ]
        p.deepestCut = .init(title: "Morning Glass", artistName: "Imani Rae", artworkURL: URL(string: "obcover://glass"),
                             appleArtwork: nil, artistListeners: 412, userPlayCount: nil, rarityScore: 97)
        return p
    }

    // MARK: Prototype loading timeline (ms)

    private static let conn = 450.0, art = (450.0, 1900.0), songs = (1900.0, 3700.0), gen = (3700.0, 6000.0)
    private static let rar = (6000.0, 7300.0), deep = (7300.0, 8300.0), end = 8900.0

    private static func prog(_ t: Double, _ r: (Double, Double)) -> Double { max(0, min(1, (t - r.0) / (r.1 - r.0))) }
    private static func st(_ t: Double, _ a: Double, _ b: Double) -> TasteProfileFlowModel.LineState {
        t >= b ? .done : t >= a ? .run : .wait
    }

    /// Drives `model` exactly like Analyze.tsx until cancelled.
    static func runLoadingClock(_ model: TasteProfileFlowModel, apple: Bool, empty: Bool) async {
        let start = Date()
        while !Task.isCancelled {
            let t = Date().timeIntervalSince(start) * 1000
            apply(t, model, apple: apple, empty: empty)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    static func apply(_ t: Double, _ model: TasteProfileFlowModel, apple: Bool, empty: Bool) {
        typealias L = TasteProfileFlowModel.StageLine
        let svc = apple ? "Apple Music" : "Spotify"
        let endT = empty ? 4300.0 : end
        var lines: [L] = [
            L(stage: .connected, text: "Connected to \(svc)", state: t >= conn ? .done : .run),
            L(stage: .artists, text: apple ? "Finding the artists you play most" : "Pulling in your top artists",
              value: t >= art.0 ? (prog(t, art) * 50).rounded() : nil, state: st(t, art.0, art.1)),
            L(stage: .songs, text: apple ? "Reading your library" : "Reading your saved songs",
              value: t >= songs.0 ? (empty ? 0 : (prog(t, songs) * 1284).rounded()) : nil,
              state: empty ? (t >= 3000 ? .done : st(t, 1900, 3000)) : st(t, songs.0, songs.1)),
        ]
        if !empty {
            lines += [
                L(stage: .genres, text: "Sorting your genres", state: st(t, gen.0, gen.1)),
                L(stage: .rarity, text: "Checking how rare it all is",
                  value: t >= rar.0 ? (prog(t, rar) * 72).rounded() : nil, outOf100: true, state: st(t, rar.0, rar.1)),
                L(stage: .deepest, text: "Finding your deepest cut", state: st(t, deep.0, deep.1)),
            ]
        }
        let filled = Int((prog(t, gen) * (Double(loadingGenres.count) + 0.4)).rounded(.down))
        // Empty variant: the quiet line shows once songs land (t > 3000).
        model.apply(lines: lines, progress: min(1, t / endT), cloudGenres: empty ? [] : loadingGenres,
                    filledCount: filled, isEmptyLibrary: empty, profile: nil, isFinished: false)
    }

    // MARK: Screens

    /// Every parity state by name (the prototype capture names).
    @ViewBuilder
    static func screen(_ name: String) -> some View {
        let ordered = TasteCopy.orderedPicks(picks)
        switch name {
        case "01-intro": OnboardingView(debugStartPage: 0, picks: [])
        case "02-keep": OnboardingView(debugStartPage: 1, picks: [])
        case "03-rarity": OnboardingView(debugStartPage: 2, picks: [])
        case "04a-mood-none": OnboardingView(debugStartPage: 3, picks: [])
        case "04-mood": OnboardingView(debugStartPage: 3, picks: picks)
        case "05-connect": OnboardingView(debugStartPage: 4, picks: picks)
        case "06-loading", "06-loading-apple", "06-loading-empty":
            let apple = name.hasSuffix("apple"), empty = name.hasSuffix("empty")
            TasteProfileFlowContent(model: TasteProfileFlowModel(), picks: ordered, onFinish: {},
                                    start: { m in await runLoadingClock(m, apple: apple, empty: empty) },
                                    autoReveal: false)
        case "07-genres": reveal(page: 0, picks: ordered)
        case "08-rarity": reveal(page: 1, picks: ordered)
        case "09-artists": reveal(page: 2, picks: ordered)
        case "10-deepest": reveal(page: 3, picks: ordered, spotify: false)
        case "10-deepest-spotify": reveal(page: 3, picks: ordered, spotify: true)
        case "10-deepest-nopicks": reveal(page: 3, picks: [], spotify: false)
        case "11-fresh": reveal(page: 0, picks: ordered, empty: true)
        case "11-fresh-nopicks": reveal(page: 0, picks: [], empty: true)
        case "probe-font": Text("Most music").font(OBFont.cabinet(.black, 60)).foregroundStyle(.white)
        case "probe-title": OBMetricsReader { OBDisplayTitle(markup: "Most music\n[heard.]", size: 61.9) }
        case "probe-cover": OBCover(art: "obcover-mesa", size: 120, radius: 16)
        case "probe-glow": OBGlowBackground(screen: 0)
        case "probe-marquee": OBMarquee(items: OBCatalog.tracks, cover: 70, radius: 14, duration: 38)
        case "probe-sub": OBMetricsReader { OBSub(text: "Swipe right to save a song to your **Hidden Jams** playlist.") }
        case "probe-cta": OBNextButton {}.padding()
        case "probe-dots": OBPageDots(count: 5, index: 0)
        case "probe-spotify": OBBrandTile(brand: .spotify)
        case "probe-apple": OBBrandTile(brand: .appleMusic)
        case "probe-intro": OBMetricsReader { OBIntroScreen() }
        default: Color.red
        }
    }

    private static func reveal(page: Int, picks: [String], empty: Bool = false, spotify: Bool? = nil) -> some View {
        let p = profile(empty: empty)
        return TasteProfileFlowContent(
            model: TasteProfileFlowModel(lines: [], progress: 1, cloudGenres: [], filledCount: 0,
                                         isEmptyLibrary: empty, profile: p, isFinished: true),
            picks: picks, onFinish: {}, start: nil, revealAt: page, autoReveal: false,
            deepestSpotifyOverride: spotify)
    }
}
#endif
