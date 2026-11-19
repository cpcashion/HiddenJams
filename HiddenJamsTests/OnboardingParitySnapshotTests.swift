//
//  OnboardingParitySnapshotTests.swift
//  HiddenJamsTests
//
//  TOOLING ONLY (branch tooling/onboarding-screenshots, never merged).
//  Renders every onboarding v5 screen in the hosted app's real window on the
//  CI iPhone 16 Pro simulator (402x874 pt) and prints each frame as base64
//  to the test log (this repo's CI token can't add an artifact workflow).
//  Settled frames: PNG @3x (1206x2622). Motion frames: JPEG @1.5x.
//  Decode on the box with design-research/onboarding-v5/parity/decode.py.
//

import XCTest
import SwiftUI
import UIKit
@testable import HiddenJams

@MainActor
final class OnboardingParitySnapshotTests: XCTestCase {

    private var window: UIWindow {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first!.windows.first!
    }

    private func show<V: View>(_ view: V) {
        let auth = SpotifyAuthManager()
        let apple = AppleMusicService()
        let root = view
            .environmentObject(auth)
            .environmentObject(apple)
            .environmentObject(MusicSourceManager(spotifyAuth: auth, appleMusic: apple))
            .environmentObject(ThemeManager.shared)
            .preferredColorScheme(.dark)
        let hc = UIHostingController(rootView: AnyView(root))
        hc.overrideUserInterfaceStyle = .dark
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = hc
        window.makeKeyAndVisible()
    }

    private func spin(until t: Date) { RunLoop.main.run(until: t) }

    private func emit(_ name: String, settled: Bool) {
        let w = window
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = settled ? 3 : 1.5
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(bounds: w.bounds, format: fmt).image { _ in
            _ = w.drawHierarchy(in: w.bounds, afterScreenUpdates: true)
        }
        let data = settled ? img.pngData()! : img.jpegData(compressionQuality: 0.8)!
        let file = name + (settled ? ".png" : ".jpg")
        let b64 = data.base64EncodedString()
        print("HJSNAP-BEGIN \(file) \(data.count) \(Int(w.bounds.width))x\(Int(w.bounds.height))")
        var i = 0, idx = b64.startIndex
        while idx < b64.endIndex {
            let end = b64.index(idx, offsetBy: 6000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("HJSNAP|\(file)|\(i)|\(b64[idx..<end])")
            idx = end; i += 1
        }
        print("HJSNAP-END \(file) \(i)")
        fflush(stdout)
    }

    /// Shows `view`, then captures at each offset (seconds); the last is the settled PNG.
    private func capture<V: View>(_ name: String, _ times: [Double], _ view: @autoclosure () -> V) {
        show(view())
        let t0 = Date()
        for (k, t) in times.enumerated() {
            spin(until: t0.addingTimeInterval(t))
            let last = k == times.count - 1
            emit(last ? name : "\(name)_t\(String(format: "%05.2f", t))", settled: last)
        }
    }

    private func setPicks(_ picks: Set<String>) { GenreCatalog.saveOnboardingPicks(picks) }
    private let picks: Set<String> = ["soul", "jazz", "funk", "ambient"]

    private func intro(_ page: Int) -> some View {
        OnboardingSnapshotHooks.introPage = page
        return ZStack { OnboardingView(isPresented: .constant(true)) }
    }

    func testCaptureOnboardingParity() throws {
        print("HJSNAP-DEVICE \(UIDevice.current.name) \(UIScreen.main.bounds.size) scale=\(UIScreen.main.scale) safe=\(window.safeAreaInsets)")
        spin(until: Date().addingTimeInterval(2))

        // ---- before sign-in: the real OnboardingView ----
        setPicks([])
        capture("01-intro", [0.4, 0.8, 1.2, 1.6, 2.0, 2.6, 3.4, 6.0], intro(0))
        capture("02-keep", [0.5, 0.9, 1.1, 1.3, 1.5, 1.7, 1.9, 2.2, 2.6, 3.0, 3.5, 4.0, 5.0, 6.0, 7.5, 8.6], intro(1))
        capture("03-rarity", [0.3, 0.6, 0.9, 1.2, 1.6, 2.0, 2.6, 4.5], intro(2))
        capture("04a-mood-none", [0.3, 2.0], intro(3))
        setPicks(picks)
        capture("04-mood", [2.0], intro(3))
        capture("05-connect", [0.4, 1.2, 2.0, 3.5], intro(4))
        OnboardingSnapshotHooks.introPage = 0

        // ---- after sign-in (fixture data = prototype demo numbers) ----
        capture("06-loading", [0.3, 0.8, 1.5, 2.5, 3.4, 4.2, 5.2, 6.5, 7.8, 9.5],
                OnboardingSnapshotHarness(mode: "loading", apple: false, empty: false, page: 0))
        capture("06-loading-apple", [4.2, 9.5], OnboardingSnapshotHarness(mode: "loading", apple: true, empty: false, page: 0))
        capture("06-loading-empty", [1.0, 2.2, 4.5], OnboardingSnapshotHarness(mode: "loading", apple: false, empty: true, page: 0))
        capture("07-genres", [0.2, 0.5, 0.8, 3.0], OnboardingSnapshotHarness(mode: "reveal", apple: false, empty: false, page: 0))
        capture("08-rarity", [0.2, 0.5, 0.9, 3.0], OnboardingSnapshotHarness(mode: "reveal", apple: false, empty: false, page: 1))
        capture("09-artists", [0.3, 5.0], OnboardingSnapshotHarness(mode: "reveal", apple: false, empty: false, page: 2))
        capture("10-deepest", [0.3, 5.0], OnboardingSnapshotHarness(mode: "reveal", apple: false, empty: false, page: 3))
        capture("07-genres-apple", [3.0], OnboardingSnapshotHarness(mode: "reveal", apple: true, empty: false, page: 0))
        capture("08-rarity-apple", [3.0], OnboardingSnapshotHarness(mode: "reveal", apple: true, empty: false, page: 1))
        capture("10-deepest-apple", [5.0], OnboardingSnapshotHarness(mode: "reveal", apple: true, empty: false, page: 2))
        capture("11-fresh", [3.0], OnboardingSnapshotHarness(mode: "reveal", apple: false, empty: true, page: 0))
        setPicks([])
        capture("10-deepest-nopicks", [5.0], OnboardingSnapshotHarness(mode: "reveal", apple: false, empty: false, page: 3))
        capture("11-fresh-nopicks", [3.0], OnboardingSnapshotHarness(mode: "reveal", apple: false, empty: true, page: 0))
        print("HJSNAP-DONE")
    }
}

/// Mirrors TasteProfileFlowView's body (loading branch / revealing branch)
/// with fixture data instead of a live library read.
struct OnboardingSnapshotHarness: View {
    let mode: String
    let apple: Bool
    let empty: Bool
    @State var page: Int
    @State private var phase = 0

