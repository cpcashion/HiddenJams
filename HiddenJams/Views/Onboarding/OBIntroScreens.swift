//
//  OBIntroScreens.swift
//  HiddenJams
//
//  Onboarding v5 screens 1-5 (before sign-in), built to the prototype's
//  source: screens/Intro, Keep, Rarity, Mood, Connect + styles.css.
//  Covers are original generated artwork with made-up names (OBCatalog).
//

import SwiftUI

// MARK: - 01 · Most music never gets heard

private struct OBCloudCover {
    let key: String
    let x: CGFloat, y: CGFloat, s: CGFloat, r: Double
}

struct OBIntroScreen: View {
    @Environment(\.obMetrics) private var m
    @State private var dim = false

    /// [x%, y%, size, rotation] of the cloud zone, same as the prototype.
    private static let cloud: [OBCloudCover] = [
        .init(key: "orbit", x: 4, y: 8, s: 92, r: -7), .init(key: "ember", x: 70, y: 4, s: 84, r: 6),
        .init(key: "rosewater", x: 33, y: 2, s: 70, r: 3), .init(key: "mesa", x: 44, y: 42, s: 96, r: -4),
        .init(key: "gently", x: 1, y: 56, s: 76, r: 5), .init(key: "velvet", x: 76, y: 50, s: 80, r: -6),
        .init(key: "lowtide", x: 22, y: 36, s: 58, r: 8), .init(key: "slowly", x: 62, y: 28, s: 56, r: -3),
    ]
    private static let lit = "mesa"

    var body: some View {
        let cloudW = m.contentWidth + 8
        let cloudH = (m.contentHeight() * 0.44).rounded(.down)
        OBScreen {
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.cloud.enumerated()), id: \.offset) { i, c in
                    OBCloudCoverView(art: "obcover-" + c.key, size: c.s * 1.14, rotation: c.r, index: i,
                                     lit: c.key == Self.lit, dim: dim)
                        .offset(x: cloudW * c.x / 100, y: cloudH * c.y / 100)
                        .zIndex(c.key == Self.lit ? 2 : 0)
                }
                OBSparkle()
                    .stroke(OB.paper, style: StrokeStyle(lineWidth: 2.6 * 26 / 40, lineJoin: .round))
                    .frame(width: 26, height: 26)
                    .offset(x: cloudW - 10 - 26, y: cloudH - 6 - 26)
                    .zIndex(1)
            }
            .frame(width: cloudW, height: cloudH, alignment: .topLeading)
            .padding(.horizontal, -4)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                OBDisplayTitle(markup: "Most music\nnever gets\n[heard.]", size: m.displayXL)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topTrailing) {
                        OBStarburst()
                            .stroke(OB.lime, style: StrokeStyle(lineWidth: 3.4 * 60 / 80, lineCap: .round))
                            .frame(width: 60, height: 60)
                            .offset(x: 2, y: -26)
                    }
                    .obRise(0.2)
                OBStatLine().padding(.top, 14).obRise(0.34)
                OBMono(text: "Source: Luminate 2025 Year-End Music Report", size: 9.5, opacity: 0.42)
                    .padding(.top, 10)
                    .obRise(0.44)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            dim = true
        }
    }
}

private struct OBCloudCoverView: View {
    let art: String
    let size: CGFloat
    let rotation: Double
    let index: Int
    let lit: Bool
    let dim: Bool

