import SwiftUI

// MARK: - Rarity Pill (teaser on the player)

/// Small tappable pill showing the artist's rarity tier. Lives on the
/// now-playing card; tap (or swipe up on artwork) reveals the full sheet.
struct RarityPill: View {
    let rarity: ArtistRarity?

    var body: some View {
        HStack(spacing: 6) {
            if let rarity {
                Text(rarity.tier.emoji)
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
        VStack(spacing: 20) {
            // Tier header
            VStack(spacing: 8) {
                Text(rarity.tier.emoji)
                    .font(.system(size: 48))
                Text(rarity.tier.label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.Colors.textPrimary)
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
                    statRow(icon: "👥", label: "Spotify followers", value: followers)
                }
                if let popularity = rarity.popularity {
                    statRow(icon: "📊", label: "Spotify popularity", value: "\(popularity)/100")
                }
                if let listeners = rarity.lastFmListeners {
                    statRow(icon: "🎧", label: "Last.fm listeners", value: formatNumber(listeners))
                }
                if let plays = rarity.lastFmPlaycount {
                    statRow(icon: "🔁", label: "Last.fm plays", value: formatNumber(plays))
                }
                if !rarity.genres.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Genres", systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        FlowLayout(spacing: 8) {
                            ForEach(rarity.genres.prefix(6), id: \.self) { genre in
                                Text(genre)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var rarityGradient: LinearGradient {
        LinearGradient(
            colors: [Color.purple, Color.blue, Color.cyan],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Text(icon)
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

// MARK: - Simple flow layout for genre chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
