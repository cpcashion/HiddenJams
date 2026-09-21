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
        // Brand Colors - Gold "Hidden Gems" theme
        static let gemGold = Color(hex: "F59E0B")         // Primary accent
        static let gemGoldLight = Color(hex: "FBBF24")    // Light gold
        static let gemGoldDark = Color(hex: "D97706")     // Dark gold
        static let spotifyGreen = gemGold                  // Alias for compatibility
        static let spotifyBlack = Color(hex: "000000")    // Pure Black
        static let spotifyDarkGray = Color(hex: "121212") // Off-black
        
        // Premium Gradients - Gold
        static let primaryGradient = LinearGradient(
            colors: [Color(hex: "F59E0B"), Color(hex: "FBBF24")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let goldGradient = LinearGradient(
            colors: [Color(hex: "D97706"), Color(hex: "F59E0B"), Color(hex: "FBBF24")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let backgroundGradient = LinearGradient(
            colors: [Color(hex: "000000"), Color(hex: "121212")],
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let cardGradient = LinearGradient(
            colors: [
                Color(hex: "181818"),
                Color(hex: "121212")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Accent Colors
        static let accentGold = Color(hex: "F59E0B")
        static let accentPurple = Color(hex: "8B5CF6")
        static let accentBlue = Color(hex: "3B82F6")
        static let accentPink = Color(hex: "EC4899")
        
        // Text Colors - High Contrast
        static let textPrimary = Color(hex: "FFFFFF")
        static let textSecondary = Color(hex: "9CA3AF")
        static let textTertiary = Color(hex: "6B7280")
        static let error = Color(hex: "EF4444")
        static let buttonText = Color(hex: "121212") // Dark grey, almost black
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
        static let small = Shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        static let medium = Shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        static let large = Shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        static let glow = Shadow(color: Theme.Colors.gemGold.opacity(0.15), radius: 15, y: 0)
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
