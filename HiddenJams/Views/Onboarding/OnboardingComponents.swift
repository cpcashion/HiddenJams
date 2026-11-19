//
//  OnboardingComponents.swift
//  HiddenJams
//
//  Shared pieces for onboarding v5 and the taste-profile reveal:
//  the display headline with a lime-highlighted word, the pinned Next,
//  the small mono kicker, and generated pastel "cover" tiles (no
//  third-party artwork on intro screens; Spotify's guidelines forbid
//  animating/overlaying their art).
//

import SwiftUI

// MARK: - Headline

/// Big SF Pro headline with one phrase on a lime highlight
/// (e.g. "Most music never gets **heard.**").
struct HighlightedHeadline: View {
    let text: String
    let highlight: String?
    var size: CGFloat = 44

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        Text(attributed)
            .font(.system(size: min(size * scale, size * 1.25), weight: .heavy))
            .tracking(-1.2)
            .foregroundStyle(Theme.Colors.textPrimary)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var attributed: AttributedString {
        var s = AttributedString(text)
        if let highlight, let range = s.range(of: highlight) {
            s[range].swiftUI.backgroundColor = Theme.Colors.lime
            s[range].swiftUI.foregroundColor = Theme.Colors.textOnPastel
        }
        return s
    }
}

/// Small uppercase kicker / footnote ("SOURCE: LUMINATE …", "SAMPLE SONGS").
struct OnboardingKicker: View {
    let text: String
    var color: Color = Theme.Colors.textTertiary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// Body copy with optional **bold** runs (Markdown).
struct OnboardingBody: View {
    let markdown: String

    var body: some View {
        Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
            .font(.system(size: 16))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next

/// The one Next button used on every screen (same slot, same style).
struct OnboardingNextButton: View {
    var title: String = "Next"
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(LimeCTAButtonStyle())
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .padding(.horizontal, 22)
    }
}

// MARK: - Sample cover tile

/// Generated pastel "album" tile. Deterministic per seed.
struct SampleCoverTile: View {
    let seed: Int
    var size: CGFloat = 64
    var desaturated: Bool = false
    var lit: Bool = false

    private static let glyphs = ["music.note", "waveform", "headphones", "opticaldisc", "music.mic", "guitars", "pianokeys", "metronome"]

    var body: some View {
        let base = Theme.Colors.pastel(seed)
        let accent = Theme.Colors.pastel(seed + 2)
        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
            .fill(LinearGradient(colors: [base, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Image(systemName: Self.glyphs[abs(seed) % Self.glyphs.count])
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textOnPastel.opacity(0.55))
            )
            .frame(width: size, height: size)
            .saturation(desaturated ? 0 : 1)
            .opacity(desaturated ? 0.45 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .stroke(Theme.Colors.lime, lineWidth: lit ? 3 : 0)
            )
            .shadow(color: lit ? Theme.Colors.lime.opacity(0.5) : .black.opacity(0.3), radius: lit ? 16 : 6, y: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Service connect button

/// "Continue with Spotify / Apple Music": lime capsule (same as Next) with
/// the service glyph on a white tile.
/// TODO(brand): swap the SF Symbols for the official, unmodified Spotify
/// icon and Apple Music badge once bundled (never `apple.logo`).
struct ServiceConnectButton: View {
    let source: MusicSource
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: source.systemIconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.textOnPastel)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
                if busy {
                    ProgressView().tint(Theme.Colors.textOnPastel)
                } else {
                    Text("Continue with \(source.displayName)")
                }
            }
        }
        .buttonStyle(LimeCTAButtonStyle())
        .disabled(busy)
        .padding(.horizontal, 22)
        .accessibilityLabel("Continue with \(source.displayName)")
    }
}

// MARK: - Genre pill row (non-interactive, e.g. "Starting with")

struct GenrePillsRow: View {
    let genres: [String]

    var body: some View {
        let colors = Theme.Colors.genreColors(for: genres)
        FlowLayout(spacing: 8) {
            ForEach(genres, id: \.self) { g in
                GenrePillContent(genre: g, isSelected: true, pillColor: colors[g.lowercased()] ?? Theme.Colors.lime)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Components") {
    ZStack {
        Theme.Colors.backgroundGradient.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
            HighlightedHeadline(text: "Most music never gets heard.", highlight: "heard.")
            OnboardingBody(markdown: "**88%** of songs on streaming got 1,000 plays or fewer last year.")
            OnboardingKicker(text: "Source: Luminate 2025 Year-End Music Report")
            HStack { SampleCoverTile(seed: 0); SampleCoverTile(seed: 1, desaturated: true); SampleCoverTile(seed: 2, lit: true) }
            GenrePillsRow(genres: ["soul", "jazz", "funk"])
            ServiceConnectButton(source: .spotify) {}
            OnboardingNextButton {}
        }
        .padding(22)
    }
    .preferredColorScheme(.dark)
}

// MARK: - Tier colors (onboarding + taste profile)

extension ArtistRarity.Tier {
    /// Ladder order, least → most rare.
    static let ladder: [ArtistRarity.Tier] = [.known, .emerging, .rare, .ultraRare, .mythic]

    var ladderColor: Color {
        switch self {
        case .known: return Theme.Colors.graphiteHigh
        case .emerging: return Theme.Colors.mint
        case .rare: return Theme.Colors.lavender
        case .ultraRare: return Theme.Colors.pink
        case .mythic: return Theme.Colors.lime
        }
    }

    var ladderTextColor: Color {
        self == .known ? Theme.Colors.textPrimary : Theme.Colors.textOnPastel
    }
}
