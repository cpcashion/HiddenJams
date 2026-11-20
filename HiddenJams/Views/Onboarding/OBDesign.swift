//
//  OBDesign.swift
//  HiddenJams
//
//  Onboarding v5, exact build of the approved prototype
//  (https://cpcashion.github.io/hiddenjams-onboarding-v4/v5/, source:
//  prototype/onboarding-v5 on design/onboarding-v4-prototype).
//  Every value here is the prototype's CSS value (styles.css), in points.
//  Display and body copy are Cabinet Grotesk (Fontshare ITF FFL, official
//  OTFs bundled unmodified); buttons, pills and rows are SF Pro; kickers are
//  SF Mono, exactly where the prototype uses each.
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Tokens

enum OB {
    static let ink = Color(hex: "0B0B0F")
    static let plum = Color(hex: "1C1024")
    static let graphite = Color(hex: "1E1E24")
    static let surface = Color(hex: "17151C")
    static let lime = Color(hex: "C8E86B")
    static let paper = Color(hex: "F7F3EE")
    static let magenta = Color(hex: "E056B5")
    static let violet = Color(hex: "8E4DE0")
    static let cell = Color(hex: "2A2A32")

    /// Side padding (`--pad`).
    static let pad: CGFloat = 22
    /// Dots (26) + gap (14) + Next (56).
    static let dockHeight: CGFloat = 96
    /// The prototype's reference width; `cqw` sizes scale from it.
    static let designWidth: CGFloat = 402

    static func tierColor(_ tier: ArtistRarity.Tier) -> Color {
        switch tier {
        case .known: return Color(hex: "9C98A6")
        case .emerging: return Color(hex: "8EE6B8")
        case .rare: return Color(hex: "C9A0F0")
        case .ultraRare: return Color(hex: "FF8FC7")
        case .mythic: return lime
        }
    }
    static let ladder: [ArtistRarity.Tier] = [.known, .emerging, .rare, .ultraRare, .mythic]

    /// framer-motion `{ type: 'spring', stiffness, damping }` (mass 1).
    static func spring(_ stiffness: Double, _ damping: Double) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: stiffness, damping: damping, initialVelocity: 0)
    }
    /// CSS `ease`.
    static func ease(_ d: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: d) }
    /// framer `easeOut` / CSS `ease-out`.
    static func easeOut(_ d: Double) -> Animation { .timingCurve(0, 0, 0.58, 1, duration: d) }
    /// framer `easeInOut` / CSS `ease-in-out`.
    static func easeInOut(_ d: Double) -> Animation { .timingCurve(0.42, 0, 0.58, 1, duration: d) }
    /// The prototype's count-up curve: 1 - (1 - k)^3.
    static func easeOutCubic(_ d: Double) -> Animation { .timingCurve(0.33, 1, 0.68, 1, duration: d) }
}

// MARK: - Screen metrics (safe areas + width)

struct OBMetrics: Equatable {
    var width: CGFloat = 402
    var height: CGFloat = 874
    var safeTop: CGFloat = 62
    var safeBottom: CGFloat = 34

    /// CSS container-query width unit.
    func cqw(_ v: CGFloat) -> CGFloat { width * v / 100 }
    /// `.screen` padding: top = safe + 10, bottom = safe + 8 + dock + 16.
    var contentTop: CGFloat { safeTop + 10 }
    func contentBottom(extra: CGFloat = 0) -> CGFloat { safeBottom + 8 + OB.dockHeight + 16 + extra }
    func contentHeight(extra: CGFloat = 0) -> CGFloat { height - contentTop - contentBottom(extra: extra) }
    var contentWidth: CGFloat { width - OB.pad * 2 }

    // Display sizes (.display.xl / .l / .m, connect's override).
    var displayXL: CGFloat { cqw(15.4) }
    var displayL: CGFloat { cqw(17) }
    var displayM: CGFloat { cqw(13.4) }
    var displayConnect: CGFloat { cqw(14.8) }
}

private struct OBMetricsKey: EnvironmentKey { static let defaultValue = OBMetrics() }
extension EnvironmentValues {
    var obMetrics: OBMetrics {
        get { self[OBMetricsKey.self] }
        set { self[OBMetricsKey.self] = newValue }
    }
}

