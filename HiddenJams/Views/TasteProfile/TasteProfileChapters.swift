//
//  TasteProfileChapters.swift
//  HiddenJams
//
//  Onboarding v5 screens 7-11: the taste-profile reveal. Plain-data views
//  (no environment) so each has a #Preview. All numbers come from the
//  user's real library via TasteProfileFlowModel.
//

import SwiftUI
import MusicKit

enum TasteCopy {
    /// Genre as it reads inside a sentence ("soul", "R&B", "K-pop").
    static func inline(_ genre: String) -> String {
        switch genre.lowercased() {
        case "r&b": return "R&B"
        case "k-pop": return "K-pop"
        default: return genre.lowercased()
        }
    }

    static func compact(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }
}

/// Shared chapter frame: kicker, headline, content, body, room for dots.
private struct ChapterLayout<Content: View>: View {
    let kicker: String
    let title: String
    let highlight: String?
    var bodyText: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingKicker(text: kicker)
                .padding(.top, 28)
            HighlightedHeadline(text: title, highlight: highlight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let bodyText { OnboardingBody(markdown: bodyText) }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 52)
    }
}

// MARK: - 7 · Genres

struct TasteGenresChapter: View {
    let genres: [TasteProfile.GenreShare]
    let picks: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grow = false

    private var title: String {
        let names = genres.prefix(2).map { TasteCopy.inline($0.genre) }
        return names.count == 2 ? "You dig \(names[0]) and \(names[1])." : "You dig \(names.first ?? "a bit of everything")."
    }

