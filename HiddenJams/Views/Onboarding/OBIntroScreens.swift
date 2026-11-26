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
        // The CSS filters are baked into copies of the art and cross-faded
        // (live layer filters crashed the CI simulator's software renderer).
        return ZStack {
            OBCover(art: art, size: size, radius: 16)
            if q > 0 { OBFilteredCover(art: art, filter: .quiet, size: size, radius: 16).opacity(q) }
            if l > 0 { OBFilteredCover(art: art, filter: .lit, size: size, radius: 16).opacity(l) }
        }
            .opacity(1 - 0.2 * q) // .cv.quiet opacity .8
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
            .opacity(1) // .sub .74 is overridden by rise()
    }
}

// MARK: - 02 · Keep what moves you (interactive swipe demo)

private enum OBKeepDeck {
    static let deck = ["orbit", "tigers", "glass", "lowtide", "dust", "rosewater"].map(OBCatalog.named)
    static let plays = [2418, 731, 412, 3290, 1366, 864]

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
    @Environment(\.obCardDragLock) private var dragLock

    /// Resting half-swipe to the right: a gentle ~4.4° tilt with the Keep
    /// stamp partly visible (opacity ≈ 0.44) as a hint the card is draggable.
    private static let restX: CGFloat = 60
    /// Drag distance (from the resting pose) that commits a swipe.
    static let commitDistance: CGFloat = 90

    @State private var index = 0
    @State private var x: CGFloat = Self.restX
    @State private var finger: Double = 0
    @State private var saved = 0
    @State private var skipped = 0
    @State private var hintKeep = true
    @State private var flying = false

    var body: some View {
        let deck = OBKeepDeck.deck
        let top = deck[index % deck.count]
        let n1 = deck[(index + 1) % deck.count], n2 = deck[(index + 2) % deck.count]
        // Card 62% of the width (296pt deck on a 402pt phone); on short
        // screens (SE) it shrinks so the tally never crowds the dots/Next.
        let card = min(m.cqw(62), max(150, m.contentHeight() - 284 - 47))
        OBScreen {
            OBDisplayTitle(markup: "Keep what\n[moves] you.", size: m.displayL).obRise(0.1)
            OBSub(text: "Swipe right to save a song to your **Hidden Jams** playlist. Swipe left to skip.")
                .padding(.top, 12).obRise(0.2)

            // Build 93: the playlist chip is gone, so the deck re-centers
            // between the header and the pinned Next button.
            Spacer(minLength: 12)

            ZStack {
                OBFilteredCover(art: n2.art, filter: .under2, size: card, radius: 24)
                    .scaleEffect(0.88).offset(y: 26)
                OBFilteredCover(art: n1.art, filter: .under, size: card, radius: 24)
                    .scaleEffect(0.94).offset(y: 14)
                OBKeepCard(x: x, track: top, plays: OBKeepDeck.plays[index % OBKeepDeck.plays.count],
                           size: card, finger: finger)
                    .id(index)
                    .contentShape(Rectangle())
                    .highPriorityGesture(drag)
            }
            .frame(maxWidth: .infinity)
            .frame(height: card + 47)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Demo: drag right to keep a song, left to skip")
            .accessibilityValue("\(saved) saved, \(skipped) skipped")
            .accessibilityHint("Swiping a card does not change the onboarding page.")
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityAction(named: "Keep") { commit(1) }
            .accessibilityAction(named: "Skip") { commit(-1) }

            ZStack {
                OBMono(text: hintKeep ? "Swipe right to keep →" : "← Swipe left to skip", size: 12, color: OB.lime, opacity: 0.95)
                    .id(hintKeep)
                    .transition(.asymmetric(insertion: .modifier(active: OBHintShift(y: 6, o: 0), identity: OBHintShift(y: 0, o: 1)),
                                            removal: .modifier(active: OBHintShift(y: -6, o: 0), identity: OBHintShift(y: 0, o: 1))))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .padding(.top, 18)

            Spacer(minLength: 12)

            OBKeepTally(saved: saved, skipped: skipped)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
                .obRise(0.3)
        }
        #if DEBUG
        .onAppear { applyKeepPinIfNeeded() }
        #endif
    }

    /// A drag that starts on the card belongs to the card only: it claims
    /// the pager's drag lock on every change, so the pager's simultaneous
    /// page swipe ignores it. Past `commitDistance` (or a fast fling) the
    /// card flies off: right = saved, left = skipped; otherwise it springs
    /// back to the resting pose.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                dragLock?.claim()
                guard !flying else { return }
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) {
                    x = Self.restX + v.translation.width
                    hintKeep = x >= 0
                }
            }
            .onEnded { v in
                dragLock?.claim()
                guard !flying else { return }
                let dir = OBKeepSwipe.direction(translation: v.translation.width,
                                                predicted: v.predictedEndTranslation.width,
                                                commit: Self.commitDistance)
                if dir != 0 { commit(dir) } else { settle() }
            }
    }

    private func settle() {
        let back = {
            x = Self.restX
            hintKeep = true
        }
        if reduceMotion {
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) { back() }
        } else {
            withAnimation(OB.spring(280, 22)) { back() }
        }
    }

    /// dir 1 = keep (saved), -1 = skip. Dismisses the top card and counts it.
    private func commit(_ dir: Int) {
        guard !flying else { return }
        flying = true
        if dir > 0 { saved += 1 } else { skipped += 1 }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let next = {
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) {
                index += 1
                x = Self.restX
                hintKeep = true
                flying = false
            }
        }
        if reduceMotion { next(); return }
        withAnimation(.easeIn(duration: 0.22)) { x = CGFloat(dir) * 560 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { next() }
    }

    #if DEBUG
    private func applyKeepPinIfNeeded() {
        guard let pin = OnboardingParityFixtures.keepPin else { return }
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) {
            index = pin.index; x = pin.x; finger = pin.finger; hintKeep = pin.hintKeep
            saved = pin.kept
            skipped = pin.skipped
        }
    }
    #endif
}