/// Reads the safe areas once at the top and hands them down, then lays the
/// content out full-bleed (the prototype positions everything against them).
struct OBMetricsReader<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geo in
            let m = OBMetrics(width: geo.size.width,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom,
                              safeTop: geo.safeAreaInsets.top,
                              safeBottom: geo.safeAreaInsets.bottom)
            content
                .environment(\.obMetrics, m)
                .frame(width: m.width, height: m.height)
                .offset(y: -geo.safeAreaInsets.top)
        }
    }
}

// MARK: - Fonts

enum OBFont {
    enum Cabinet: String, CaseIterable {
        case medium = "CabinetGrotesk-Medium"
        case bold = "CabinetGrotesk-Bold"
        case extrabold = "CabinetGrotesk-Extrabold"
        case black = "CabinetGrotesk-Black"
    }

    /// UIAppFonts registers these at launch; this is a belt-and-braces
    /// fallback (and makes previews/tests independent of Info.plist).
    private static let registered: Void = {
        for face in Cabinet.allCases where UIFont(name: face.rawValue, size: 12) == nil {
            if let url = Bundle.main.url(forResource: face.rawValue, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func ui(_ face: Cabinet, _ size: CGFloat) -> UIFont {
        _ = registered
        return UIFont(name: face.rawValue, size: size) ?? .systemFont(ofSize: size, weight: .black)
    }
    static func cabinet(_ face: Cabinet, _ size: CGFloat) -> Font {
        _ = registered
        return .custom(face.rawValue, fixedSize: size)
    }
    /// `ui-monospace` 500.
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
    /// `-apple-system`.
    static func sf(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    /// Width of `s` in Cabinet with CSS letter-spacing `kern` (applied after every character).
    static func width(_ s: String, _ face: Cabinet, _ size: CGFloat, kern: CGFloat) -> CGFloat {
        let attr = NSAttributedString(string: s, attributes: [.font: ui(face, size), .kern: kern])
        return ceil(attr.size().width * 100) / 100
    }
    /// CSS `ch` for Cabinet Medium.
    static func ch(_ size: CGFloat) -> CGFloat { width("0", .medium, size, kern: 0) }
}

// MARK: - Display headline (Cabinet Black, tracking -0.045em, line-height .88,
// lime highlight chip rotated -2.5°)

struct OBRun: Equatable {
    enum Kind: Equatable { case text, chip, space }
    var kind: Kind
    var text: String
}

enum OBTitleLayout {
    /// `markup`: explicit breaks with "\n", the highlighted phrase in [brackets].
    /// Words wrap greedily inside `maxWidth` like the browser; the highlight
    /// never breaks (it is an inline-block in the prototype).
    static func lines(_ markup: String, size: CGFloat, maxWidth: CGFloat) -> [[OBRun]] {
        let kern = -0.045 * size
        func w(_ s: String) -> CGFloat { OBFont.width(s, .black, size, kern: kern) }
        let space = w(" ")
        var out: [[OBRun]] = []
        for paragraph in markup.components(separatedBy: "\n") {
            // tokens: (text, isChip)
            var tokens: [(String, Bool)] = []
            var rest = Substring(paragraph)
            while !rest.isEmpty {
                if rest.first == "[" , let close = rest.firstIndex(of: "]") {
                    tokens.append((String(rest[rest.index(after: rest.startIndex)..<close]), true))
                    rest = rest[rest.index(after: close)...]
                } else {
                    let stop = rest.firstIndex(where: { $0 == " " || $0 == "[" }) ?? rest.endIndex
                    if stop == rest.startIndex { rest = rest.dropFirst(); tokens.append((" ", false)); continue }
                    tokens.append((String(rest[..<stop]), false))
                    rest = rest[stop...]
                }
            }
            // Greedy wrap on word boundaries (" " tokens).
            var line: [(String, Bool)] = []
            var lineW: CGFloat = 0
            func tokW(_ t: (String, Bool)) -> CGFloat {
                t.0 == " " && !t.1 ? space : (t.1 ? w(t.0) + 0.18 * size : w(t.0))
            }
            for t in tokens {
                if t.0 == " " && !t.1 {
                    if !line.isEmpty { line.append(t); lineW += space }
                    continue
                }
                let tw = tokW(t)
                let trimmed = line.last.map { $0.0 == " " && !$0.1 } ?? false
                if !line.isEmpty && lineW + tw > maxWidth + 0.5 && trimmed {
                    line.removeLast()
                    out.append(runs(line))
                    line = []; lineW = 0
                }
                line.append(t); lineW += tw
            }
            while let last = line.last, last.0 == " " && !last.1 { line.removeLast() }
            out.append(runs(line))
        }
        return out
    }

    private static func runs(_ tokens: [(String, Bool)]) -> [OBRun] {
        var r: [OBRun] = []
        for t in tokens {
            if t.1 { r.append(OBRun(kind: .chip, text: t.0)) }
            else if t.0 == " " { r.append(OBRun(kind: .space, text: " ")) }
            else if let last = r.last, last.kind == .text { r[r.count - 1].text += t.0 }
            else { r.append(OBRun(kind: .text, text: t.0)) }
        }
        return r
    }

    /// Widest line, for the "step down one size if it won't fit" rule on real data.
    static func fits(_ markup: String, size: CGFloat, maxWidth: CGFloat, maxLines: Int) -> Bool {
        let ls = lines(markup, size: size, maxWidth: maxWidth)
        guard ls.count <= maxLines else { return false }
        let kern = -0.045 * size
        for l in ls {
            var total: CGFloat = 0
            for r in l {
                switch r.kind {
                case .space: total += OBFont.width(" ", .black, size, kern: kern)
                case .text: total += OBFont.width(r.text, .black, size, kern: kern)
                case .chip: total += OBFont.width(r.text, .black, size, kern: kern) + 0.18 * size
                }
            }
            if total > maxWidth + 0.5 { return false }
        }
        return true
    }
}

struct OBDisplayTitle: View {
    let markup: String
    let size: CGFloat
    var maxWidth: CGFloat? = nil
    /// Real-data titles step down (l → m → smaller) until they fit in 3 lines.
    var autoFit = false
    @Environment(\.obMetrics) private var m

    var body: some View {
        let width = maxWidth ?? m.contentWidth
        let s = resolvedSize(width)
        let lines = OBTitleLayout.lines(markup, size: s, maxWidth: width)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, runs in
                OBTitleLine(runs: runs, size: s)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(markup.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
        .accessibilityAddTraits(.isHeader)
    }

    private func resolvedSize(_ width: CGFloat) -> CGFloat {
        guard autoFit else { return size }
        var s = size
        while s > 30 && !OBTitleLayout.fits(markup, size: s, maxWidth: width, maxLines: 3) {
            s = s > m.displayM + 0.5 ? m.displayM : s - 4
        }
        return s
    }
}

private struct OBTitleLine: View {
    let runs: [OBRun]
    let size: CGFloat

    var body: some View {
        let hasChip = runs.contains { $0.kind == .chip }
        // CSS line box: .88em (strut), or .92em when it holds the .9-line-height chip.
        let lineH = size * (hasChip ? 0.92 : 0.88)
        let baseline = size * (hasChip ? 0.745 : 0.735)
        let font = OBFont.cabinet(.black, size)
        let kern = -0.045 * size
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, r in
                switch r.kind {
                case .space:
                    Text(" ").font(font).tracking(kern).hidden()
                        .frame(width: OBFont.width(" ", .black, size, kern: kern))
                case .text:
                    Text(r.text).font(font).tracking(kern).foregroundStyle(OB.paper)
                        .fixedSize()
                case .chip:
                    OBHighlightChip(text: r.text, size: size)
                }
            }
        }
        .alignmentGuide(.top) { d in d[.firstTextBaseline] - baseline }
        .frame(height: lineH, alignment: .topLeading)
    }
}

/// `.hl`: lime chip, ink text, padding 0 .1em .02em, radius .12em,
/// rotate(-2.5deg), line-height .9, margin-left -.02em.
struct OBHighlightChip: View {
    let text: String
    let size: CGFloat
    var body: some View {
        Text(text)
            .font(OBFont.cabinet(.black, size))
            .tracking(-0.045 * size)
            .foregroundStyle(OB.ink)
            .fixedSize()
            .padding(.horizontal, 0.1 * size)
            .background(alignment: Alignment(horizontal: .center, vertical: .firstTextBaseline)) {
                RoundedRectangle(cornerRadius: 0.12 * size, style: .circular)
                    .fill(OB.lime)
                    .frame(height: 0.92 * size)
                    .alignmentGuide(.firstTextBaseline) { _ in 0.745 * size }
            }
            .rotationEffect(.degrees(-2.5))
            .padding(.leading, -0.02 * size)
    }
}

// MARK: - Body copy (.sub) and kickers (.mono)

/// `.sub`: Cabinet 500, 17px (16px `.tight`), line-height 1.32, paper @74%,
/// tracking -0.005em, max-width 31ch. `**bold**` runs are Cabinet 800.
struct OBSub: View {
    let text: String
    var size: CGFloat = 16
    var maxCh: CGFloat = 31
    var centered = false
    var opacity: Double = 0.74

    var body: some View {
        let ui = OBFont.ui(.medium, size)
        let natural = ui.lineHeight
        let lineBox = size * 1.32
        // CSS centres the 1.15em content area in the 1.32em line box.
        let half = (lineBox - size * 1.15) / 2
        OBSub.styled(text, size: size)
            .tracking(-0.005 * size)
            .foregroundStyle(OB.paper)
            .lineSpacing(max(0, lineBox - natural))
            .multilineTextAlignment(centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, half)
            .padding(.bottom, max(0, lineBox - natural - half))
            .frame(maxWidth: OBFont.ch(size) * maxCh, alignment: centered ? .center : .leading)
            .opacity(opacity)
    }

    static func styled(_ s: String, size: CGFloat) -> Text {
        var result = Text("")
        var bold = false
        for part in s.components(separatedBy: "**") {
            if !part.isEmpty {
                result = result + Text(part).font(OBFont.cabinet(bold ? .extrabold : .medium, size))
            }
            bold.toggle()
        }
        return result
    }
}

/// `.mono`: ui-monospace 500, uppercase, tracking .14em.
struct OBMono: View {
    let text: String
    var size: CGFloat = 10.5
    var color: Color = OB.paper
    var opacity: Double = 1
    var tracking: CGFloat = 0.14
    var body: some View {
        Text(text.uppercased())
            .font(OBFont.mono(size))
            .tracking(tracking * size)
            .foregroundStyle(color)
            .opacity(opacity)
            .lineLimit(1)
    }
}

/// `.eyebrow`: lime mono @90%, margin 2px 0 12px.
struct OBEyebrow: View {
    let text: String
    var body: some View {
        OBMono(text: text, color: OB.lime, opacity: 0.9)
            .padding(.top, 2)
            .padding(.bottom, 12)
    }
}

// MARK: - Entrance (`rise`) and count-ups

/// `rise(d)`: y 36 → 0 + fade, spring(260, 26), delay d.
struct OBRise: ViewModifier {
    let delay: Double
    var dy: CGFloat = 36
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .offset(y: on ? 0 : dy)
            .opacity(on ? 1 : 0)
            .onAppear {
                if reduceMotion { on = true; return }
                withAnimation(OB.spring(260, 26).delay(delay)) { on = true }
            }
    }
}
extension View {
    func obRise(_ delay: Double) -> some View { modifier(OBRise(delay: delay)) }
}

/// Animatable number text: interpolates `value` every frame.
struct OBNumberText: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(format(value)) }
}