    @State private var shown = false
    @State private var quiet: Double = 0
    @State private var glow: Double = 0
    @State private var driftStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// CSS `drift`: translate (0,-5) → (3,6), ease-in-out, alternate;
    /// 7s; even children 9s alternate-reverse; every third child 8s.
    private var driftPeriod: Double { (index + 1) % 3 == 0 ? 8 : ((index + 1) % 2 == 0 ? 9 : 7) }
    private var driftReverse: Bool { (index + 1) % 2 == 0 }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let d = drift(at: tl.date)
            cover
                .offset(x: d.x, y: d.y)
        }
        .onAppear {
            driftStart = Date()
            if reduceMotion { shown = true; return }
            withAnimation(OB.spring(160, 18).delay(0.1 + Double(index) * 0.07)) { shown = true }
        }
        .onChange(of: dim) { _, on in
            guard on else { return }
            if lit {
                glow = 1
                withAnimation(OB.ease(1.1).delay(Double(index) * 0.13)) { quiet = -1 }
            } else {
                withAnimation(OB.ease(1.1).delay(Double(index) * 0.13)) { quiet = 1 }
            }
        }
    }

    private var cover: some View {
        // quiet: grayscale(1) brightness(.38) contrast(.9) → out = .342·gray + .05
        // lit (quiet = -1): saturate(1.15)
        let q = max(0, quiet), l = max(0, -quiet)
        return OBCover(art: art, size: size, radius: 16)
            .saturation(1 + 0.15 * l)
            .grayscale(q)
            .colorMultiply(Color(white: 1 - q * (1 - 0.342)))
            .brightness(0.05 * q)
            .overlay(RoundedRectangle(cornerRadius: 16.5).stroke(Color.white.opacity(0.1), lineWidth: 1).padding(-0.5))
            .obRing(cornerRadius: 16, color: OB.lime.opacity(glow), width: 2)
            .obShadow(RoundedRectangle(cornerRadius: 16), color: OB.lime.opacity(0.45 * glow), blur: 42, spread: 6)
            .obShadow(RoundedRectangle(cornerRadius: 16), color: .black.opacity(0.7), y: 18, blur: 36, spread: -12)
            .scaleEffect(shown ? 1 : 0.6)
            .rotationEffect(.degrees(shown ? rotation : rotation - 10))
            .opacity(shown ? 1 : 0)
    }

    private func drift(at date: Date) -> CGPoint {
        guard !reduceMotion else { return CGPoint(x: 0, y: -5) }
        let t = max(0, date.timeIntervalSince(driftStart))
        let cycle = t / driftPeriod
        var k = cycle.truncatingRemainder(dividingBy: 1)
        var forward = Int(cycle) % 2 == 0
        if driftReverse { forward.toggle() }
        if !forward { k = 1 - k }
        let e = OBEasing.easeInOut(k)
        return CGPoint(x: 3 * e, y: -5 + 11 * e)
    }
}

/// CSS timing functions evaluated in code (for clock-driven motion).
enum OBEasing {
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<30 {
            let cx = 3 * x1 * t * (1 - t) * (1 - t) + 3 * x2 * t * t * (1 - t) + t * t * t
            if cx < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return 3 * y1 * t * (1 - t) * (1 - t) + 3 * y2 * t * t * (1 - t) + t * t * t
    }
    static func easeInOut(_ x: Double) -> Double { bezier(0.42, 0, 0.58, 1, x) }
    static func easeOut(_ x: Double) -> Double { bezier(0, 0, 0.58, 1, x) }
}

/// "**88%** of songs on streaming got 1,000 plays or fewer last year. Hidden Jams finds them."
/// 88 counts up from 0 (1.5s, ease-out cubic) starting at 1.5s.
private struct OBStatLine: View {
    @State private var pct: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        OBStatText(value: pct)
            .task {
                if reduceMotion { pct = 88; return }
                try? await Task.sleep(for: .milliseconds(1500))
                withAnimation(OB.easeOutCubic(1.5)) { pct = 88 }
            }
            .accessibilityLabel("88% of songs on streaming got 1,000 plays or fewer last year. Hidden Jams finds them.")
    }
}

private struct OBStatText: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View {
        let size: CGFloat = 17
        let pct = Text("\(Int(value.rounded()))%")
            .font(OBFont.cabinet(.extrabold, size * 1.15).monospacedDigit())
            .tracking(-0.02 * size * 1.15)
            .foregroundColor(OB.lime)
        let rest = Text(" of songs on streaming got 1,000 plays or fewer last year. Hidden Jams finds them.")
            .font(OBFont.cabinet(.medium, size))
            .tracking(-0.005 * size)
            .foregroundColor(OB.paper)
        let ui = OBFont.ui(.medium, size)
        return (pct + rest)
            .lineSpacing(max(0, size * 1.32 - ui.lineHeight))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, (size * 1.32 - size * 1.15) / 2)
            .frame(maxWidth: OBFont.ch(size) * 31, alignment: .leading)
            .opacity(0.74)
    }
}

