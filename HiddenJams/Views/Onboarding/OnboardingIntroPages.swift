//
//  OnboardingIntroPages.swift
//  HiddenJams
//
//  Onboarding v5, screens 1-5 (before sign-in). Copy is final per
//  design-research/onboarding-v5/PLAN.md §3. Every demo plays on its own;
//  nothing asks the user to perform a gesture. Reduce Motion shows the
//  end state without movement.
//

import SwiftUI

/// Common page frame: visual zone on top, copy pinned above the dots.
struct OnboardingPageLayout<Visual: View, Copy: View>: View {
    @ViewBuilder var visual: Visual
    @ViewBuilder var copy: Copy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            visual
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 14) { copy }
                .padding(.horizontal, 22)
        }
        // Room for the system page dots under the copy.
        .padding(.bottom, 52)
    }
}

// MARK: - 1 · Most music never gets heard

struct OnboardingStatPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var greyed = 0
    @State private var percent = 0
    @State private var drift = false

    /// Tile seeds + positions (fractions of the visual zone). Index 4 stays lit.
    private let tiles: [(seed: Int, x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0, 0.14, 0.22, 70), (1, 0.40, 0.12, 58), (2, 0.70, 0.18, 76),
        (3, 0.88, 0.42, 54), (4, 0.50, 0.46, 96), (5, 0.18, 0.56, 62),
        (6, 0.78, 0.72, 66), (7, 0.30, 0.82, 52), (8, 0.58, 0.86, 48)
    ]
    private let litIndex = 4
    private var greyOrder: [Int] { [0, 2, 7, 5, 1, 8, 3, 6] }

    var body: some View {
        OnboardingPageLayout {
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                        let isGrey = greyOrder.prefix(greyed).contains(i)
                        SampleCoverTile(seed: t.seed, size: t.size, desaturated: isGrey, lit: i == litIndex && greyed >= greyOrder.count)
                            .rotationEffect(.degrees(Double((t.seed * 7) % 13) - 6))
                            .offset(y: drift && !reduceMotion ? (i.isMultiple(of: 2) ? -6 : 6) : 0)
                            .position(x: geo.size.width * t.x, y: geo.size.height * t.y)
                            .animation(.easeInOut(duration: 0.5), value: isGrey)
                    }
                }
            }
            .padding(.top, 24)
            .accessibilityElement()
            .accessibilityLabel("Album covers fade to grey one by one; a single one stays lit.")
        } copy: {
            HighlightedHeadline(text: "Most music never gets heard.", highlight: "heard.")
            OnboardingBody(markdown: "**\(percent)%** of songs on streaming got 1,000 plays or fewer last year. Hidden Jams finds them.")
                .contentTransition(.numericText())
                .accessibilityLabel("88% of songs on streaming got 1,000 plays or fewer last year. Hidden Jams finds them.")
            OnboardingKicker(text: "Source: Luminate 2025 Year-End Music Report")
        }
        .task(id: isActive) {
            guard isActive else { return }
            if reduceMotion { greyed = greyOrder.count; percent = 88; return }
            greyed = 0; percent = 0
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { drift = true }
            for step in 1...22 {
                try? await Task.sleep(for: .milliseconds(90))
                if Task.isCancelled { return }
                withAnimation(.snappy) { percent = step * 4 }
                if step.isMultiple(of: 3), greyed < greyOrder.count { greyed += 1 }
            }
            greyed = greyOrder.count
        }
    }
}

// MARK: - 2 · Keep what moves you

