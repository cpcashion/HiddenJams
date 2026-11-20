//
//  OBTasteScreens.swift
//  HiddenJams
//
//  Onboarding v5 after sign-in, built to the prototype's source
//  (screens/Analyze + screens/Reveal + styles.css): the "Digging through
//  your library" sequence and the taste-profile reveal. Every number comes
//  from the user's library (TasteProfileFlowModel).
//
//  Spotify artwork (signature artists, a Spotify deepest cut) is shown
//  upright and unaltered apart from resizing and 8pt corners, per Spotify's
//  artwork rules; everything around it, and Apple Music artwork, keeps the
//  prototype's tilted layout.
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

    /// Onboarding picks in a stable order (the `selectedGenres` contract is
    /// an unordered set): alphabetical.
    static func orderedPicks(_ picks: Set<String>) -> [String] { picks.map { $0.lowercased() }.sorted() }
}

// MARK: - Artwork

/// Remote artwork (Spotify) drawn upright: resize + corner radius only.
struct OBRemoteArt: View {
    let url: URL?
    var body: some View {
        #if DEBUG
        if let url, url.scheme == "obcover", let host = url.host() {
            Image("obcover-" + host).resizable().aspectRatio(contentMode: .fill)
        } else {
            remote
        }
        #else
        remote
        #endif
    }
    private var remote: some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            OB.cell
        }
    }
}

// MARK: - 06 · Digging through your library

struct OBLoadingScreen: View {
    @ObservedObject var model: TasteProfileFlowModel
    @Environment(\.obMetrics) private var m

    var body: some View {
        let t = OBCatalog.tracks
        let r1 = Array(t[0..<9]), r2 = Array(t[3...] + t[0..<3]), r3 = Array(t[6...] + t[0..<6])
        OBScreen {
            Group {
                if model.isEmptyLibrary {
                    OBDisplayTitle(markup: "Looking\naround…", size: m.displayM)
                } else {
                    OBDisplayTitle(markup: "Digging through\nyour [library.]", size: m.displayM)
                }
            }
            .obRise(0.05)

            ZStack {
                VStack(spacing: 10) {
                    OBMarquee(items: r1, cover: 54, radius: 12, duration: 30).opacity(0.5)
                    OBMarquee(items: r2, cover: 54, radius: 12, duration: 38, reverse: true).opacity(0.5)
                    OBMarquee(items: r3, cover: 54, radius: 12, duration: 26).opacity(0.5)
                }
                OBLoadingRing(progress: model.progress, animated: model.animatesCounts)
            }
            .frame(width: m.width, height: 188)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                         .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .padding(.horizontal, -OB.pad)
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(model.lines) { line in
                    OBStageRow(line: line, animated: model.animatesCounts)
                }
                if model.isSlow {
                    Text("Big library. Still reading…")
                        .font(.system(size: 13)).foregroundStyle(OB.paper).opacity(0.5)
                        .padding(.leading, 28)
                }
            }
            .padding(.top, 14)

            if model.isEmptyLibrary {
                OBSub(text: "Your library’s quiet, so we’ll start fresh from your picks.")
                    .padding(.top, 20)
                    .opacity(model.lines.first(where: { $0.stage == .songs })?.done == true ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: model.lines)
            } else {
                let colors = Theme.Colors.genreColors(for: model.cloudGenres)
                OBFlow(spacing: 7) {
                    ForEach(Array(model.cloudGenres.enumerated()), id: \.element) { i, g in
                        OBGenrePill(genre: g, on: i < model.filledCount, color: colors[g] ?? OB.lime, compact: true)
                            .animation(.easeInOut(duration: 0.35), value: model.filledCount)
                    }
                }
                .padding(.top, 16)
            }
        }
        .onChange(of: model.lines.filter(\.done).count) {
            #if DEBUG
            OnboardingParityFixtures.log("HJSNAP-STEP announce muted=\(OnboardingParityFixtures.muteAnnouncements)")
            if OnboardingParityFixtures.muteAnnouncements { return }
            #endif
            if let last = model.lines.last(where: \.done) {
                AccessibilityNotification.Announcement(last.text + (last.count.map { ", \($0)" } ?? "")).post()
            }
        }
    }
}