/// `useCountUp(to, delay, dur)`: 0 → to with ease-out cubic.
struct OBCountUp: View {
    let to: Double
    var delay: Double = 0
    var duration: Double = 1.2
    var format: (Double) -> String = { "\(Int($0.rounded()))" }
    @State private var v: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        OBNumberText(value: v, format: format)
            .task(id: to) {
                if reduceMotion { v = to; return }
                v = 0
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(OB.easeOutCubic(duration)) { v = to }
            }
    }
}

// MARK: - CSS box-shadow

extension View {
    /// CSS `box-shadow: x y blur spread color` behind a shape.
    func obShadow<S: InsettableShape>(_ shape: S, color: Color, x: CGFloat = 0, y: CGFloat = 0,
                                      blur: CGFloat, spread: CGFloat = 0) -> some View {
        background(
            shape.inset(by: -spread)
                .fill(color)
                .offset(x: x, y: y)
                .blur(radius: blur / 2)
        )
    }
    /// CSS `box-shadow: 0 0 0 w color` (outer ring).
    func obRing(cornerRadius: CGFloat, color: Color, width: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius + width / 2, style: .circular)
                .stroke(color, lineWidth: width)
                .padding(-width / 2)
        )
    }
}

// MARK: - Stickers and doodles

/// `.sticker`: Cabinet 900, 15px, tracking -0.01em, padding 6 12 7, pill,
/// shadow 0 6 16 rgba(0,0,0,.3); paper or lime.
struct OBSticker: View {
    enum Tone { case paper, lime }
    let text: String
    var tone: Tone = .paper
    var rotation: Double = -4
    var size: CGFloat = 15
    var body: some View {
        Text(text)
            .font(OBFont.cabinet(.black, size))
            .tracking(-0.01 * size)
            .foregroundStyle(OB.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.top, 6).padding(.bottom, 7).padding(.horizontal, 12)
            .background(Capsule().fill(tone == .paper ? OB.paper : OB.lime))
            .obShadow(Capsule(), color: .black.opacity(0.3), y: 6, blur: 16)
            .rotationEffect(.degrees(rotation))
    }
}

