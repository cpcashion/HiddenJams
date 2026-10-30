//
//  Theme.swift
//  SpotifyHiddenGems
//
//  App-wide design system with Hidden Jams aesthetic
//

import SwiftUI

struct Theme {
    // MARK: - Colors
    
    struct Colors {
        // All colors are computed from the current appearance mode so the
        // whole UI re-themes instantly when the user flips the switch.
        // Build 76 ("too much blue" redesign, Chris's Oct 29 references):
        // Dark  = near-black + plum canvas with a pink/purple ambient glow,
        //         lime accent, pastel cards (lavender/pink/peach/mint/butter).
        // Light = warm off-white canvas, same pastel cards, deep plum accent
        //         text with lime CTAs.
        // Blue is intentionally gone from the palette.
        private static var isLight: Bool { ThemeManager.shared.isLight }

        // MARK: Base palette (raw hex tokens)
        static let ink = Color(hex: "0B0B0F")        // near-black canvas
        static let plum = Color(hex: "1C1024")       // deep aubergine
        static let plumDeep = Color(hex: "120A18")
        static let plumButton = Color(hex: "3B1A4F") // dark purple play disc on pastel cards
        static let graphite = Color(hex: "1E1E24")   // unselected chips / secondary surface
        static let graphiteHigh = Color(hex: "2A2A32")
        static let lime = Color(hex: "C8E86B")       // primary accent
        static let limeDeep = Color(hex: "A8CC45")
        static let lavender = Color(hex: "C9A0F0")
        static let pink = Color(hex: "F6B8D1")
        static let peach = Color(hex: "F9C9A8")
        static let mint = Color(hex: "B8E6C9")
        static let butter = Color(hex: "F3E59A")
        static let magentaGlow = Color(hex: "E056B5")
        static let violetGlow = Color(hex: "8E4DE0")
        static let paper = Color(hex: "F7F3EE")      // light-mode canvas

        /// Pastel card palette, in display order.
        static let pastels: [Color] = [lavender, pink, peach, mint, butter, lime]

        /// Deterministic pastel for a given index (wraps).
        static func pastel(_ index: Int) -> Color {
            pastels[((index % pastels.count) + pastels.count) % pastels.count]
        }

        /// Text/icon color on pastel and lime surfaces — always near-black
        /// (all pastels have luminance > 0.55, so contrast is > 10:1).
        static let textOnPastel = Color(hex: "0B0B0F")
        static let textOnPastelSecondary = Color(hex: "0B0B0F").opacity(0.68)

        // Brand Colors
        static var gemGold: Color { // Primary accent: lime (dark), deep plum-violet text accent (light)
            isLight ? Color(hex: "6B2FA0") : lime
        }
        static var gemGoldLight: Color {
            isLight ? lavender : Color(hex: "DDF29A")
        }
        static var gemGoldDark: Color {
            isLight ? Color(hex: "4A1D73") : limeDeep
        }
        /// CTA fill (buttons, selected chips, primary play). Lime in both
        /// modes — black text on lime is ~14:1.
        static var ctaFill: Color { lime }
        static var spotifyGreen: Color { lime } // CTA alias for compatibility
        static var spotifyBlack: Color { // Primary background
            isLight ? paper : ink
        }
        static var spotifyDarkGray: Color { // Secondary background
            isLight ? Color(hex: "EDE6DE") : graphite
        }
        /// Unselected chip / pill fill.
        static var chipFill: Color {
            isLight ? Color(hex: "E9E1D8") : graphite
        }
        /// Card surface for non-pastel cards.
        static var surface: Color {
            isLight ? Color.white : Color(hex: "17151C")
        }