private struct OBLoadingRing: View {
    let progress: Double
    let animated: Bool
    var body: some View {
        let k: CGFloat = 156 / 180
        ZStack {
            Circle().fill(RadialGradient(stops: [.init(color: OB.ink.opacity(0.96), location: 0.58),
                                                 .init(color: OB.ink.opacity(0), location: 0.72)],
                                         center: .center, startRadius: 0, endRadius: 78 * 1.41421))
            Circle().stroke(OB.paper.opacity(0.12), lineWidth: 7 * k).frame(width: 140 * k, height: 140 * k)
            Circle().trim(from: 0, to: progress)
                .stroke(OB.lime, style: StrokeStyle(lineWidth: 7 * k, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 140 * k, height: 140 * k)
                .shadow(color: OB.lime.opacity(0.6), radius: 4 * k)
                .animation(animated ? .easeInOut(duration: 0.35) : nil, value: progress)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int((progress * 100).rounded()))")
                    .font(OBFont.cabinet(.black, 42).monospacedDigit())
                Text("%")
                    .font(OBFont.cabinet(.black, 18))
                    .opacity(0.6)
            }
            .tracking(-0.04 * 42)
            .foregroundStyle(OB.paper)
        }
        .frame(width: 156, height: 156)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading your library, \(Int((progress * 100).rounded())) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct OBStageRow: View {
    let line: TasteProfileFlowModel.StageLine
    let animated: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                switch line.state {
                case .done: OBCheck().stroke(OB.lime, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)).frame(width: 16, height: 16)
                case .run: OBSpinner()
                case .wait: Circle().fill(OB.paper).frame(width: 6, height: 6)
                }
            }
            .frame(width: 18, height: 18)
            Text(line.text).font(.system(size: 14.5)).foregroundStyle(OB.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            if let v = line.value {
                OBNumberText(value: v) { line.outOf100 ? "\(Int($0.rounded()))/100" : Int($0.rounded()).formatted(.number.locale(Locale(identifier: "en_US"))) }
                    .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(OB.lime)
                    .animation(animated ? OB.easeOutCubic(0.7) : nil, value: v)
                    .transition(.identity)
            }
        }
        .opacity(line.state == .wait ? 0.3 : line.state == .run ? 1 : 0.78)
        .animation(.easeInOut(duration: 0.3), value: line.state)
        .accessibilityElement(children: .combine)
    }
}

/// Check path M3.5 8.4l3 3 6-6.6 (viewBox 16).
private struct OBCheck: Shape {
    func path(in r: CGRect) -> Path {
        let k = r.width / 16
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 3.5 * k, y: r.minY + 8.4 * k))
        p.addLine(to: CGPoint(x: r.minX + 6.5 * k, y: r.minY + 11.4 * k))
        p.addLine(to: CGPoint(x: r.minX + 12.5 * k, y: r.minY + 4.8 * k))
        return p
    }
}

/// 15pt ring, 2.2pt border paper@25% with a lime top, 0.8s per turn.
private struct OBSpinner: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { tl in
            let a = tl.date.timeIntervalSince(start) / 0.8 * 360
            ZStack {
                Circle().stroke(OB.paper.opacity(0.25), lineWidth: 2.2)
                Circle().trim(from: 0.625, to: 0.875).stroke(OB.lime, lineWidth: 2.2)
            }
            .frame(width: 15 - 2.2, height: 15 - 2.2)
            .rotationEffect(.degrees(a))
        }
        .frame(width: 15, height: 15)
    }
}

// MARK: - Reveal chapters (shared bits)