/// Lime starburst doodle (viewBox 80).
struct OBStarburst: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 80
        var p = Path()
        for i in 0..<9 {
            let a = Double(i) / 9 * .pi * 2 + 0.2
            let r1 = 9.0 + Double(i % 2) * 3, r2 = 26.0 + Double(i % 3) * 4
            p.move(to: CGPoint(x: rect.minX + (40 + cos(a) * r1) * k, y: rect.minY + (40 + sin(a) * r1) * k))
            p.addLine(to: CGPoint(x: rect.minX + (40 + cos(a) * r2) * k, y: rect.minY + (40 + sin(a) * r2) * k))
        }
        return p
    }
}

/// Paper sparkle doodle (viewBox 40).
struct OBSparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 40
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var p = Path()
        p.move(to: pt(20, 3))
        p.addCurve(to: pt(37, 20), control1: pt(21, 13), control2: pt(24, 18))
        p.addCurve(to: pt(20, 37), control1: pt(24, 22), control2: pt(21, 27))
        p.addCurve(to: pt(3, 20), control1: pt(19, 27), control2: pt(16, 22))
        p.addCurve(to: pt(20, 3), control1: pt(16, 18), control2: pt(19, 13))
        p.closeSubpath()
        return p
    }
}

// MARK: - Genre pill (GenrePillContent values; compact = 12.5px, 7×13)

