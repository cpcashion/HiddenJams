//
//  TasteProfileFlowView.swift
//  HiddenJams
//
//  Onboarding v5, after sign-in: "Digging through your library…" loading
//  sequence (screen 6) followed by the reveal chapters (7-10, or 11 for an
//  empty library). Shown by ContentView once a service connects and
//  onboarding isn't complete; `onFinish` fires only on "Start digging".
//

import SwiftUI

struct TasteProfileFlowView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var sourceManager: MusicSourceManager
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @EnvironmentObject var apiService: SpotifyAPIService
    @EnvironmentObject var appleMusicService: AppleMusicService

    let onFinish: () -> Void

    @StateObject private var model = TasteProfileFlowModel()
    @State private var revealing = false
    @State private var page = 0

    private enum Chapter: Hashable { case genres, rarity, signature, deepest, fresh }

    /// Onboarding picks in onboarding order.
    private var picks: [String] {
        let set = GenreCatalog.loadSelected() ?? []
        return GenreCatalog.onboardingOrder.filter { set.contains($0) }
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

    var body: some View {
        ZStack {
            Theme.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                if revealing {
                    TabView(selection: $page) {
                        ForEach(Array(chapters.enumerated()), id: \.offset) { i, chapter in
                            chapterView(chapter).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .transition(.opacity)

                    let last = page >= chapters.count - 1
                    OnboardingNextButton(title: last ? "Start digging" : "Next") {
                        if last { onFinish() } else { withAnimation { page += 1 } }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                } else {
                    TasteLoadingView(model: model)
                    OnboardingNextButton(enabled: model.isFinished) { reveal() }
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
        }
        .task {
            await model.run(sources: sourceManager.connectedSources,
                            spotifyToken: authManager.accessToken,
                            analyzer: profileAnalyzer,
                            spotifyAPI: apiService,
                            appleMusic: appleMusicService)
            // Auto-advance shortly after the last line lands.
            try? await Task.sleep(for: .milliseconds(900))
            reveal()
        }
    }

    private func reveal() {
        guard model.isFinished, !revealing else { return }
        withAnimation(.easeInOut(duration: 0.4)) { revealing = true }
    }

    @ViewBuilder
    private func chapterView(_ chapter: Chapter) -> some View {
        if let p = model.profile {
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
}

// MARK: - 6 · Digging through your library

struct TasteLoadingView: View {
    @ObservedObject var model: TasteProfileFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HighlightedHeadline(text: "Digging through your library.", highlight: "library.")
                .padding(.top, 28)

            ring
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.lines) { line in
                    HStack(spacing: 10) {
                        Group {
                            if line.done {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.lime)
                            } else {
                                ProgressView().controlSize(.small).tint(Theme.Colors.lime)
                            }
                        }
                        .frame(width: 18)
                        Text(line.text)
                            .font(.system(size: 15, weight: line.done ? .regular : .semibold))
                            .foregroundStyle(line.done ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        Spacer()
                        if let count = line.count {
                            Text(count).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .contentTransition(.numericText())
                        }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                }
                if model.isSlow {
                    Text("Big library. Still reading…")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.leading, 28)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: model.lines)

            if !model.filledGenres.isEmpty {
                GenrePillsRow(genres: model.filledGenres)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .onChange(of: model.lines.filter(\.done).count) {
            if let last = model.lines.last(where: \.done) {
                AccessibilityNotification.Announcement(last.text + (last.count.map { ", \($0)" } ?? "")).post()
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.Colors.chipFill, lineWidth: 10)
            if !reduceMotion {
                Circle().trim(from: 0, to: model.progress)
                    .stroke(Theme.Colors.lime, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: model.progress)
            }
            Text("\(Int((model.progress * 100).rounded()))%")
                .font(.system(size: 30, weight: .heavy)).monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(width: 130, height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading your library, \(Int((model.progress * 100).rounded())) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("6 · Loading") {
    let model = TasteProfileFlowModel(
        previewLines: [
            .init(stage: .connected, text: "Connected to Spotify", count: nil, done: true),
            .init(stage: .artists, text: "Pulling in your top artists", count: "50", done: true),
            .init(stage: .songs, text: "Reading your saved songs", count: "1,284", done: true),
            .init(stage: .genres, text: "Sorting your genres", count: nil, done: false)
        ],
        progress: 0.55,
        genres: ["soul", "jazz", "funk"]
    )
    return ZStack {
        Theme.Colors.backgroundGradient.ignoresSafeArea()
        TasteLoadingView(model: model)
    }
    .preferredColorScheme(.dark)
}