    private var picks: [String] {
        let set = GenreCatalog.loadSelected() ?? []
        return GenreCatalog.onboardingOrder.filter { set.contains($0) }
    }

    // MARK: fixture (same demo numbers as the prototype's demo.ts)

    private static func art(_ s: String) -> URL? { URL(string: "https://is1-ssl.mzstatic.com/image/thumb/\(s)/600x600bb.jpg") }
    private static let khruangbin = art("Music115/v4/17/67/2e/17672e3b-9d01-2d5e-9b43-38f44b40f654/656605145365.jpg")
    private static let cleo = art("Music125/v4/a4/d3/aa/a4d3aadc-014d-7cdc-5e8b-ec0dcf2bf12b/859734840785_cover.jpg")
    private static let nala = art("Music221/v4/e4/57/42/e45742d5-0ac5-a3a5-9840-a54b8648d182/0801061032432.png")
    private static let yazmin = art("Music112/v4/59/ef/d7/59efd742-7130-f3d1-a197-22651c7a7d3c/cover.jpg")

    private var profile: TasteProfile {
        var p = TasteProfile()
        p.topGenres = [.init(genre: "soul", share: 0.34), .init(genre: "jazz", share: 0.22),
                       .init(genre: "funk", share: 0.14), .init(genre: "indie", share: 0.11),
                       .init(genre: "ambient", share: 0.08)]
        p.rarityScore = 68
        p.ratedArtistCount = 23
        p.signatureArtists = apple ? [] : [
            .init(name: "Khruangbin", imageURL: Self.khruangbin, savedSongs: 31),
            .init(name: "Cleo Sol", imageURL: Self.cleo, savedSongs: 24),
            .init(name: "Nala Sinephro", imageURL: Self.nala, savedSongs: 19)]
        p.deepestCut = .init(title: "Morning Matters", artistName: "Yazmin Lacey", artworkURL: Self.yazmin,
                             appleArtwork: nil, artistListeners: 2_140, userPlayCount: apple ? 412 : nil, rarityScore: 94)
        p.librarySize = empty ? 0 : 1284
        p.sources = [apple ? .appleMusic : .spotify]
        return p
    }

