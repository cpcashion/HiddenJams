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

/// Slowly rotating diamond with twinkling sparkles for the paywall.
private struct AnimatedGemView: View {
    @State private var rotating = false
    @State private var sparkleOn = false

    private let sparkleOffsets: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (38, -30, 14), (-34, -18, 10), (20, 34, 16), (-24, 30, 8)
    ]

    var body: some View {
        ZStack {
            // Soft glow
            Circle()
                .fill(Theme.Colors.gemGold.opacity(0.15))
                .frame(width: 150, height: 150)
                .blur(radius: 20)

            // Diamond, rotating slowly
            Image(systemName: "diamond.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.gemGold)
                .rotationEffect(.degrees(rotating ? 360 : 0))
                .animation(
                    .linear(duration: 14).repeatForever(autoreverses: false),
                    value: rotating
                )

            // Twinkling sparkles, staggered
            ForEach(0..<sparkleOffsets.count, id: \.self) { i in
                let sp = sparkleOffsets[i]
                Image(systemName: "sparkle")
                    .font(.system(size: sp.size))
                    .foregroundColor(.white)
                    .offset(x: sp.x, y: sp.y)
                    .opacity(sparkleOn ? 1 : 0.1)
                    .scaleEffect(sparkleOn ? 1.25 : 0.7)
                    .animation(
                        .easeInOut(duration: 1.1)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.35),
                        value: sparkleOn
                    )
            }
        }
        .frame(width: 170, height: 170)
        .onAppear {
            rotating = true
            sparkleOn = true
        }
    }
}
