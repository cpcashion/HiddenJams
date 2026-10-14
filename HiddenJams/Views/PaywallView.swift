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
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            // Animated gem: slow rotation + twinkling sparkles
            AnimatedGemView()

            VStack(spacing: 8) {
                Text("You've found 50 gems today!")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Free discovery stops here — but the music doesn't have to. Go Pro and keep digging, all day, every day.")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Benefits — why unlimited is so much better
            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "infinity", text: "Never hit the wall — free stops at 50 songs a day, Pro never stops")
                benefitRow(icon: "arrow.triangle.2.circlepath", text: "Fresh decks on every tap — 50+ new hidden jams, as many times as you want")
                benefitRow(icon: "music.note.list", text: "The catalog is millions deep — Pro lets you explore all of it")
            }
            .padding(.horizontal, 40)

            Spacer()

            // Price + CTA
            VStack(spacing: 12) {
                if let product = monthlyProduct {
                    Text("\(product.displayPrice) / month")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                } else {
                    Text("$1.99 / month")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                }

                Button {
                    Task { await buyPro() }
                } label: {
                    if isPurchasing {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text("Go Pro")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .background(Theme.Colors.gemGold)
                .cornerRadius(16)
                .disabled(isPurchasing)
                .padding(.horizontal, 24)

                if let error = subscriptionManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                HStack(spacing: 24) {
                    Button("Restore") {
                        Task { await subscriptionManager.restore() }
                    }
                    Button("Not now") {
                        // Snooze the paywall for this session so the user can
                        // keep testing/using the app. Resets on next launch.
                        DiscoveryQuotaManager.shared.paywallSnoozed = true
                        dismiss()
                    }
                }
                .font(.system(size: 15))
                .foregroundColor(Theme.Colors.textSecondary)

                Text("Cancel anytime in Settings. 50 free discoveries refresh daily.")
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 32)
        }
        .background(Theme.Colors.spotifyBlack.ignoresSafeArea())
        .task {
            await subscriptionManager.loadProducts()
        }
        .onChange(of: subscriptionManager.isPremium) { isPro in
            if isPro { dismiss() }
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Theme.Colors.gemGold)
                .frame(width: 28)
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(Theme.Colors.textPrimary)
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

/// Diamond with a slow 3D spin around its vertical axis (like a coin turning)
/// and very subtle twinkling sparkles. (Build 52: the flat 2D rotation looked
/// cheap — this is the coin-spin Chris asked for.)
private struct AnimatedGemView: View {
    @State private var spin = false
    @State private var sparkleOn = false

    // Few, small, gentle sparkles
    private let sparkles: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (30, -26, 9), (-28, -14, 7), (16, 28, 8)
    ]

    var body: some View {
        ZStack {
            // Faint glow
            Circle()
                .fill(Theme.Colors.gemGold.opacity(0.10))
                .frame(width: 130, height: 130)
                .blur(radius: 24)

            // Diamond, spinning around the vertical axis
            Image(systemName: "diamond.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.gemGold, Theme.Colors.gemGold.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .rotation3DEffect(
                    .degrees(spin ? 360 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )
                .animation(
                    .linear(duration: 9).repeatForever(autoreverses: false),
                    value: spin
                )

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
        .frame(width: 160, height: 160)
        .onAppear {
            spin = true
            sparkleOn = true
        }
    }
}