// MARK: - 02 · Keep what moves you (auto-playing swipe demo)

private enum OBKeepDeck {
    static let deck = ["orbit", "tigers", "glass", "lowtide", "dust", "rosewater"].map(OBCatalog.named)
    static let plays = [2418, 731, 412, 3290, 1366, 864]
    static let script: [Bool] = [true, false, true, true] // keep, skip, keep, keep

    static func tag(_ t: OBTrack) -> String {
        "#" + t.genre.lowercased()
            .replacingOccurrences(of: "r&b/soul", with: "soul")
            .replacingOccurrences(of: "indie pop", with: "indie")
            .replacingOccurrences(of: "indie rock", with: "psych")
    }
}

struct OBKeepScreen: View {
    @Environment(\.obMetrics) private var m
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var x: CGFloat = 0
    @State private var finger: Double = 0
    @State private var kept: [String] = []
    @State private var hintKeep = true
    @State private var bump = 0

    var body: some View {
        let deck = OBKeepDeck.deck
        let top = deck[index % deck.count]
        let n1 = deck[(index + 1) % deck.count], n2 = deck[(index + 2) % deck.count]
        let card = m.cqw(62)
        OBScreen {
            OBDisplayTitle(markup: "Keep what\n[moves] you.", size: m.displayL).obRise(0.1)
            OBSub(text: "Swipe right to save a song to your **Hidden Jams** playlist. Swipe left to skip.")
                .padding(.top, 12).obRise(0.2)

            ZStack {
                OBCover(art: n2.art, size: card, radius: 24)
                    .colorMultiply(Color(white: 0.42))
                    .scaleEffect(0.88).offset(y: 26)
                OBCover(art: n1.art, size: card, radius: 24)
                    .saturation(0.9).colorMultiply(Color(white: 0.6))
                    .scaleEffect(0.94).offset(y: 14)
                OBKeepCard(x: x, track: top, plays: OBKeepDeck.plays[index % OBKeepDeck.plays.count],
                           size: card, finger: finger)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 296)
            .padding(.top, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Demo: swipe right to keep a song, left to skip")

            ZStack {
                OBMono(text: hintKeep ? "Swipe right to keep →" : "← Swipe left to skip", size: 12, color: OB.lime, opacity: 0.95)
                    .id(hintKeep)
                    .transition(.asymmetric(insertion: .modifier(active: OBHintShift(y: 6, o: 0), identity: OBHintShift(y: 0, o: 1)),
                                            removal: .modifier(active: OBHintShift(y: -6, o: 0), identity: OBHintShift(y: 0, o: 1))))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .padding(.top, 12)

            OBPlaylistChip(kept: kept, bump: bump)
                .padding(.top, 8)
                .obRise(0.3)
        }
        .task { await runScript() }
    }

    private func runScript() async {
        guard !reduceMotion else { return }
        func wait(_ ms: Int) async -> Bool {
            try? await Task.sleep(for: .milliseconds(ms))
            return !Task.isCancelled
        }
        var n = 0
        guard await wait(1000) else { return }
        while !Task.isCancelled {
            for keep in OBKeepDeck.script {
                // AnimatePresence mode="wait": old hint leaves (.18s), then the new one enters (.18s)
                if hintKeep != keep {
                    withAnimation(.easeInOut(duration: 0.18)) { hintKeep = keep }
                }
                let dir: CGFloat = keep ? 1 : -1
                guard await wait(650) else { return }
                withAnimation(.easeOut(duration: 0.18)) { finger = 1 }
                guard await wait(220) else { return }
                withAnimation(.timingCurve(0.3, 0.1, 0.3, 1, duration: 0.75)) { x = dir * 120 }
                guard await wait(750 + 160) else { return }
                withAnimation(.timingCurve(0.5, 0, 0.9, 0.6, duration: 0.34)) { x = dir * 560 }
                guard await wait(340) else { return }
                withAnimation(.easeOut(duration: 0.1)) { finger = 0 }
                if keep {
                    kept.append(OBKeepDeck.deck[n % OBKeepDeck.deck.count].art)
                    bump += 1
                }
                n += 1
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { index = n; x = 0 }
                guard await wait(900) else { return }
            }
            guard await wait(1500) else { return }
            kept = []
        }
    }
}

private struct OBHintShift: ViewModifier {
    let y: CGFloat
    let o: Double
    func body(content: Content) -> some View { content.offset(y: y).opacity(o) }
}

/// Top card: `x` drives the tilt (x/220·16°, clamped) and the stamps.
private struct OBKeepCard: View, Animatable {
    var x: CGFloat
    let track: OBTrack
    let plays: Int
    let size: CGFloat
    let finger: Double

    var animatableData: CGFloat { get { x } set { x = newValue } }

    var body: some View {
        let rot = Double(max(-16, min(16, x / 220 * 16)))
        let keepOp = Double(max(0, min(1, (x - 20) / 90)))
        let skipOp = Double(max(0, min(1, (-20 - x) / 90)))
        ZStack {
            OBCover(art: track.art, size: size, radius: 24)
                .overlay(RoundedRectangle(cornerRadius: 24.5).stroke(Color.white.opacity(0.08), lineWidth: 1).padding(-0.5))
                .obShadow(RoundedRectangle(cornerRadius: 24), color: .black.opacity(0.7), y: 30, blur: 60, spread: -18)
            OBSticker(text: OBKeepDeck.tag(track), tone: .paper, rotation: -6, size: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: 14, y: -10)
            OBSticker(text: "\(plays.formatted(.number.locale(Locale(identifier: "en_US")))) plays", tone: .lime, rotation: 5, size: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: -12, y: 12)
            OBStamp(text: "Keep", fill: OB.lime, rotation: 8)
                .opacity(keepOp)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: -14, y: 20)
            OBStamp(text: "Skip", fill: OB.paper, rotation: -8)
                .opacity(skipOp)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: 14, y: 20)
            Circle()
                .fill(OB.paper.opacity(0.28))
                .overlay(Circle().strokeBorder(OB.paper.opacity(0.75), lineWidth: 2))
                .frame(width: 46, height: 46)
                .obShadow(Circle(), color: .black.opacity(0.4), y: 6, blur: 20)
                .position(x: size * 0.52, y: size * 0.58)
                .opacity(finger)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rot))
        .offset(x: x)
    }
}