/// Pure swipe decision for the onboarding keep card (unit-tested).
enum OBKeepSwipe {
    /// 1 = keep, -1 = skip, 0 = spring back.
    static func direction(translation: CGFloat, predicted: CGFloat, commit: CGFloat) -> Int {
        if translation >= commit || predicted >= commit * 2.5 { return 1 }
        if translation <= -commit || predicted <= -commit * 2.5 { return -1 }
        return 0
    }
}

/// "3 saved · 1 skipped" tally under the onboarding deck.
private struct OBKeepTally: View {
    let saved: Int
    let skipped: Int
    @State private var bumpSaved: CGFloat = 1
    @State private var bumpSkipped: CGFloat = 1

    var body: some View {
        HStack(spacing: 10) {
            (Text("\(saved)").fontWeight(.bold) + Text(" saved"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OB.ink)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Capsule().fill(OB.lime))
                .scaleEffect(bumpSaved)
            (Text("\(skipped)").fontWeight(.bold) + Text(" skipped"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OB.paper)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Capsule().fill(OB.surface.opacity(0.86)))
                .overlay(Capsule().strokeBorder(OB.paper.opacity(0.14), lineWidth: 1))
                .scaleEffect(bumpSkipped)
        }
        .fixedSize()
        .onChange(of: saved) { _, _ in
            bumpSaved = 1.2
            withAnimation(OB.spring(400, 12)) { bumpSaved = 1 }
        }
        .onChange(of: skipped) { _, _ in
            bumpSkipped = 1.2
            withAnimation(OB.spring(400, 12)) { bumpSkipped = 1 }
        }
        .accessibilityElement(children: .combine)
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

// MARK: - 03 · Fewer plays. Rarer finds. (auto-playing descent)

private struct OBRarityRow {
    let key: String
}

struct OBRarityDemoScreen: View {
    @Environment(\.obMetrics) private var m
    @State private var rail: CGFloat = 0

    /// Sample tracks, most-heard to least-heard (build 93: titles only).
    private static let rows: [OBRarityRow] = ["slowly", "mesa", "rosewater", "velvet", "glass"].map(OBRarityRow.init)

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

                VStack(spacing: 12) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { k, r in
                        OBRarityRowView(row: r, k: k, last: k == Self.rows.count - 1)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 22)

        }
        .onAppear {
            withAnimation(OB.easeInOut(3.4).delay(0.5)) { rail = 1 }
        }
    }
}

/// Build 93 (Chris): a plain track list — artwork, title, artist. No play
/// counts, scores, numbers, badges or dividers.
private struct OBRarityRowView: View {
    let row: OBRarityRow
    let k: Int
    let last: Bool
    @State private var on = false

    var body: some View {
        let t = OBCatalog.named(row.key)
        let d = 0.55 + Double(k) * 0.7
        HStack(spacing: 12) {
            OBCover(art: t.art, size: 44, radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.track).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.white)
                Text(t.artist).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.6))
            }
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scaleEffect(on ? 1 : 0.97)
        .offset(x: on ? 0 : -24)
        .opacity(on ? 1 : 0)
        .onAppear { withAnimation(OB.spring(220, 22).delay(d)) { on = true } }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 04 · Pick your genres

struct OBMoodScreen: View {
    @Binding var picks: Set<String>
    var onTap: () -> Void = {}
    @Environment(\.obMetrics) private var m

    var body: some View {
        let colors = Theme.Colors.genreColors(for: Array(picks))
        OBScreen {
            OBOneLineTitle(lead: OBCopy.moodTitleLead, accent: OBCopy.moodTitleAccent, size: m.displayM).obRise(0.1)
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

// MARK: - 05 · Connect (30-second clips headline)

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
                OBDisplayTitle(markup: OBCopy.connectHeadline, size: m.displayConnect, autoFit: true).obRise(0.1)
                OBSub(text: "Streaming pushes what’s trending and promoted. Connect your music and we’ll dig up what you’d never hear otherwise.",
                      maxCh: 33)
                    .padding(.top, 12).obRise(0.22)
                OBMono(text: "We only save songs you keep.", size: 10, opacity: 1) // .foot .5 overridden by rise()
                    .padding(.top, 14).obRise(0.3)
            }
            .padding(.top, 30)
        }
    }
}
