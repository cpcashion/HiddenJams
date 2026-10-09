//
//  PaywallView.swift
//  HiddenJams
//
//  Presented when a free user hits the 20 discoveries/day limit.
//  Hidden Jams Pro: $4.99/month, unlimited discoveries.
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

            // Gem icon
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.gemGold)

            VStack(spacing: 8) {
                Text("You've found 20 gems today!")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Hidden Jams Pro unlocks unlimited discoveries — dig as deep as you want, every day.")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Benefits
            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "infinity", text: "Unlimited discoveries, every day")
                benefitRow(icon: "music.note.list", text: "Every genre & subgenre unlocked")
                benefitRow(icon: "slider.horizontal.3", text: "Full Deep Cuts slider range")
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
                    Text("$4.99 / month")
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
                    Button("Not now") { dismiss() }
                }
                .font(.system(size: 15))
                .foregroundColor(Theme.Colors.textSecondary)

                Text("Cancel anytime in Settings. 20 free discoveries refresh daily.")
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 32)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
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