struct OnboardingKeepDemoPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Action { case keep, skip }
    /// keep, skip, keep, keep, (pause), loop
    private let script: [Action] = [.keep, .skip, .keep, .keep]

    @State private var step = 0
    @State private var cardSeed = 0
    @State private var offsetX: CGFloat = 0
    @State private var stamp: Action?
    @State private var saved = 0

    private var nextAction: Action { script[step % script.count] }

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                ZStack {
                    SampleCoverTile(seed: cardSeed + 1, size: 210)
                        .rotationEffect(.degrees(-4))
                        .opacity(0.6)
                    demoCard
                        .offset(x: offsetX)
                        .rotationEffect(.degrees(Double(offsetX / 18)))
                }
                .frame(height: 250)

                // The instruction lives in its own row below the card so
                // the art can never cover it.
                OnboardingKicker(
                    text: nextAction == .keep ? "Swipe right to keep →" : "← Swipe left to skip",
                    color: Theme.Colors.lime
                )
                .animation(.easeInOut, value: step)

                playlistChip
                    .padding(.horizontal, 22)
                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Demo: a song card swipes right to keep and left to skip. Kept songs land in your Hidden Jams playlist.")
        } copy: {
            HighlightedHeadline(text: "Keep what moves you.", highlight: "moves")
            OnboardingBody(markdown: "Swipe right to save a song to your **Hidden Jams** playlist. Swipe left to skip.")
        }
        .task(id: isActive) {
            guard isActive else { return }
            if reduceMotion { saved = 3; return }
            step = 0; saved = 0; offsetX = 0; stamp = nil
            while !Task.isCancelled {
                for action in script {
                    try? await Task.sleep(for: .milliseconds(900))
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: 0.25)) { offsetX = action == .keep ? 40 : -40; stamp = action }
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.easeIn(duration: 0.35)) { offsetX = action == .keep ? 420 : -420 }
                    try? await Task.sleep(for: .milliseconds(380))
                    if action == .keep { withAnimation(.spring) { saved += 1 } }
                    cardSeed += 1; stamp = nil; offsetX = 0
                    step += 1
                }
                try? await Task.sleep(for: .milliseconds(1400))   // pause, then loop
                withAnimation { saved = 0 }
            }
        }
    }

    private var demoCard: some View {
        ZStack(alignment: .topLeading) {
            SampleCoverTile(seed: cardSeed, size: 210)
            OnboardingKicker(text: "Sample", color: Theme.Colors.textOnPastel)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.7)))
                .padding(12)
            if let stamp {
                Text(stamp == .keep ? "KEEP" : "SKIP")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(stamp == .keep ? Theme.Colors.textOnPastel : .white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(stamp == .keep ? Theme.Colors.lime : Theme.Colors.error))
                    .rotationEffect(.degrees(stamp == .keep ? -12 : 12))
                    .frame(width: 210, height: 210, alignment: stamp == .keep ? .topTrailing : .topLeading)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 210, height: 210)
    }

    private var playlistChip: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Colors.textOnPastel)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Colors.lavender))
            VStack(alignment: .leading, spacing: 2) {
                Text("Hidden Jams").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                Text("Playlist in your music app").font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Text("\(saved) saved")
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.numericText())
                .chipStyle(selected: true)
        }
        .padding(12)
        .surfaceCard(radius: 18)
    }
}

// MARK: - 3 · Fewer plays. Rarer finds.

struct OnboardingRarityPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    /// SAMPLE data (fictional songs and numbers, labelled on screen).
    private struct Row { let title: String; let artist: String; let plays: String; let score: Int; let tier: ArtistRarity.Tier }
    private let rows: [Row] = [
        // Scores use the app's real tier cut-offs (RarityService).
        Row(title: "Everywhere Tonight", artist: "Sample Chart Act", plays: "41.8M", score: 9, tier: .known),
        Row(title: "Paper Lanterns", artist: "Sample Artist", plays: "6.2M", score: 56, tier: .emerging),
        Row(title: "Slow Bloom", artist: "Sample Artist", plays: "480K", score: 74, tier: .rare),
        Row(title: "Second Window", artist: "Sample Artist", plays: "38K", score: 88, tier: .ultraRare),
        Row(title: "Basement Tape #4", artist: "Sample Artist", plays: "412", score: 97, tier: .mythic)
    ]

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 10) {
                Spacer(minLength: 8)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i < shown {
                        rowView(row, seed: i)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                Spacer(minLength: 0)
                OnboardingKicker(text: "Sample songs and numbers")
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sample: as play counts fall from 41.8 million to 412, the Rarity score climbs from 9 to 97.")
        } copy: {
            HighlightedHeadline(text: "Fewer plays. Rarer finds.", highlight: "Rarer finds.")
            OnboardingBody(markdown: "Every song gets a Rarity score. The less it's been heard, the higher it climbs.")
        }
        .task(id: isActive) {
            guard isActive else { return }
            if reduceMotion { shown = rows.count; return }
            shown = 0
            for i in 1...rows.count {
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = i }
            }
        }
    }

    private func rowView(_ row: Row, seed: Int) -> some View {
        HStack(spacing: 12) {
            SampleCoverTile(seed: seed + 3, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                Text(row.artist).font(.system(size: 12)).foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text(row.plays).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.Colors.textPrimary)
                Text("plays").font(.system(size: 10)).foregroundStyle(Theme.Colors.textTertiary)
            }
            VStack(spacing: 0) {
                Text("\(row.score)").font(.system(size: 17, weight: .heavy)).monospacedDigit()
                Text(row.tier.label).font(.system(size: 7, weight: .bold)).lineLimit(1)
            }
            .foregroundStyle(row.tier.ladderTextColor)
            .frame(width: 62, height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(row.tier.ladderColor))
        }
        .padding(10)
        .surfaceCard(radius: 14)
    }
}