private struct OBStartsWith: View {
    let picks: [String]
    let max: Int
    var left = false
    var body: some View {
        let shown = Array(picks.prefix(max))
        let colors = Theme.Colors.genreColors(for: shown)
        VStack(alignment: left ? .leading : .center, spacing: 9) {
            OBMono(text: "Starting with", size: 9.5, opacity: 0.5)
            if shown.isEmpty {
                Text("a bit of everything").font(.system(size: 14)).foregroundStyle(OB.paper).opacity(0.75)
            } else {
                OBFlow(spacing: 7, centered: !left) {
                    ForEach(shown, id: \.self) { g in
                        OBGenrePill(genre: g, on: true, color: colors[g] ?? OB.lime, compact: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: left ? .leading : .center)
    }
}

// MARK: - 07 · Your sound

struct OBGenresChapter: View {
    let genres: [TasteProfile.GenreShare]
    let picks: Set<String>
    @Environment(\.obMetrics) private var m

    private var title: String {
        let names = genres.prefix(2).map { TasteCopy.inline($0.genre) }
        return names.count == 2 ? "You dig\n[\(names[0])] and \(names[1])." : "You dig\n[\(names.first ?? "everything")]."
    }

    var body: some View {
        let colors = Theme.Colors.genreColors(for: genres.map(\.genre))
        OBScreen {
            OBEyebrow(text: "Your sound")
            OBDisplayTitle(markup: title, size: m.displayL, autoFit: true).obRise(0.05)
            VStack(spacing: 11) {
                ForEach(Array(genres.prefix(5).enumerated()), id: \.element.genre) { k, g in
                    OBGenreBar(genre: g.genre, pct: Int((g.share * 100).rounded()), color: colors[g.genre] ?? OB.lime,
                               picked: picks.contains(g.genre), k: k)
                }
            }
            .padding(.top, 22)
            OBSub(text: "That’s most of your library. We’ll still dig for the unexpected.", maxCh: 32)
                .padding(.top, 10).obRise(0.6) // measured 2.5pt low at 12 (Cabinet text + 15pt pill line boxes, font-independent)
        }
    }
}

private struct OBGenreBar: View {
    let genre: String
    let pct: Int
    let color: Color
    let picked: Bool
    let k: Int
    @State private var on = false
    @State private var fill: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            OBGenrePill(genre: genre, on: true, color: color, fixedWidth: 98, verticalPadding: 9, horizontalPadding: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(OB.paper.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6).fill(color)
                        .frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("\(pct)%")
                .font(OBFont.mono(10.5)).tracking(0.14 * 10.5)
                .foregroundStyle(OB.paper).opacity(0.8)
                .lineLimit(1).fixedSize()
                .frame(width: 32, alignment: .trailing)
        }
        .overlay(alignment: .topTrailing) {
            if picked {
                OBMono(text: "your pick", size: 7.5, color: OB.lime).offset(y: -9)
            }
        }
        .offset(x: on ? 0 : -20)
        .opacity(on ? 1 : 0)
        .onAppear {
            withAnimation(OB.spring(220, 24).delay(0.35 + Double(k) * 0.14)) { on = true }
            withAnimation(OB.easeOut(0.9).delay(0.5 + Double(k) * 0.14)) { fill = min(1, CGFloat(pct) * 2.6 / 100) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(genre.capitalized), \(pct) percent\(picked ? ", your pick" : "")")
    }
}

// MARK: - 08 · Your rarity

struct OBRarityChapter: View {
    let score: Int
    @Environment(\.obMetrics) private var m
    @State private var ring: Double = 0

    private var tier: ArtistRarity.Tier { TasteRarity.tier(forScore: score) }

    private var title: String {
        switch tier {
        case .mythic: return "Your taste\nruns [mythic.]"
        case .ultraRare: return "Your taste\nruns [ultra rare.]"
        case .rare: return "Your taste\nruns [rare.]"
        case .emerging: return "Your taste\nis [on the rise.]"
        case .known: return "Your taste\nruns [familiar.]"
        }
    }

    private var bodyText: String {
        switch tier {
        case .known: return "**Plenty of rare finds ahead.** Let’s go deeper."
        case .emerging: return "**On the rise.** You already lean off the charts. Let’s go deeper."
        default:
            let tag = tier.tagline
            return "**\(tag.prefix(1).uppercased() + tag.dropFirst()).** You already listen well off the charts. Let’s go deeper."
        }
    }

    var body: some View {
        let k: CGFloat = 190 / 200
        OBScreen {
            OBEyebrow(text: "Your rarity")
            OBDisplayTitle(markup: title, size: m.displayL, autoFit: true).obRise(0.05)
            ZStack {
                Circle().stroke(OB.paper.opacity(0.12), lineWidth: 10 * k)
                Circle().trim(from: 0, to: ring)
                    .stroke(OB.lime, style: StrokeStyle(lineWidth: 10 * k, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: OB.lime.opacity(0.6), radius: 4 * k)
                VStack(spacing: 2) {
                    OBCountUp(to: Double(score), delay: 0.5, duration: 1.5)
                        .font(OBFont.cabinet(.black, 74).monospacedDigit())
                        .tracking(-0.05 * 74)
                        .frame(height: 74 * 0.9)
                    Text("/ 100").font(.system(size: 14)).opacity(0.55)
                }
                .foregroundStyle(OB.paper)
            }
            .frame(width: 156 * k, height: 156 * k)
            .frame(width: 190, height: 190)
            .frame(maxWidth: .infinity)
            .padding(.top, 26).padding(.bottom, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rarity \(score) out of 100, \(tier.label.lowercased())")

            HStack(spacing: 5) {
                ForEach(OB.ladder, id: \.self) { t in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(OB.tierColor(t)).frame(height: 6)
                        OBMono(text: t.label, size: 7.5, tracking: 0.02)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(t == tier ? 1 : 0.4)
                }
            }
            .padding(.top, 6).padding(.bottom, 4)
            .obRise(0.4)
            .accessibilityHidden(true)

            OBSub(text: bodyText, maxCh: 32, centered: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .obRise(0.55)
        }
        .onAppear { withAnimation(OB.easeOut(1.5).delay(0.5)) { ring = Double(score) / 100 } }
    }
}

// MARK: - 09 · Your signature artists (Spotify artwork: upright)

struct OBSignatureChapter: View {
    let artists: [TasteProfile.SignatureArtist]
    @Environment(\.obMetrics) private var m

    var body: some View {
        let inner = m.contentWidth - 16
        // .sg widths 39% / 29% / 29% + two 8pt gaps overflow the row, so CSS
        // flex-shrink scales all three by the same factor (131 / 97.5 / 97.5).
        let shrink: CGFloat = min(1, (inner - 16) / (inner * (0.39 + 0.29 + 0.29)))
        OBScreen {
            OBEyebrow(text: "Your artists")
            OBDisplayTitle(markup: "Your\n[signature]\nartists.", size: m.displayL).obRise(0.05)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(artists.prefix(3).enumerated()), id: \.element.name) { k, a in
                    OBSignatureTile(artist: a, k: k, width: inner * (k == 0 ? 0.39 : 0.29) * shrink)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 232, alignment: .bottom)
            .padding(.horizontal, 8)
            .padding(.top, 26)
            OBSub(text: "The ones you keep coming back to.", maxCh: 32, centered: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .obRise(0.9)
        }
    }
}

private struct OBSignatureTile: View {
    let artist: TasteProfile.SignatureArtist
    let k: Int
    let width: CGFloat
    @State private var on = false

    var body: some View {
        VStack(spacing: 4) {
            OBRemoteArt(url: artist.imageURL)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .obRing(cornerRadius: 8, color: k == 0 ? OB.lime : Color.white.opacity(0.1), width: k == 0 ? 2 : 1)
                .obShadow(RoundedRectangle(cornerRadius: 8), color: .black.opacity(0.7), y: 24, blur: 40, spread: -14)
            Text(artist.name)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(OB.paper)
                .multilineTextAlignment(.center).lineLimit(2)
                .padding(.top, 6)
            OBMono(text: "\(artist.savedSongs) saved songs", size: 8, opacity: 0.55)
        }
        .frame(width: width)
        .padding(.bottom, k == 0 ? 18 : 0)
        .offset(y: on ? 0 : 40)
        .opacity(on ? 1 : 0)
        .onAppear { withAnimation(OB.spring(160, 16).delay(0.3 + Double(k) * 0.2)) { on = true } }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 10 · Your deepest cut

struct OBDeepestChapter: View {
    let cut: TasteProfile.DeepCut
    let picks: [String]
    /// Spotify artwork is shown upright; Apple Music keeps the tilt.
    let spotifyArt: Bool
    @Environment(\.obMetrics) private var m
    @State private var on = false

    private var sticker: String? {
        cut.artistListeners.map { "\(TasteCopy.compact($0)) listeners" }
    }

    var body: some View {
        let size = m.cqw(52)
        OBScreen {
            OBEyebrow(text: "Your deepest cut")
            OBDisplayTitle(markup: "Your [deepest]\ncut.", size: m.displayL).obRise(0.05)

            Group {
                if spotifyArt { spotifyBlock(size) } else { appleBlock(size) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)

            VStack(spacing: 2) {
                Text(cut.title).font(.system(size: 17, weight: .semibold))
                Text(cut.artistName).font(.system(size: 14)).opacity(0.6)
            }
            .foregroundStyle(OB.paper)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, spotifyArt ? 16 : 24)
            .obRise(0.7)

            OBSub(text: "Hardly anyone has heard it. You have.", maxCh: 32, centered: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .obRise(0.8)

            Spacer(minLength: 12)
            OBStartsWith(picks: picks, max: 5).obRise(0.9)
        }
        .onAppear { withAnimation(OB.spring(150, 16).delay(0.3)) { on = true } }
    }

    /// Apple Music: the prototype exactly (tilted -2°, sticker on the corner).
    private func appleBlock(_ size: CGFloat) -> some View {
        art
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .circular))
            .obRing(cornerRadius: 24, color: OB.lime, width: 2)
            .obShadow(RoundedRectangle(cornerRadius: 24), color: OB.lime.opacity(0.35), blur: 48, spread: 4)
            .obShadow(RoundedRectangle(cornerRadius: 24), color: .black.opacity(0.7), y: 30, blur: 60, spread: -18)
            .overlay(alignment: .bottomTrailing) {
                if let sticker { OBSticker(text: sticker, tone: .lime, rotation: 5).offset(x: 10, y: 12) }
            }
            .scaleEffect(on ? 1 : 0.8)
            .rotationEffect(.degrees(on ? -2 : -6))
            .opacity(on ? 1 : 0)
    }

    /// Spotify: artwork upright and unaltered (resize + 8pt corners), the
    /// sticker moved off the art, Spotify attribution beside it.
    private func spotifyBlock(_ size: CGFloat) -> some View {
        VStack(spacing: 14) {
            art
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .obRing(cornerRadius: 8, color: OB.lime, width: 2)
                .obShadow(RoundedRectangle(cornerRadius: 8), color: OB.lime.opacity(0.35), blur: 48, spread: 4)
                .obShadow(RoundedRectangle(cornerRadius: 8), color: .black.opacity(0.7), y: 30, blur: 60, spread: -18)
            HStack(spacing: 10) {
                Image("brand-spotify-icon").resizable().interpolation(.high).scaledToFit()
                    .frame(width: 21, height: 21)
                    .accessibilityLabel("From Spotify")
                if let sticker { OBSticker(text: sticker, tone: .lime, rotation: 5) }
            }
        }
        .scaleEffect(on ? 1 : 0.8)
        .opacity(on ? 1 : 0)
    }

    @ViewBuilder
    private var art: some View {
        if let a = cut.appleArtwork {
            ArtworkImage(a, width: size(), height: size())
        } else {
            OBRemoteArt(url: cut.artworkURL)
        }
    }
    private func size() -> CGFloat { m.cqw(52) }
}

// MARK: - 11 · Fresh start (empty library)

struct OBFreshChapter: View {
    let picks: [String]
    @Environment(\.obMetrics) private var m
    var body: some View {
        OBScreen {
            OBEyebrow(text: "Empty library")
            OBDisplayTitle(markup: "Fresh\n[start.]", size: m.displayL).obRise(0.05)
            OBSub(text: "Nothing saved yet, so we’ll start from what you picked. Keep a few songs and your taste profile fills in on its own.",
                  size: 17)
                .padding(.top, 14).obRise(0.2)
            OBStartsWith(picks: picks, max: 8, left: true)
                .padding(.top, 22 + 12).obRise(0.35) // .starts.left margin 22 + .starts padding 12
        }
    }
}