struct OBGenrePill: View {
    let genre: String
    let on: Bool
    let color: Color
    var compact = false
    var fixedWidth: CGFloat? = nil
    var verticalPadding: CGFloat? = nil
    var horizontalPadding: CGFloat? = nil

    var body: some View {
        Text(genre.capitalized)
            .font(.system(size: compact ? 12.5 : 14, weight: on ? .semibold : .medium))
            .foregroundStyle(on ? Theme.Colors.textOnGenreColor(color) : Color.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, verticalPadding ?? (compact ? 7 : 10))
            .padding(.horizontal, horizontalPadding ?? (compact ? 13 : 16))
            .frame(width: fixedWidth)
            .background(Capsule().fill(on ? color : OB.graphite))
            .shadow(color: on ? color.opacity(0.45) : .clear, radius: 4, x: 0, y: 2)
            .scaleEffect(on ? 1.02 : 1)
    }
}

/// flex-wrap row.
struct OBFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat? = nil
    var centered = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let h = rows.reduce(0) { $0 + $1.h } + CGFloat(max(0, rows.count - 1)) * (lineSpacing ?? spacing)
        let w = rows.map(\.w).max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (centered ? (bounds.width - row.w) / 2 : 0)
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.h - s.height) / 2), proposal: .unspecified)
                x += s.width + spacing
            }
            y += row.h + (lineSpacing ?? spacing)
        }
    }
    private struct Row { var items: [Int] = []; var w: CGFloat = 0; var h: CGFloat = 0 }
    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var cur = Row()
        for (i, sv) in subviews.enumerated() {
            let s = sv.sizeThatFits(.unspecified)
            let add = cur.items.isEmpty ? s.width : cur.w + spacing + s.width
            if add > width + 0.5 && !cur.items.isEmpty {
                rows.append(cur); cur = Row()
                cur.items = [i]; cur.w = s.width; cur.h = s.height
            } else {
                cur.items.append(i); cur.w = add; cur.h = max(cur.h, s.height)
            }
        }
        if !cur.items.isEmpty { rows.append(cur) }
        return rows
    }
}

// MARK: - Dock: page dots + Next / brand buttons