// MARK: - 4 · In the mood for…

struct OnboardingMoodPage: View {
    @Binding var picks: Set<String>

    var body: some View {
        let colors = Theme.Colors.genreColors(for: Array(picks))
        VStack(alignment: .leading, spacing: 14) {
            HighlightedHeadline(text: "In the mood for…", highlight: "mood")
                .padding(.top, 28)
            OnboardingBody(markdown: "Pick a few and we'll dig there first. Change them any time.")
            ScrollView(showsIndicators: false) {
                FlowLayout(spacing: 8) {
                    ForEach(GenreCatalog.onboardingOrder, id: \.self) { genre in
                        let selected = picks.contains(genre)
                        Button { toggle(genre) } label: {
                            GenrePillContent(genre: genre, isSelected: selected,
                                             pillColor: colors[genre] ?? Theme.Colors.gemGold)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            OnboardingKicker(text: picks.isEmpty ? "Skipping is fine · we'll mix it up"
                                                 : "\(picks.count) picked · we'll start there")
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 52)
    }

    private func toggle(_ genre: String) {
        if picks.contains(genre) { picks.remove(genre) } else { picks.insert(genre) }
        // Persist on every toggle so a force-quit mid-onboarding keeps it.
        GenreCatalog.saveOnboardingPicks(picks)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - 5 · Find what the big apps won't play.

struct OnboardingConnectPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 12) {
                marqueeRow(seedOffset: 0, speed: 18, reversed: false)
                marqueeRow(seedOffset: 5, speed: 24, reversed: true)
            }
            .padding(.top, 36)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
        } copy: {
            HighlightedHeadline(text: "Find what the big apps won't play.", highlight: "won't")
            OnboardingBody(markdown: "Streaming pushes what's trending and promoted. Connect your music and we'll dig up what you'd never hear otherwise.")
            OnboardingKicker(text: "We only save songs you keep.")
        }
    }

    private func marqueeRow(seedOffset: Int, speed: Double, reversed: Bool) -> some View {
        let tile: CGFloat = 76, gap: CGFloat = 12, count = 10
        let span = (tile + gap) * CGFloat(count)
        return TimelineView(.animation(paused: reduceMotion || !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let shift = CGFloat((t * speed).truncatingRemainder(dividingBy: Double(span)))
            HStack(spacing: gap) {
                ForEach(0..<(count * 2), id: \.self) { i in
                    SampleCoverTile(seed: seedOffset + i % count, size: tile)
                }
            }
            .offset(x: reversed ? shift - span : -shift)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: tile)
        .clipped()
    }
}

// MARK: - Previews

private struct IntroPreview<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack { Theme.Colors.backgroundGradient.ignoresSafeArea(); content }
            .preferredColorScheme(.dark)
    }
}

#Preview("1 · Stat") { IntroPreview { OnboardingStatPage(isActive: true) } }
#Preview("2 · Keep") { IntroPreview { OnboardingKeepDemoPage(isActive: true) } }
#Preview("3 · Rarity") { IntroPreview { OnboardingRarityPage(isActive: true) } }
#Preview("4 · Mood") { IntroPreview { OnboardingMoodPage(picks: .constant(["soul", "jazz", "funk"])) } }
#Preview("5 · Connect") { IntroPreview { OnboardingConnectPage(isActive: true) } }