    var body: some View {
        let colors = Theme.Colors.genreColors(for: genres.map(\.genre))
        let maxShare = genres.map(\.share).max() ?? 1
        ChapterLayout(kicker: "Your sound", title: title, highlight: genres.first.map { TasteCopy.inline($0.genre) },
                      bodyText: "That's most of your library. We'll still dig for the unexpected.") {
            VStack(spacing: 14) {
                ForEach(genres, id: \.genre) { g in
                    HStack(spacing: 12) {
                        GenrePillContent(genre: g.genre, isSelected: true, pillColor: colors[g.genre] ?? Theme.Colors.lime)
                            .frame(width: 128, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack {
                                if picks.contains(g.genre) { OnboardingKicker(text: "Your pick", color: Theme.Colors.lime) }
                                Spacer()
                                Text("\(Int((g.share * 100).rounded()))%")
                                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            GeometryReader { geo in
                                Capsule().fill(Theme.Colors.chipFill)
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(colors[g.genre] ?? Theme.Colors.lime)
                                            .frame(width: geo.size.width * (grow ? g.share / maxShare : 0))
                                    }
                            }
                            .frame(height: 8)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(g.genre.capitalized), \(Int((g.share * 100).rounded())) percent\(picks.contains(g.genre) ? ", your pick" : "")")
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            if reduceMotion { grow = true } else { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { grow = true } }
        }
    }
}

// MARK: - 8 · Rarity score

struct TasteRarityChapter: View {
    let score: Int
    let ratedArtists: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: Double = 0

    private var tier: ArtistRarity.Tier { TasteRarity.tier(forScore: score) }

    private var title: (String, String) {
        switch tier {
        case .mythic: return ("Your taste runs mythic.", "mythic.")
        case .ultraRare: return ("Your taste runs ultra rare.", "ultra rare.")
        case .rare: return ("Your taste runs rare.", "rare.")
        case .emerging: return ("Your taste is on the rise.", "on the rise.")
        case .known: return ("Your taste runs familiar.", "familiar.")
        }
    }

    private var bodyText: String {
        switch tier {
        case .known: return "**Plenty of rare finds ahead.** Let's go deeper."
        case .emerging: return "**On the rise.** You already lean off the charts. Let's go deeper."
        default:
            let tag = tier.tagline
            return "**\(tag.prefix(1).uppercased() + tag.dropFirst()).** You already listen well off the charts. Let's go deeper."
        }
    }

    var body: some View {
        ChapterLayout(kicker: "Your rarity", title: title.0, highlight: title.1, bodyText: bodyText) {
            VStack(spacing: 22) {
                ZStack {
                    Circle().stroke(Theme.Colors.chipFill, lineWidth: 14)
                    Circle().trim(from: 0, to: fill)
                        .stroke(Theme.Colors.lime, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(score)").font(.system(size: 60, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("/ 100").font(.system(size: 14)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(width: 180, height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rarity score \(score) out of 100, \(tier.label.lowercased())")

                HStack(spacing: 6) {
                    ForEach(ArtistRarity.Tier.ladder, id: \.self) { t in
                        VStack(spacing: 6) {
                            Capsule().fill(t == tier ? t.ladderColor : Theme.Colors.chipFill).frame(height: 6)
                            Text(t.label).font(.system(size: 8, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(t == tier ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        }
                    }
                }
                .accessibilityHidden(true)

                OnboardingKicker(text: "From Last.fm listeners for \(ratedArtists) of your top artists")
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            let target = Double(score) / 100
            if reduceMotion { fill = target } else { withAnimation(.easeOut(duration: 1.2)) { fill = target } }
        }
    }
}

// MARK: - 9 · Signature artists (Spotify only)

struct TasteSignatureChapter: View {
    let artists: [TasteProfile.SignatureArtist]

    var body: some View {
        ChapterLayout(kicker: "Your artists", title: "Your signature artists.", highlight: "signature",
                      bodyText: "The ones you keep coming back to.") {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(artists.enumerated()), id: \.offset) { i, a in
                    VStack(spacing: 8) {
                        AsyncImage(url: a.imageURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            SampleCoverTile(seed: i, size: 100)
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(a.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if a.savedSongs > 0 {
                            OnboardingKicker(text: "\(a.savedSongs) saved song\(a.savedSongs == 1 ? "" : "s")")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - 10 · Deepest cut

struct TasteDeepestCutChapter: View {
    let cut: TasteProfile.DeepCut
    let picks: [String]

    var body: some View {
        ChapterLayout(kicker: "Your deepest cut", title: "Your deepest cut.", highlight: "deepest",
                      bodyText: "Hardly anyone has heard it. You have.") {
            VStack(spacing: 12) {
                artwork
                    .frame(width: 190, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                if let listeners = cut.artistListeners {
                    Text("\(TasteCopy.compact(listeners)) listeners on Last.fm")
                        .font(.system(size: 13, weight: .bold))
                        .chipStyle(selected: true)
                }
                VStack(spacing: 2) {
                    Text(cut.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                    Text(cut.artistName).font(.system(size: 14)).foregroundStyle(Theme.Colors.textSecondary)
                    if let plays = cut.userPlayCount {
                        OnboardingKicker(text: "You've played it \(plays) time\(plays == 1 ? "" : "s")").padding(.top, 4)
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                StartingWithRow(picks: picks).padding(.top, 6)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder private var artwork: some View {
        if let art = cut.appleArtwork {
            ArtworkImage(art, width: 190, height: 190)
        } else {
            AsyncImage(url: cut.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                SampleCoverTile(seed: 2, size: 190)
            }
        }
    }
}

/// "Starting with" + the onboarding picks (or "a bit of everything").
struct StartingWithRow: View {
    let picks: [String]

    var body: some View {
        VStack(spacing: 8) {
            OnboardingKicker(text: "Starting with")
            if picks.isEmpty {
                Text("a bit of everything").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.Colors.textSecondary)
            } else {
                GenrePillsRow(genres: picks)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 11 · Fresh start (empty / tiny library)

struct TasteFreshStartChapter: View {
    let picks: [String]

    var body: some View {
        ChapterLayout(kicker: "Empty library", title: "Fresh start.", highlight: "start.",
                      bodyText: "Nothing saved yet, so we'll start from what you picked. Keep a few songs and your taste profile fills in on its own.") {
            StartingWithRow(picks: picks)
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Previews (sample data, previews only)

private struct ChapterPreview<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack { Theme.Colors.backgroundGradient.ignoresSafeArea(); content }
            .preferredColorScheme(.dark)
    }
}

#Preview("7 · Genres") {
    ChapterPreview {
        TasteGenresChapter(genres: [.init(genre: "soul", share: 0.34), .init(genre: "jazz", share: 0.22),
                                    .init(genre: "funk", share: 0.14), .init(genre: "indie", share: 0.11),
                                    .init(genre: "ambient", share: 0.08)],
                           picks: ["soul", "ambient"])
    }
}
#Preview("8 · Rarity") { ChapterPreview { TasteRarityChapter(score: 72, ratedArtists: 23) } }
#Preview("9 · Signature artists") {
    ChapterPreview {
        TasteSignatureChapter(artists: [.init(name: "Preview Artist One", imageURL: nil, savedSongs: 31),
                                        .init(name: "Preview Two", imageURL: nil, savedSongs: 24),
                                        .init(name: "Preview Three", imageURL: nil, savedSongs: 19)])
    }
}
#Preview("10 · Deepest cut") {
    ChapterPreview {
        TasteDeepestCutChapter(cut: .init(title: "Preview Song", artistName: "Preview Artist", artworkURL: nil,
                                          appleArtwork: nil, artistListeners: 2_140, userPlayCount: 37, rarityScore: 94),
                               picks: ["ambient", "funk", "hip hop"])
    }
}
#Preview("11 · Fresh start") { ChapterPreview { TasteFreshStartChapter(picks: ["ambient", "funk", "jazz", "soul"]) } }