/// `.dots`: 26pt pill rgba(120,120,128,.28), 7pt dots, gap 9, active white ×1.08, inactive white 38%.
struct OBPageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<count, id: \.self) { k in
                Circle()
                    .fill(k == index ? Color.white : Color.white.opacity(0.38))
                    .frame(width: 7, height: 7)
                    .scaleEffect(k == index ? 1.08 : 1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Capsule().fill(Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.28)))
        .animation(.easeInOut(duration: 0.25), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

/// `.cta`: 56pt flat lime capsule, SF 16/600, tracking -0.01em, shadow 0 5 10
/// lime@30%, inset top highlight white@55%, sheen white 22% → 0 over 55%,
/// press ×.97. `.cta.brand`: label left-aligned at 22pt, gap 14.
struct OBCTAStyle: ButtonStyle {
    var brand = false
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .tracking(-0.16)
            .foregroundStyle(OB.ink)
            .frame(maxWidth: .infinity, alignment: brand ? .leading : .center)
            .padding(.leading, brand ? 22 : 0)
            .frame(height: 56)
            .background(
                ZStack {
                    Capsule().fill(OB.lime)
                    Capsule().fill(LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0),
                                                          .init(color: .white.opacity(0), location: 0.55)],
                                                  startPoint: .top, endPoint: .bottom))
                    Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                        .mask(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.06)],
                                             startPoint: .top, endPoint: .bottom))
                    Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0.94), .init(color: .white, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                }
                .shadow(color: OB.lime.opacity(0.3), radius: 5, x: 0, y: 5)
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.38)
            .animation(OB.spring(420, 32), value: configuration.isPressed)
            .animation(OB.spring(420, 32), value: enabled)
    }
}

struct OBNextButton: View {
    var title = "Next"
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: { if enabled { action() } }) { Text(title) }
            .buttonStyle(OBCTAStyle(enabled: enabled))
            .allowsHitTesting(enabled)
            .accessibilityAddTraits(enabled ? [] : .isStaticText)
    }
}

/// Official brand mark on the prototype's 30pt white circle tile
/// (inset ring rgba(11,11,15,.08)). Spotify icon 22pt (Spotify's 21pt digital
/// minimum); Apple Music icon 20pt. Both unaltered official artwork.
struct OBBrandTile: View {
    enum Brand { case spotify, appleMusic }
    let brand: Brand
    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().strokeBorder(OB.ink.opacity(0.08), lineWidth: 1)
            switch brand {
            case .spotify:
                Image("brand-spotify-icon").resizable().interpolation(.high).scaledToFit().frame(width: 22, height: 22)
            case .appleMusic:
                Image("brand-applemusic-icon").resizable().interpolation(.high).scaledToFit().frame(width: 20, height: 20)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

struct OBBrandButton: View {
    let brand: OBBrandTile.Brand
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                OBBrandTile(brand: brand)
                Text(brand == .spotify ? "Continue with Spotify" : "Continue with Apple Music")
                if busy { ProgressView().tint(OB.ink).padding(.leading, 4) }
            }
        }
        .buttonStyle(OBCTAStyle(brand: true))
        .disabled(busy)
    }
}

/// `.dock`: pinned at safe bottom + 8, dots then Next (gap 14), or on the
/// connect screen dots (+4) and two brand buttons (gap 10).
struct OBDock<Buttons: View>: View {
    var dots: (count: Int, index: Int)?
    var two = false
    @ViewBuilder var buttons: Buttons
    @Environment(\.obMetrics) private var m
    var body: some View {
        VStack(spacing: two ? 10 : 14) {
            if let dots {
                OBPageDots(count: dots.count, index: dots.index).padding(.bottom, two ? 4 : 0)
            } else {
                Color.clear.frame(height: 26)
            }
            buttons
        }
        .padding(.horizontal, OB.pad)
        .padding(.bottom, m.safeBottom + 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Screen scaffold and pager transition

/// `.screen`: column with the prototype's paddings against the safe areas.
struct OBScreen<Content: View>: View {
    var extraBottom: CGFloat = 0
    @ViewBuilder var content: Content
    @Environment(\.obMetrics) private var m
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.top, m.contentTop)
            .padding(.horizontal, OB.pad)
            .padding(.bottom, m.contentBottom(extra: extraBottom))
            .frame(width: m.width, height: m.height, alignment: .topLeading)
    }
}

/// New screen slides 60pt + fades in; old one slides 60pt the other way and fades out.
struct OBSlide: ViewModifier {
    let x: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.offset(x: x).opacity(opacity) }
}
extension AnyTransition {
    static func obPage(_ dir: CGFloat) -> AnyTransition {
        .asymmetric(insertion: .modifier(active: OBSlide(x: dir * 60, opacity: 0), identity: OBSlide(x: 0, opacity: 1)),
                    removal: .modifier(active: OBSlide(x: -dir * 60, opacity: 0), identity: OBSlide(x: 0, opacity: 1)))
    }
}
extension OB {
    /// Screen change spring (300 / 34).
    static var pageSpring: Animation { spring(300, 34) }
}

