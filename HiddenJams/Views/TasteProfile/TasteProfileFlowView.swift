//
//  TasteProfileFlowView.swift
//  HiddenJams
//
//  Onboarding v5, after sign-in: "Digging through your library…" (screen 6)
//  then the reveal chapters (7-10, or 11 for an empty library), on the same
//  glow, dots and dock as the screens before sign-in. Shown by ContentView
//  once a service connects and onboarding isn't complete; `onFinish` fires
//  only on "Start digging".
//

import SwiftUI

struct TasteProfileFlowView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var sourceManager: MusicSourceManager
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @EnvironmentObject var apiService: SpotifyAPIService
    @EnvironmentObject var appleMusicService: AppleMusicService

    let onFinish: () -> Void

    var body: some View {
        TasteProfileFlowContent(
            model: TasteProfileFlowModel(),
            picks: TasteCopy.orderedPicks(GenreCatalog.loadSelected() ?? []),
            onFinish: onFinish,
            start: { model in
                await model.run(sources: sourceManager.connectedSources,
                                spotifyToken: authManager.accessToken,
                                analyzer: profileAnalyzer,
                                spotifyAPI: apiService,
                                appleMusic: appleMusicService)
            }
        )
    }
}

/// The flow's look and paging, fed by a model (the real library run, or a
/// DEBUG parity fixture).
struct TasteProfileFlowContent: View {
    enum Chapter: Hashable { case genres, rarity, signature, deepest, fresh

        /// The prototype's glow screen index.
        var glow: Int {
            switch self {
            case .genres: return 6
            case .rarity: return 7
            case .signature: return 8
            case .deepest: return 9
            case .fresh: return 10
            }
        }
    }

    @StateObject private var model: TasteProfileFlowModel
    let picks: [String]
    let onFinish: () -> Void
    let start: ((TasteProfileFlowModel) async -> Void)?
    var autoReveal = true
    var deepestSpotifyOverride: Bool? = nil

    @State private var revealing: Bool
    @State private var page: Int
    @State private var direction: CGFloat = 1

    init(model: @autoclosure @escaping () -> TasteProfileFlowModel, picks: [String], onFinish: @escaping () -> Void,
         start: ((TasteProfileFlowModel) async -> Void)?,
         revealAt page: Int? = nil, autoReveal: Bool = true, deepestSpotifyOverride: Bool? = nil) {
        _model = StateObject(wrappedValue: model())
        self.picks = picks
        self.onFinish = onFinish
        self.start = start
        self.autoReveal = autoReveal
        self.deepestSpotifyOverride = deepestSpotifyOverride
        _revealing = State(initialValue: page != nil)
        _page = State(initialValue: page ?? 0)
    }

    private var chapters: [Chapter] {
        guard let p = model.profile else { return [] }
        if p.isEmptyLibrary { return [.fresh] }
        var list: [Chapter] = []
        // Fewer than 3 genres: lead with rarity instead (spec §5.4).
        if p.topGenres.count >= 3 { list.append(.genres) }
        if p.rarityScore != nil { list.append(.rarity) }
        if !p.signatureArtists.isEmpty { list.append(.signature) }
        if p.deepestCut != nil { list.append(.deepest) }
        return list.isEmpty ? [.fresh] : list
    }

    private var current: Chapter? { revealing && chapters.indices.contains(page) ? chapters[page] : nil }

    var body: some View {
        OBMetricsReader {
            ZStack {
                OBGlowBackground(screen: current?.glow ?? 5)

                ZStack {
                    Group {
                        if let chapter = current {
                            chapterView(chapter).id("chapter-\(page)")
                        } else {
                            OBLoadingScreen(model: model).id("loading")
                        }
                    }
                    .transition(.obPage(direction))
                }
                .contentShape(Rectangle())
                .simultaneousGesture(swipe)

                dock
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard let start, !revealing else { return }
            await start(model)
            guard autoReveal else { return }
            // Auto-advance shortly after the last line lands.
            try? await Task.sleep(for: .milliseconds(600))
            reveal()
        }
    }

    @ViewBuilder
    private var dock: some View {
        if let chapter = current {
            let last = page >= chapters.count - 1
            let showDots = chapter != .fresh
            OBDock(dots: showDots ? (count: chapters.count, index: page) : nil) {
                OBNextButton(title: last ? "Start digging" : "Next") {
                    if last { onFinish() } else { go(page + 1) }
                }
            }
        } else {
            OBDock(dots: nil) {
                OBNextButton(enabled: model.isFinished) { reveal() }
            }
        }
    }

    private func reveal() {
        guard model.isFinished, !revealing else { return }
        direction = 1
        withAnimation(OB.pageSpring) { revealing = true }
    }

    private func go(_ n: Int) {
        let target = max(0, min(chapters.count - 1, n))
        guard target != page else { return }
        direction = target > page ? 1 : -1
        withAnimation(OB.pageSpring) { page = target }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { v in
                guard revealing else { return }
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) >= 70, abs(dy) <= 50 else { return }
                if dx < 0 { go(page + 1) } else { go(page - 1) }
            }
    }

    @ViewBuilder
    private func chapterView(_ chapter: Chapter) -> some View {
        if let p = model.profile {
            switch chapter {
            case .genres: OBGenresChapter(genres: p.topGenres, picks: Set(picks))
            case .rarity: OBRarityChapter(score: p.rarityScore ?? 0)
            case .signature:
                // Signature art is Spotify's unless the profile has no Spotify source.
                OBSignatureChapter(artists: p.signatureArtists,
                                   tilted: !p.sources.isEmpty && !p.sources.contains(.spotify))
            case .deepest:
                if let cut = p.deepestCut {
                    OBDeepestChapter(cut: cut, picks: picks,
                                     spotifyArt: deepestSpotifyOverride ?? (cut.appleArtwork == nil && cut.artworkURL != nil))
                }
            case .fresh: OBFreshChapter(picks: picks)
            }
        }
    }
}

#Preview("6 · Loading") {
    let model = TasteProfileFlowModel(
        lines: [
            .init(stage: .connected, text: "Connected to Spotify", state: .done),
            .init(stage: .artists, text: "Pulling in your top artists", count: "50", value: 50, state: .done),
            .init(stage: .songs, text: "Reading your saved songs", count: "1,284", value: 1284, state: .done),
            .init(stage: .genres, text: "Sorting your genres", state: .run),
            .init(stage: .rarity, text: "Checking how rare it all is", state: .wait),
            .init(stage: .deepest, text: "Finding your deepest cut", state: .wait),
        ],
        progress: 0.55, cloudGenres: ["soul", "jazz", "funk"], filledCount: 3)
    return TasteProfileFlowContent(model: model, picks: ["jazz", "soul"], onFinish: {}, start: nil)
}
