//
//  OBGlow.swift
//  HiddenJams
//
//  The prototype's animated background (Glow.tsx), same maths on the CPU:
//  ink → plum vertical base, three gaussian blooms per screen (magenta,
//  violet, lime) with per-screen position / size / intensity, slow drift
//  (0.35 / 0.29 Hz, ±0.035), cross-fade between screens (k = 1 − e^(−3.2·dt)),
//  tone-map col / (1 + 0.35·col), ±1.4% film grain, and the lime pulse on
//  genre taps (decay e^(−2.5·t)). The field is smooth, so it is evaluated
//  on a small grid and scaled up; grain is drawn at full resolution.
//

import SwiftUI
import UIKit

private struct OBBloom {
    var c: SIMD3<Double>
    var p: SIMD2<Double>
    var s: Double
    var i: Double
}

final class OBGlowField {
    // three.js r169 colour management stores `new Color('#hex')` in linear
    // sRGB and the raw ShaderMaterial writes it out untouched, so the
    // prototype's bloom colours are the linearised hex values.
    private static func lin(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> {
        func f(_ c: Double) -> Double { let v = c / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return SIMD3(f(r), f(g), f(b))
    }
    static let magenta = lin(224, 86, 181)
    static let violet = lin(142, 77, 224)
    static let lime = lin(200, 232, 107)

    private var blooms: [OBBloom] = [
        OBBloom(c: OBGlowField.magenta, p: [0.5, 0.7], s: 0.3, i: 0),
        OBBloom(c: OBGlowField.violet, p: [0.1, 0.9], s: 0.4, i: 0),
        OBBloom(c: OBGlowField.violet, p: [0.9, 0.5], s: 0.3, i: 0),
    ]
    private(set) var time: Double = 0
    private var last: Date?
    var pulse: Double = 0
    private var lastPulseToken = 0

    /// Glow.tsx `targets(screen)`; p is in GL uv (y up).
    private func targets(_ screen: Int) -> [OBBloom] {
        let M = Self.magenta, V = Self.violet, L = Self.lime
        switch screen {
        case 0: return [.init(c: M, p: [0.5, 0.78], s: 0.26, i: 0.5), .init(c: V, p: [0.1, 0.98], s: 0.34, i: 0.5), .init(c: V, p: [0.98, 0.55], s: 0.22, i: 0.22)]
        case 1: return [.init(c: M, p: [0.5, 0.52], s: 0.34, i: 0.4), .init(c: V, p: [0.9, 0.98], s: 0.32, i: 0.35), .init(c: L, p: [0.1, 0.3], s: 0.22, i: 0.12)]
        case 2: return [.init(c: V, p: [0.5, 0.62], s: 0.4, i: 0.5), .init(c: M, p: [0.85, 0.3], s: 0.3, i: 0.28), .init(c: L, p: [0.5, 0.92], s: 0.3, i: 0.34)]
        case 3: return [.init(c: L, p: [0.15, 0.55], s: 0.3, i: 0.28 + pulse * 0.25), .init(c: V, p: [0.86, 0.4], s: 0.36, i: 0.5), .init(c: M, p: [0.55, 0.95], s: 0.32, i: 0.3)]
        case 4: return [.init(c: M, p: [0.6, 0.95], s: 0.3, i: 0.32), .init(c: V, p: [0.1, 0.55], s: 0.4, i: 0.5), .init(c: L, p: [0.5, 0.12], s: 0.26, i: 0.2)]
        case 5: return [.init(c: V, p: [0.5, 0.4], s: 0.42, i: 0.55), .init(c: M, p: [0.1, 0.9], s: 0.34, i: 0.32), .init(c: L, p: [0.9, 0.7], s: 0.28, i: 0.25)]
        case 6: return [.init(c: L, p: [0.2, 0.45], s: 0.3, i: 0.22), .init(c: V, p: [0.85, 0.35], s: 0.4, i: 0.5), .init(c: M, p: [0.5, 0.95], s: 0.34, i: 0.34)]
        case 7: return [.init(c: L, p: [0.5, 0.42], s: 0.34, i: 0.34), .init(c: M, p: [0.1, 0.85], s: 0.36, i: 0.4), .init(c: V, p: [0.9, 0.7], s: 0.4, i: 0.5)]
        case 8: return [.init(c: M, p: [0.3, 0.5], s: 0.36, i: 0.4), .init(c: V, p: [0.8, 0.8], s: 0.4, i: 0.5), .init(c: L, p: [0.7, 0.15], s: 0.26, i: 0.2)]
        default: return [.init(c: L, p: [0.5, 0.5], s: 0.3, i: 0.3), .init(c: M, p: [0.15, 0.85], s: 0.38, i: 0.42), .init(c: V, p: [0.88, 0.45], s: 0.4, i: 0.5)]
        }
    }

    func step(to date: Date, screen: Int, pulseToken: Int) {
        if pulseToken != lastPulseToken { lastPulseToken = pulseToken; pulse = 1 }
        let dt = min(0.1, max(0, last.map { date.timeIntervalSince($0) } ?? 0))
        last = date
        time += dt
        let t = targets(screen)
        let k = 1 - exp(-dt * 3.2)
        for n in 0..<3 {
            blooms[n].c += (t[n].c - blooms[n].c) * k
            blooms[n].p += (t[n].p - blooms[n].p) * k
            blooms[n].s += (t[n].s - blooms[n].s) * k
            blooms[n].i += (t[n].i - blooms[n].i) * k
        }
        pulse *= exp(-dt * 2.5)
    }

    /// Glow.tsx fragment shader, without grain, on a gw × gh grid.
    func render(aspect: Double, gw: Int = 96) -> CGImage? {
        let gh = max(2, Int((Double(gw) / aspect).rounded()))
        var px = [UInt8](repeating: 255, count: gw * gh * 4)
        let base0 = SIMD3<Double>(0.043, 0.043, 0.059), base1 = SIMD3<Double>(0.110, 0.063, 0.141)
        var centers: [SIMD2<Double>] = []
        for (k, b) in blooms.enumerated() {
            let fk = Double(k)
            centers.append(SIMD2(b.p.x * aspect, b.p.y) + 0.035 * SIMD2(sin(time * 0.35 + fk * 2.1), cos(time * 0.29 + fk * 1.3)))
        }
        for y in 0..<gh {
            // texel centres; GL uv has y up, image rows go down
            let vy = 1 - (Double(y) + 0.5) / Double(gh)
            let sm = vy * vy * (3 - 2 * vy)
            let base = base0 + (base1 - base0) * (sm * 0.85)
            for x in 0..<gw {
                let vx = (Double(x) + 0.5) / Double(gw)
                let p = SIMD2(vx * aspect, vy)
                var col = base
                for (k, b) in blooms.enumerated() {
                    var d = p - centers[k]
                    d.x *= 0.85
                    let g = exp(-(d.x * d.x + d.y * d.y) / (b.s * b.s * 0.5))
                    col += b.c * (g * b.i)
                }
                col = col / (1 + col * 0.35)
                let o = (y * gw + x) * 4
                px[o] = UInt8(max(0, min(255, (col.x * 255).rounded())))
                px[o + 1] = UInt8(max(0, min(255, (col.y * 255).rounded())))
                px[o + 2] = UInt8(max(0, min(255, (col.z * 255).rounded())))
            }
        }
        let data = Data(px) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: gw, height: gh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: gw * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// ±1.4% grain tiles (white for +, black for −), regenerated offsets per frame.
    static let grain: (light: CGImage?, dark: CGImage?) = {
        let n = 192
        var light = [UInt8](repeating: 0, count: n * n * 4)
        var dark = [UInt8](repeating: 0, count: n * n * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(n * n) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = Double(seed >> 11) / Double(1 << 53) - 0.5   // −0.5…0.5
            if v > 0 {
                // premultiplied white with alpha = v·0.028
                let a = UInt8((v * 0.028 * 255).rounded())
                light[i * 4] = a; light[i * 4 + 1] = a; light[i * 4 + 2] = a; light[i * 4 + 3] = a
            } else {
                // black over a dark base: alpha scaled so the drop ≈ |v|·0.028 at col ≈ 0.08
                let a = UInt8(min(255, (-v * 0.028 / 0.08 * 255).rounded()))
                dark[i * 4 + 3] = a
            }
        }
        func make(_ b: [UInt8]) -> CGImage? {
            guard let p = CGDataProvider(data: Data(b) as CFData) else { return nil }
            return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        return (make(light), make(dark))
    }()
}

/// Full-bleed animated background. `screen` uses the prototype's indices
/// (0-4 intro, 5 analysis, 6 genres, 7 rarity, 8 artists, 9+ deepest / fresh).
struct OBGlowBackground: View {
    let screen: Int
    var pulseToken: Int = 0
    @State private var field = OBGlowField()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas(rendersAsynchronously: false) { ctx, size in
                field.step(to: tl.date, screen: screen, pulseToken: pulseToken)
                guard size.width > 0, size.height > 0 else { return }
                if let img = field.render(aspect: Double(size.width / size.height)) {
                    ctx.draw(Image(decorative: img, scale: 1).resizable().interpolation(.high),
                             in: CGRect(origin: .zero, size: size))
                }
                guard !reduceMotion else { return }
                // grain: ~2 device px cells like the prototype's DPR-2 canvas
                let tile: CGFloat = 192 / 1.5
                let ox = CGFloat(Int(field.time * 977) % 97), oy = CGFloat(Int(field.time * 613) % 89)
                for g in [OBGlowField.grain.light, OBGlowField.grain.dark] {
                    guard let g else { continue }
                    let image = Image(decorative: g, scale: 1.5)
                    var y = -oy
                    while y < size.height {
                        var x = -ox
                        while x < size.width {
                            ctx.draw(image, in: CGRect(x: x, y: y, width: tile, height: tile))
                            x += tile
                        }
                        y += tile
                    }
                }
            }
        }
        .background(OB.ink)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