private struct OBStamp: View {
    let text: String
    let fill: Color
    let rotation: Double
    var body: some View {
        Text(text)
            .font(OBFont.cabinet(.black, 32))
            .tracking(-0.03 * 32)
            .foregroundStyle(OB.ink)
            .fixedSize()
            .padding(.top, 2).padding(.bottom, 5).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .circular).fill(fill))
            .rotationEffect(.degrees(rotation))
    }
}

private struct OBPlaylistChip: View {
    let kept: [String]
    let bump: Int
    @State private var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            // 2×2 mosaic, newest first
            let cells = (0..<4).map { k -> String? in kept.count - 1 - k >= 0 ? kept[kept.count - 1 - k] : nil }
            VStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { c in
                            ZStack {
                                OB.cell
                                if let art = cells[r * 2 + c] {
                                    OBMosaicCell(art: art).id("\(art)\(kept.count)")
                                }
                            }
                            .frame(width: 22, height: 22)
                            .clipped()
                        }
                    }
                }
            }
            .frame(width: 46, height: 46)
            .background(OB.graphite)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .circular))

            VStack(alignment: .leading, spacing: 2) {
                Text("Hidden Jams").font(.system(size: 15, weight: .semibold)).foregroundStyle(OB.paper)
                Text("Playlist in your music app").font(.system(size: 12.5)).foregroundStyle(OB.paper).opacity(0.55)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            (Text("\(kept.count)").fontWeight(.bold) + Text(" saved"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OB.ink)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Capsule().fill(OB.lime))
                .scaleEffect(scale)
                .fixedSize()
        }
        .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .circular).fill(OB.surface.opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .circular).strokeBorder(OB.paper.opacity(0.07), lineWidth: 1))
        .onChange(of: bump) { _, _ in
            scale = 1.35
            withAnimation(OB.spring(400, 12)) { scale = 1 }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OBMosaicCell: View {
    let art: String
    @State private var on = false
    var body: some View {
        Image(art).resizable().aspectRatio(contentMode: .fill)
            .frame(width: 22, height: 22).clipped()
            .scaleEffect(on ? 1 : 0.4)
            .opacity(on ? 1 : 0)
            .onAppear { withAnimation(OB.spring(300, 18)) { on = true } }
    }
}

// MARK: - 03 · Fewer plays. Rarer finds. (auto-playing descent)

private struct OBRarityRow {
    let key: String
    let plays: Int
    let score: Int
    let tier: ArtistRarity.Tier
}

struct OBRarityDemoScreen: View {
    @Environment(\.obMetrics) private var m
    @State private var rail: CGFloat = 0
    @State private var foot = false

    /// Sample numbers moved onto the app's tier cut-offs (known < 50,
    /// emerging 50-69, rare 70-84, ultra rare 85-94, mythic 95+).
    private static let rows: [OBRarityRow] = [
        .init(key: "slowly", plays: 41_800_000, score: 9, tier: .known),
        .init(key: "mesa", plays: 6_200_000, score: 56, tier: .emerging),
        .init(key: "rosewater", plays: 480_000, score: 74, tier: .rare),
        .init(key: "velvet", plays: 38_000, score: 88, tier: .ultraRare),
        .init(key: "glass", plays: 412, score: 97, tier: .mythic),
    ]

    var body: some View {
        OBScreen {
            OBDisplayTitle(markup: "Fewer plays.\n[Rarer] finds.", size: m.displayL).obRise(0.1)
            OBSub(text: "Every song gets a Rarity score. The less it’s been heard, the higher it climbs.")
                .padding(.top, 12).obRise(0.2)

            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .top) {
                    Capsule().fill(OB.paper.opacity(0.1))
                    LinearGradient(stops: [.init(color: Color(hex: "9C98A6"), location: 0),
                                           .init(color: Color(hex: "C9A0F0"), location: 0.4),
                                           .init(color: Color(hex: "FF8FC7"), location: 0.7),
                                           .init(color: OB.lime, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .scaleEffect(x: 1, y: rail, anchor: .top)
                }
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.vertical, 6)

                VStack(spacing: 8) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { k, r in
                        OBRarityRowView(row: r, k: k, last: k == Self.rows.count - 1)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 22)

            OBMono(text: "Sample songs and numbers", size: 9.5)
                .opacity(foot ? 0.55 : 0)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .onAppear {
            withAnimation(OB.easeInOut(3.4).delay(0.5)) { rail = 1 }
            withAnimation(.easeInOut(duration: 0.3).delay(3.9)) { foot = true }
        }
    }
}

private struct OBRarityRowView: View {
    let row: OBRarityRow
    let k: Int
    let last: Bool
    @State private var on = false

    var body: some View {
        let t = OBCatalog.named(row.key)
        let d = 0.55 + Double(k) * 0.7
        HStack(spacing: 10) {
            OBCover(art: t.art, size: 46, radius: 11)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.track).font(.system(size: 14, weight: .semibold)).foregroundStyle(OB.paper)
                Text(t.artist).font(.system(size: 12)).foregroundStyle(OB.paper).opacity(0.55)
            }
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(row.plays >= 1_000_000 ? String(format: "%.1fM", Double(row.plays) / 1e6)
                                            : row.plays.formatted(.number.locale(Locale(identifier: "en_US"))))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Text("plays").font(.system(size: 10.5)).opacity(0.5)
            }
            .foregroundStyle(OB.paper)
            .fixedSize()
            VStack(spacing: 3) {
                OBCountUp(to: Double(row.score), delay: d + 0.15, duration: 0.7)
                    .font(OBFont.cabinet(.black, 18).monospacedDigit())
                    .frame(height: 18)
                Text(row.tier.label)
                    .font(.system(size: 7.5, weight: .heavy))
                    .tracking(0.06 * 7.5)
                    .frame(height: 7.5)
            }
            .foregroundStyle(OB.ink)
            .frame(width: 70, height: 42)
            .background(RoundedRectangle(cornerRadius: 13, style: .circular).fill(OB.tierColor(row.tier)))
        }
        .padding(.leading, 6).padding(.trailing, 8)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(OB.surface.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .circular)
            .strokeBorder(last ? OB.lime.opacity(0.75) : OB.paper.opacity(0.07), lineWidth: 1))
        .obShadow(RoundedRectangle(cornerRadius: 18), color: last ? OB.lime.opacity(0.4) : .clear, blur: 28, spread: -4)
        .scaleEffect(on ? 1 : 0.97)
        .offset(x: on ? 0 : -24)
        .opacity(on ? 1 : 0)
        .onAppear { withAnimation(OB.spring(220, 22).delay(d)) { on = true } }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 04 · In the mood for…

struct OBMoodScreen: View {
    @Binding var picks: Set<String>
    var onTap: () -> Void = {}
    @Environment(\.obMetrics) private var m

    var body: some View {
        let colors = Theme.Colors.genreColors(for: Array(picks))
        OBScreen {
            OBDisplayTitle(markup: "In the [mood]\nfor…", size: m.displayM).obRise(0.1)
            OBSub(text: "Pick a few and we’ll dig there first. Change them any time.", maxCh: 34)
                .padding(.top, 12).obRise(0.2)

            ScrollView(.vertical, showsIndicators: false) {
                OBFlow(spacing: 8) {
                    ForEach(Array(GenreCatalog.onboardingOrder.enumerated()), id: \.element) { k, g in
                        OBMoodPill(genre: g, on: picks.contains(g), color: colors[g] ?? OB.lime, delay: 0.3 + Double(k) * 0.012) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onTap()
                            if picks.contains(g) { picks.remove(g) } else { picks.insert(g) }
                        }
                    }
                }
                .padding(.bottom, 6)
                .padding(.vertical, 4).padding(.horizontal, 6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
                }
            )
            .padding(.horizontal, -6)
            .padding(.top, 14)
            .frame(maxHeight: .infinity)
            .obRise(0.3)

            OBMono(text: picks.isEmpty ? "Skipping is fine · we’ll mix it up" : "\(picks.count) picked · we’ll start there",
                   size: 10, opacity: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }
}

private struct OBMoodPill: View {
    let genre: String
    let on: Bool
    let color: Color
    let delay: Double
    let action: () -> Void
    @State private var shown = false

    var body: some View {
        Button(action: action) {
            OBGenrePill(genre: genre, on: on, color: color)
                .animation(OB.spring(400, 20), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .offset(y: shown ? 0 : 14)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(OB.spring(500, 25).delay(delay)) { shown = true } }
    }
}

// MARK: - 05 · Find what the big apps won't play

struct OBConnectScreen: View {
    @Environment(\.obMetrics) private var m

    var body: some View {
        let t = OBCatalog.tracks
        let rowA = Array(t[0..<8])
        let rowB = Array((Array(t[4...]) + Array(t[0..<4])).prefix(8))
        OBScreen(extraBottom: 66) {
            VStack(spacing: 10) {
                OBMarquee(items: rowA, cover: 70, radius: 14, duration: 38)
                OBMarquee(items: rowB, cover: 70, radius: 14, duration: 46, reverse: true)
            }
            .frame(width: m.width, height: 150)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                         .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .padding(.horizontal, -OB.pad)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                OBDisplayTitle(markup: "Find what the\nbig apps\n[won’t] play.", size: m.displayConnect).obRise(0.1)
                OBSub(text: "Streaming pushes what’s trending and promoted. Connect your music and we’ll dig up what you’d never hear otherwise.",
                      maxCh: 33)
                    .padding(.top, 12).obRise(0.22)
                OBMono(text: "We only save songs you keep.", size: 10, opacity: 0.5)
                    .padding(.top, 14).obRise(0.3)
            }
            .padding(.top, 30)
        }
    }
}
