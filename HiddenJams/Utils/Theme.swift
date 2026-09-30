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
        // Dark = signature gold "hidden gems" look.
        // Light = monochrome with blue accent pops.
        private static var isLight: Bool { ThemeManager.shared.isLight }

        // Brand Colors
        static var gemGold: Color { // Primary accent: gold in dark, blue pop in light
            isLight ? Color(hex: "2563EB") : Color(hex: "F59E0B")
        }
        static var gemGoldLight: Color {
            isLight ? Color(hex: "60A5FA") : Color(hex: "FBBF24")
        }
        static var gemGoldDark: Color {
            isLight ? Color(hex: "1E40AF") : Color(hex: "D97706")
        }
        static var spotifyGreen: Color { gemGold } // Alias for compatibility
        static var spotifyBlack: Color { // Primary background
            isLight ? Color(hex: "FFFFFF") : Color(hex: "000000")
        }
        static var spotifyDarkGray: Color { // Secondary background
            isLight ? Color(hex: "F4F4F5") : Color(hex: "121212")
        }

        // Brand Gradients
        static var primaryGradient: LinearGradient {
            LinearGradient(
                colors: isLight
                    ? [Color(hex: "2563EB"), Color(hex: "60A5FA")]
                    : [Color(hex: "F59E0B"), Color(hex: "FBBF24")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static var goldGradient: LinearGradient {
            LinearGradient(
                colors: isLight
                    ? [Color(hex: "1E40AF"), Color(hex: "2563EB"), Color(hex: "60A5FA")]
                    : [Color(hex: "D97706"), Color(hex: "F59E0B"), Color(hex: "FBBF24")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static var backgroundGradient: LinearGradient {
            LinearGradient(
                colors: isLight
                    ? [Color(hex: "FFFFFF"), Color(hex: "F4F4F5")]
                    : [Color(hex: "000000"), Color(hex: "121212")],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        static var cardGradient: LinearGradient {
            LinearGradient(
                colors: isLight
                    ? [Color(hex: "FFFFFF"), Color(hex: "F1F1F1")]
                    : [Color(hex: "181818"), Color(hex: "121212")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        // Accent Colors
        static var accentGold: Color {
            isLight ? Color(hex: "2563EB") : Color(hex: "F59E0B")
        }
        static var accentPurple: Color {
            // Decorative glow only — keep monochrome in light mode
            isLight ? Color(hex: "9CA3AF") : Color(hex: "8B5CF6")
        }
        static var accentBlue: Color { Color(hex: "3B82F6") } // Blue in both modes
        static var accentPink: Color {
            isLight ? Color(hex: "2563EB") : Color(hex: "EC4899")
        }

        // MARK: - Genre neon palette (Chris's lotus screenshots, build 22)
        //
        // Every selected genre gets its own color. Neon by design: these pop
        // on black AND on white, so the palette is identical in both themes.

        /// The neon palette, sampled from Chris's neon-lotus screenshots:
        /// hot pink, electric blue, cyan, lime, golden yellow, orange, red,
        /// violet, emerald, fuchsia.
        static let genrePalette: [Color] = [
            Color(hex: "FF4D8D"), // hot pink
            Color(hex: "3B82F6"), // electric blue
            Color(hex: "22D3EE"), // cyan
            Color(hex: "A3E635"), // lime
            Color(hex: "FACC15"), // golden yellow
            Color(hex: "FB923C"), // orange
            Color(hex: "EF4444"), // red
            Color(hex: "A855F7"), // violet
            Color(hex: "34D399"), // emerald
            Color(hex: "D946EF"), // fuchsia
        ]

        /// Assigns every genre in the set a distinct palette color.
        /// Deterministic: the same genre always hashes to the same base slot
        /// (FNV-1a over the lowercased name — stable across launches), and
        /// hash collisions probe forward to the next free slot. Any selection
        /// of up to `genrePalette.count` genres gets all-different colors;
        /// keys are lowercased genre names.
        static func genreColors(for genres: [String]) -> [String: Color] {
            let sorted = genres.map { $0.lowercased() }.sorted()
            var used = Set<Int>()
            var result: [String: Color] = [:]
            for genre in sorted {
                var idx = stableGenreHash(genre) % genrePalette.count
                while used.contains(idx) { idx = (idx + 1) % genrePalette.count }
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
            isLight ? Color(hex: "111827") : Color(hex: "FFFFFF")
        }
        static var textSecondary: Color {
            isLight ? Color(hex: "6B7280") : Color(hex: "9CA3AF")
        }
        static var textTertiary: Color {
            isLight ? Color(hex: "9CA3AF") : Color(hex: "6B7280")
        }
        static var error: Color { Color(hex: "EF4444") }
        static var buttonText: Color { // Text on accent buttons
            isLight ? Color(hex: "FFFFFF") : Color(hex: "121212")
        }
    }
    
    // MARK: - Typography
    
    struct Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold) // Clean bold
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
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let circle: CGFloat = 999
    }
    
    // MARK: - Shadows
    
    struct Shadows {
        // Computed so the gold/blue glow follows the appearance mode
        // (static lets would capture the dark-mode color forever).
        static var small: Shadow { Shadow(color: .black.opacity(0.2), radius: 2, y: 1) }
        static var medium: Shadow { Shadow(color: .black.opacity(0.3), radius: 6, y: 2) }
        static var large: Shadow { Shadow(color: .black.opacity(0.4), radius: 12, y: 4) }
        static var glow: Shadow { Shadow(color: Theme.Colors.gemGold.opacity(0.15), radius: 15, y: 0) }
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
