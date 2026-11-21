import SwiftUI

// MARK: - Rarity Pill (teaser on the player)

/// Small tappable pill showing the artist's rarity tier. Lives on the
/// now-playing card; tap (or swipe up on artwork) reveals the full sheet.
struct RarityPill: View {
    let rarity: ArtistRarity?

    var body: some View {
        HStack(spacing: 6) {
            if let rarity {
                Text(rarity.tier.label)
                    .font(.caption2)
                    .fontWeight(.bold)
                if let followers = rarity.formattedFollowers {
                    Text("· \(followers)")
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            } else {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .foregroundColor(Theme.Colors.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(20)
    }
}

// MARK: - Rarity Sheet (swipe-up stats)

/// Full rarity breakdown. Presented via swipe-up on artwork or pill tap.
struct RaritySheet: View {
    let rarity: ArtistRarity
    let trackName: String

    var body: some View {
        // Root cause of the recurring "handle hidden by the title" bug: the
        // content was a plain VStack sized to the sheet. At the .medium detent
        // (and while dragging) the VStack is taller than the sheet, and SwiftUI
        // centres an overflowing stack, pushing its top (the title) up past the
        // 16pt padding and under the system drag indicator. HJSheetScaffold
        // reserves a fixed handle zone and puts the content in a top-aligned
        // ScrollView, so content can never be centred upward at any height.
        HJSheetScaffold {
        VStack(spacing: 20) {
            // Tier header
            VStack(spacing: 8) {
                Text(rarity.tier.label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .hjSheetTitle()
                Text(rarity.tier.tagline)
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            // Rarity score meter
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(rarity.score)")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("/ 100")
                        .font(.title3)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Text("RARITY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .tracking(4)

                // Meter bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(rarityGradient)
                            .frame(width: geo.size.width * CGFloat(rarity.score) / 100, height: 12)
                    }
                }
                .frame(height: 12)

                Text(String(format: "Rarer than %.1f%% of artists on Spotify", rarity.rarerThanPercent))
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            Divider().background(Color.white.opacity(0.1))

            // Stat rows
            VStack(spacing: 14) {
                if let followers = rarity.formattedFollowers {
                    statRow(label: "Spotify followers", value: followers)
                }
                if let popularity = rarity.popularity {
                    statRow(label: "Spotify popularity", value: "\(popularity)/100")
                }
                if let listeners = rarity.lastFmListeners {
                    statRow(label: "Last.fm listeners", value: formatNumber(listeners))
                }
                if let plays = rarity.lastFmPlaycount {
                    statRow(label: "Last.fm plays", value: formatNumber(plays))
                }
                if !rarity.genres.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Genres", systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        Text(rarity.genres.prefix(6).joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
            }

        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        }
        .presentationDetents(RaritySheet.detents)
        .presentationDragIndicator(.visible)
    }

    static let detents: Set<PresentationDetent> = [.medium, .large]

    private var rarityGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.Colors.lavender, Theme.Colors.pink, Theme.Colors.peach],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}




// MARK: - Sheet scaffold (fixed handle zone)

/// Content for a detented sheet with the system drag indicator. The top
/// `handleZone` points are reserved for the indicator (UIKit draws it 5pt
/// tall, ~5pt from the top); content starts below it and lives in a
/// top-aligned ScrollView, so at any detent or mid-drag height the content
/// can only be clipped at the bottom (and scrolled), never pushed up under
/// the handle. Locked in by SheetHandleRegressionTests.
struct HJSheetScaffold<Content: View>: View {
    /// Indicator area: 5pt inset + 5pt grabber + 14pt breathing room.
    static var handleZone: CGFloat { 24 }
    static var coordinateSpaceName: String { "hjSheetScaffold" }

    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: Self.handleZone)
                .accessibilityHidden(true)
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(Self.coordinateSpaceName))
    }
}

/// Frame of a sheet's title in the scaffold's coordinate space (used by the
/// regression test; harmless in Release).
struct HJSheetTitleFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Marks the sheet title so its frame can be checked against the handle zone.
    func hjSheetTitle() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: HJSheetTitleFrameKey.self,
                                   value: g.frame(in: .named("hjSheetScaffold")))
        })
    }
}