        // Brand Gradients
        static var primaryGradient: LinearGradient {
            LinearGradient(
                colors: [lime, mint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static var goldGradient: LinearGradient {
            LinearGradient(
                colors: [lavender, pink, peach],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Ambient canvas: plum → near-black with a soft pink/purple glow
        /// bloom at the top (warm paper + peach/lavender glow in light mode).
        /// A View rather than a gradient so every screen that used the old
        /// navy gradient picks up the glow automatically.
        static var backgroundGradient: AmbientBackground { AmbientBackground() }

        static var cardGradient: LinearGradient {
            LinearGradient(
                colors: isLight
                    ? [Color.white, Color(hex: "FBF7F2")]
                    : [Color(hex: "1E1B24"), Color(hex: "16141B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        // Accent Colors
        static var accentGold: Color { gemGold }
        static var accentPurple: Color { lavender }
        /// Legacy token name — no longer blue. Mint keeps secondary accents
        /// cool without reintroducing blue.
        static var accentBlue: Color { mint }
        static var accentPink: Color { pink }

        // MARK: - Genre neon palette (Chris's lotus screenshots, build 22)
        //
        // Every selected genre gets its own color. Neon by design: these pop
        // on black AND on white, so the palette is identical in both themes.

        /// Pastel-neon palette (build 76 redesign — no blues): pink,
        /// lavender, lime, peach, butter, mint, coral, violet, orchid, seafoam.
        static let genrePalette: [Color] = [
            Color(hex: "FF8FC7"), // bubblegum pink
            Color(hex: "C9A0F0"), // lavender
            Color(hex: "C8E86B"), // lime
            Color(hex: "FFB38A"), // peach
            Color(hex: "F3E59A"), // butter
            Color(hex: "8EE6B8"), // mint
            Color(hex: "FF7A85"), // coral
            Color(hex: "A78BFA"), // violet
            Color(hex: "E879F9"), // orchid
            Color(hex: "7FE0C4"), // seafoam
        ]

        /// Assigns every genre in the set a palette color.
        /// Deterministic: the same genre always hashes to the same base slot
        /// (FNV-1a over the lowercased name — stable across launches), and
        /// hash collisions probe forward to the next free slot. Any selection
        /// of up to `genrePalette.count` genres gets all-different colors.
        /// The probe is BOUNDED by the palette size: once all 10 slots are
        /// taken, colors repeat deterministically instead of spinning forever
        /// (an unbounded probe here froze the app on the 11th selected genre
        /// in build 22). Keys are lowercased genre names.
        static func genreColors(for genres: [String]) -> [String: Color] {
            let sorted = Array(Set(genres.map { $0.lowercased() })).sorted()
            var used = Set<Int>()
            var result: [String: Color] = [:]
            for genre in sorted {
                var idx = stableGenreHash(genre) % genrePalette.count
                var probes = 0
                while used.contains(idx) && probes < genrePalette.count {
                    idx = (idx + 1) % genrePalette.count
                    probes += 1
                }
                // probes == genrePalette.count means every slot is taken;
                // idx has wrapped back to the hashed slot, so the color
                // repeats deterministically. Always terminates.
                used.insert(idx)
                result[genre] = genrePalette[idx]
            }
            return result
        }

        /// Readable text color on top of a saturated genre color —
        /// near-black on light neons (lime, yellow, cyan), white on the rest.
        static func textOnGenreColor(_ color: Color) -> Color {
            let ui = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luminance > 0.55 ? Color(hex: "111827") : .white
        }

        /// FNV-1a 64-bit — stable across launches (Swift's Hasher is not).
        private static func stableGenreHash(_ s: String) -> Int {
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in s.lowercased().utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return Int(hash & 0x7fffffffffffffff)
        }

        // Text Colors
        static var textPrimary: Color {
            isLight ? Color(hex: "16121A") : Color(hex: "FFFFFF")
        }
        static var textSecondary: Color {
            isLight ? Color(hex: "5E5866") : Color(hex: "A19DA8")
        }
        static var textTertiary: Color {
            isLight ? Color(hex: "8C8694") : Color(hex: "75707D")
        }
        static var error: Color { Color(hex: "EF4444") }
        static var buttonText: Color { // Text on lime CTA buttons (both modes)
            textOnPastel
        }
    }
    
    // MARK: - Typography
    
    struct Typography {
        static let display = Font.system(size: 40, weight: .light) // Editorial display
        static let largeTitle = Font.system(size: 34, weight: .bold) // Clean bold
        static let title = Font.system(size: 24, weight: .semibold)
        static let title2 = Font.system(size: 20, weight: .semibold)
        static let title3 = Font.system(size: 18, weight: .medium)
        static let headline = Font.system(size: 16, weight: .medium)
        static let body = Font.system(size: 15, weight: .regular)
        static let body2 = Font.system(size: 14, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
        static let caption2 = Font.system(size: 10, weight: .regular)
    }
    
    // MARK: - Spacing
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    
    struct CornerRadius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 26
        static let card: CGFloat = 24
        static let circle: CGFloat = 999
    }
    
    // MARK: - Shadows
    
    struct Shadows {
        // Computed so the glow follows the appearance mode
        // (static lets would capture the dark-mode color forever).
        static var small: Shadow { Shadow(color: .black.opacity(0.2), radius: 2, y: 1) }
        static var medium: Shadow { Shadow(color: .black.opacity(0.3), radius: 6, y: 2) }
        static var large: Shadow { Shadow(color: .black.opacity(0.4), radius: 12, y: 4) }
        static var glow: Shadow { Shadow(color: Theme.Colors.magentaGlow.opacity(0.25), radius: 18, y: 0) }
    }
    
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        
        init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct GlassmorphismModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .fill(Theme.Colors.cardGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassmorphism() -> some View {
        modifier(GlassmorphismModifier())
    }
    
    func applyShadow(_ shadow: Theme.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Ambient background (build 76)

/// Plum → near-black canvas with a soft magenta/violet bloom at the top,
/// matching Chris's dark music-app references. Light mode: warm paper with
/// a faint peach/lavender bloom.
struct AmbientBackground: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let light = themeManager.isLight
        ZStack {
            LinearGradient(
                colors: light
                    ? [Color(hex: "FBF6F0"), Theme.Colors.paper]
                    : [Theme.Colors.plum, Theme.Colors.plumDeep, Theme.Colors.ink, Theme.Colors.ink],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    Circle()
                        .fill(light ? Theme.Colors.peach.opacity(0.55) : Theme.Colors.magentaGlow.opacity(0.42))
                        .frame(width: w * 0.95, height: w * 0.95)
                        .blur(radius: 90)
                        .offset(x: -w * 0.30, y: -w * 0.45)
                    Circle()
                        .fill(light ? Theme.Colors.lavender.opacity(0.45) : Theme.Colors.violetGlow.opacity(0.40))
                        .frame(width: w * 0.85, height: w * 0.85)
                        .blur(radius: 100)
                        .offset(x: w * 0.35, y: -w * 0.30)
                }
                .frame(width: w, height: geo.size.height, alignment: .top)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shared component styles (build 76)

/// Capsule filter chip: lime + black text when selected, graphite + white
/// text otherwise.
struct ChipStyle: ViewModifier {
    let isSelected: Bool
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isSelected ? Theme.Colors.textOnPastel : Theme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            // Build 78: subtle Liquid Glass tinted with the chip's color.
            .brandGlass(isSelected ? Theme.Colors.lime : Theme.Colors.chipFill, in: Capsule())
    }
}

/// Big rounded pastel card with near-black content.
struct PastelCardModifier: ViewModifier {
    let color: Color
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .foregroundColor(Theme.Colors.textOnPastel)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous)
                    .fill(color)
            )
    }
}

/// Lime capsule primary CTA.
struct LimeCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.Colors.textOnPastel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .brandGlass(Theme.Colors.lime, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Dark card surface (non-pastel) with a hairline edge.
struct SurfaceCardModifier: ViewModifier {
    var radius: CGFloat = Theme.CornerRadius.lg
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Colors.surface.opacity(ThemeManager.shared.isLight ? 1 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.Colors.textPrimary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func chipStyle(selected: Bool) -> some View { modifier(ChipStyle(isSelected: selected)) }
    func pastelCard(_ color: Color, padding: CGFloat = 20) -> some View {
        modifier(PastelCardModifier(color: color, padding: padding))
    }
    func surfaceCard(radius: CGFloat = Theme.CornerRadius.lg) -> some View {
        modifier(SurfaceCardModifier(radius: radius))
    }
}
