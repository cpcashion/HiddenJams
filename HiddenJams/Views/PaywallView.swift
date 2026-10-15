//
//  PaywallView.swift
//  HiddenJams
//
//  Presented when a free user hits the 50 discoveries/day limit.
//  Hidden Jams Pro: $1.99/month, unlimited discoveries.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false

    private var monthlyProduct: Product? {
        subscriptionManager.products.first(where: { $0.id == SubscriptionProduct.monthly.rawValue })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Rock hand — Chris's own emoji PNG, static, subtle sparkles
                AnimatedRockHandView()
                    .padding(.top, 24)

                Text("RARE SONGS. REAL DISCOVERY.")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(3)
                    .foregroundColor(Theme.Colors.textSecondary)

                // Premium card
                VStack(spacing: 16) {
                    // PREMIUM pill
                    Text("PREMIUM")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Theme.Colors.gemGold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(
                            Capsule()
                                .stroke(Theme.Colors.gemGold.opacity(0.5), lineWidth: 1)
                        )
                        .background(Theme.Colors.gemGold.opacity(0.12))
                        .cornerRadius(20)

                    VStack(spacing: 8) {
                        Text("Unlock Premium")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(Theme.Colors.textPrimary)

                        Text("Go beyond the mainstream and discover music the world hasn't heard yet.")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    if let product = monthlyProduct {
                        Text("\(product.displayPrice) / month")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.Colors.textPrimary)
                    } else {
                        Text("$1.99 / month")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    // Benefits
                    VStack(alignment: .leading, spacing: 20) {
                        benefitRow(icon: "infinity", title: "Unlimited songs",
                                   text: "Get unlimited access to fresh, obscure tracks from Spotify and Apple Music.")
                        benefitRow(icon: "sparkles", title: "Discover rare songs",
                                   text: "Find hidden gems before anyone else.")
                        benefitRow(icon: "music.note", title: "Spotify + Apple Music",
                                   text: "Explore curated tracks from the most undiscovered artists.")
                    }
                    .padding(.top, 4)

                    Button {
                        Task { await buyPro() }
                    } label: {
                        if isPurchasing {
                            ProgressView()
                                .tint(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        } else {
                            HStack(spacing: 8) {
                                Text("Start Premium")
                                    .font(.system(size: 18, weight: .bold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                        }
                    }
                    .background(
                        LinearGradient(
                            colors: [Theme.Colors.gemGoldLight, Theme.Colors.gemGold],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .cornerRadius(16)
                    .disabled(isPurchasing)

                    if let error = subscriptionManager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .cornerRadius(24)
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button("Maybe later") {
                        // Snooze the paywall for this session so the user can
                        // keep testing/using the app. Resets on next launch.
                        DiscoveryQuotaManager.shared.paywallSnoozed = true
                        dismiss()
                    }
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.textSecondary)

                    Button("Restore purchases") {
                        Task { await subscriptionManager.restore() }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.textSecondary.opacity(0.7))

                    Text("Cancel anytime in Settings. 50 free discoveries refresh daily.")
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.textSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)
            }
        }
        .background(Theme.Colors.spotifyBlack.ignoresSafeArea())
        .task {
            await subscriptionManager.loadProducts()
        }
        .onChange(of: subscriptionManager.isPremium) { isPro in
            if isPro { dismiss() }
        }
    }

    private func benefitRow(icon: String, title: String, text: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(Theme.Colors.gemGold)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func buyPro() async {
        isPurchasing = true
        defer { isPurchasing = false }
        guard let product = monthlyProduct else {
            await subscriptionManager.loadProducts()
            return
        }
        do {
            try await subscriptionManager.purchase(product)
        } catch {
            // Error surfaced via subscriptionManager.lastError
        }
    }
}

// MARK: - Animated Gem

/// Rock-hand emoji (Chris's own PNG), static, with very subtle twinkling
/// sparkles. Build 56: Chris asked for the plain emoji with no rotation.
private struct AnimatedRockHandView: View {
    @State private var sparkleOn = false

    // Few, small, gentle sparkles
    private let sparkles: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (46, -32, 8), (-44, -20, 7), (22, 42, 8)
    ]

    var body: some View {
        ZStack {
            // Faint glow
            Circle()
                .fill(Theme.Colors.gemGold.opacity(0.10))
                .frame(width: 78, height: 78)
                .blur(radius: 24)

            // Rock-hand emoji — Chris's own PNG (the checkerboard baked into
            // the JPEG he sent was stripped to transparency; the hand is his
            // pixels, byte-for-byte). Static, no rotation, per Chris.
            Image("RockHand")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)

            // Very subtle sparkles
            ForEach(0..<sparkles.count, id: \.self) { i in
                let sp = sparkles[i]
                Image(systemName: "sparkle")
                    .font(.system(size: sp.size))
                    .foregroundColor(.white.opacity(0.85))
                    .offset(x: sp.x, y: sp.y)
                    .opacity(sparkleOn ? 0.9 : 0.15)
                    .scaleEffect(sparkleOn ? 1.1 : 0.85)
                    .animation(
                        .easeInOut(duration: 1.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.5),
                        value: sparkleOn
                    )
            }
        }
        .frame(width: 110, height: 110)
        .onAppear {
            sparkleOn = true
        }
    }
}