// MARK: - Owned sample covers (generated originals, fictional names)

struct OBTrack: Equatable {
    let art: String       // asset name
    let track: String
    let artist: String
    let genre: String
}

enum OBCatalog {
    /// Same order and roles as the prototype's tracks.json; every image is an
    /// original generated cover and every name is made up.
    static let tracks: [OBTrack] = [
        OBTrack(art: "obcover-orbit", track: "Orbit 3", artist: "Ilse Marrow", genre: "Jazz"),
        OBTrack(art: "obcover-tigers", track: "Paper Tigers", artist: "Lua Ventana", genre: "Indie Pop"),
        OBTrack(art: "obcover-dust", track: "Dust & Brass", artist: "Los Vela", genre: "Instrumental"),
        OBTrack(art: "obcover-glass", track: "Morning Glass", artist: "Imani Rae", genre: "R&B/Soul"),
        OBTrack(art: "obcover-lowtide", track: "Low Tide", artist: "Kwelo", genre: "Electronic"),
        OBTrack(art: "obcover-rosewater", track: "Rosewater", artist: "Sela Moon", genre: "R&B/Soul"),
        OBTrack(art: "obcover-mesa", track: "Mesa Hours", artist: "Tierra Swim", genre: "Indie Rock"),
        OBTrack(art: "obcover-velvet", track: "Velvet Prayer", artist: "Noor Hale", genre: "Worldwide"),
        OBTrack(art: "obcover-gently", track: "Gently", artist: "Wren Abara", genre: "Alternative"),
        OBTrack(art: "obcover-ember", track: "Ember", artist: "Nine Rooms", genre: "Alternative"),
        OBTrack(art: "obcover-static", track: "Strawberry Static", artist: "Les Comètes", genre: "Electronic"),
        OBTrack(art: "obcover-slowly", track: "Show Me Slowly", artist: "Paler Kin", genre: "Pop"),
    ]
    static func named(_ key: String) -> OBTrack { tracks.first { $0.art == "obcover-" + key } ?? tracks[0] }
}

struct OBCover: View {
    let art: String
    var size: CGFloat
    var radius: CGFloat
    var body: some View {
        Image(art)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
            .accessibilityHidden(true)
    }
}

/// Horizontal `.mq` marquee: two copies, translateX 0 → -50% linear, looping.
struct OBMarquee: View {
    let items: [OBTrack]
    let cover: CGFloat
    let radius: CGFloat
    var gap: CGFloat = 10
    let duration: Double
    var reverse = false
    var shadow = true
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // CSS: two copies in a row sliding 0 → -50% (one copy per cycle).
        // Each cover is offset on its own from x = 0 so nothing sits far
        // outside the screen (SwiftUI culls far-offscreen layout).
        let step = cover + gap
        let period = CGFloat(items.count) * step
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSince(start)
            let f = CGFloat((t / duration).truncatingRemainder(dividingBy: 1))
            let shift = period * (reverse ? 1 - f : f)
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, tr in
                    let x0 = (CGFloat(i) * step - shift).truncatingRemainder(dividingBy: period)
                    let x = x0 < 0 ? x0 + period : x0
                    ForEach([x, x - period, x + period], id: \.self) { xi in
                        if xi > -step && xi < period + step {
                            OBCover(art: tr.art, size: cover, radius: radius)
                                .obShadow(RoundedRectangle(cornerRadius: radius), color: shadow ? .black.opacity(0.7) : .clear,
                                          y: 10, blur: 24, spread: -10)
                                .offset(x: xi)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: cover)
        .clipped()
        .onAppear { start = Date() }
    }
}