    private enum Chapter: Hashable { case genres, rarity, signature, deepest, fresh }
    private var chapters: [Chapter] {   // same rules as TasteProfileFlowView.chapters
        let p = profile
        if p.isEmptyLibrary { return [.fresh] }
        var list: [Chapter] = []
        if p.topGenres.count >= 3 { list.append(.genres) }
        if p.rarityScore != nil { list.append(.rarity) }
        if !p.signatureArtists.isEmpty { list.append(.signature) }
        if p.deepestCut != nil { list.append(.deepest) }
        return list
    }

    // Loading phases at the prototype's timing (Analyze.tsx T table).
    private typealias L = TasteProfileFlowModel.StageLine
    private var phases: [(at: Double, model: TasteProfileFlowModel)] {
        let svc = apple ? "Apple Music" : "Spotify"
        let c = L(stage: .connected, text: "Connected to \(svc)", count: nil, done: false)
        let a = L(stage: .artists, text: apple ? "Finding the artists you play most" : "Pulling in your top artists", count: nil, done: false)
        let s = L(stage: .songs, text: apple ? "Reading your library" : "Reading your saved songs", count: nil, done: false)
        let g = L(stage: .genres, text: "Sorting your genres", count: nil, done: false)
        let r = L(stage: .rarity, text: "Checking how rare it all is", count: nil, done: false)
        let d = L(stage: .deepest, text: "Finding your deepest cut", count: nil, done: false)
        func done(_ l: L, _ n: String? = nil) -> L { var x = l; x.done = true; x.count = n; return x }
        let five = ["soul", "jazz", "funk", "indie", "ambient"]
        func m(_ lines: [L], _ p: Double, _ g: [String] = []) -> TasteProfileFlowModel {
            TasteProfileFlowModel(previewLines: lines, progress: p, genres: g)
        }
        if empty {
            return [(0, m([c], 0)), (0.6, m([done(c), a], 0.05)), (1.9, m([done(c), done(a, "0"), s], 0.21)),
                    (3.0, m([done(c), done(a, "0"), done(s, "0")], 1.0))]
        }
        return [
            (0.0, m([c], 0)),
            (0.45, m([done(c), a], 0.05)),
            (1.9, m([done(c), done(a, "50"), s], 0.21)),
            (3.7, m([done(c), done(a, "50"), done(s, "1,284"), g], 0.41)),
            (4.8, m([done(c), done(a, "50"), done(s, "1,284"), g], 0.41, Array(five.prefix(3)))),
            (6.0, m([done(c), done(a, "50"), done(s, "1,284"), done(g), r], 0.67, five)),
            (7.3, m([done(c), done(a, "50"), done(s, "1,284"), done(g), done(r, "68/100"), d], 0.82, five)),
            (8.3, m([done(c), done(a, "50"), done(s, "1,284"), done(g), done(r, "68/100"), done(d)], 1.0, five)),
        ]
    }

    var body: some View {
        ZStack {
            Theme.Colors.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                if mode == "reveal" {
                    TabView(selection: $page) {
                        ForEach(Array(chapters.enumerated()), id: \.offset) { i, chapter in
                            chapterView(chapter).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    let last = page >= chapters.count - 1
                    OnboardingNextButton(title: last ? "Start digging" : "Next") {
                        if !last { withAnimation { page += 1 } }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                } else {
                    let ph = phases
                    TasteLoadingView(model: ph[min(phase, ph.count - 1)].model)
                    OnboardingNextButton(enabled: phase >= ph.count - 1) {}
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
        }
        .task {
            guard mode != "reveal" else { return }
            let start = Date()
            let ph = phases
            for i in ph.indices {
                let wait = ph[i].at - Date().timeIntervalSince(start)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = i }
            }
        }
    }

    @ViewBuilder
    private func chapterView(_ chapter: Chapter) -> some View {
        let p = profile
        switch chapter {
        case .genres: TasteGenresChapter(genres: p.topGenres, picks: Set(picks))
        case .rarity: TasteRarityChapter(score: p.rarityScore ?? 0, ratedArtists: p.ratedArtistCount)
        case .signature: TasteSignatureChapter(artists: p.signatureArtists)
        case .deepest:
            if let cut = p.deepestCut { TasteDeepestCutChapter(cut: cut, picks: picks) }
        case .fresh: TasteFreshStartChapter(picks: picks)
        }
    }
}
