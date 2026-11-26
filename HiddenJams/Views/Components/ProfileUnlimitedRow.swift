//
//  ProfileUnlimitedRow.swift
//  HiddenJams
//
//  Build 94 (App Review 2.1(b), 1.6.1): an always-visible way to reach the
//  "Hidden Jams Unlimited" subscription. Before this, the paywall only
//  appeared at the free limit, so a reviewer couldn't find the in-app
//  purchase. The row sits near the top of Profile for every user: no
//  gating on music service, onboarding, quota, storefront, device, or
//  TestFlight vs App Store.
//

import SwiftUI
import StoreKit

/// What the Profile row says. The name matches the App Store Connect
/// product display name ("Hidden Jams Unlimited").
struct UnlimitedRowContent: Equatable {
    static let productName = SubscriptionProduct.monthly.displayName // "Hidden Jams Unlimited"
    static let fallbackPrice = "$1.99"

    let title: String
    let subtitle: String
    let isActive: Bool

    /// - Parameters:
    ///   - isPremium: StoreKit entitlement for unlimited.monthly.
    ///   - displayPrice: `Product.displayPrice` once loaded, else nil.
    init(isPremium: Bool, displayPrice: String?) {
        isActive = isPremium
        if isPremium {
            title = "\(Self.productName) · Active"
            subtitle = "Manage subscription"
        } else {
            title = Self.productName
            subtitle = "\(displayPrice ?? Self.fallbackPrice)/month · unlimited songs"
        }
    }
}

/// Presentation state for the row. A tap opens the paywall for a free user,
/// or Apple's manage-subscriptions sheet for an active subscriber.
@MainActor
final class UnlimitedRowModel: ObservableObject {
    @Published var showsPaywall = false
    @Published var showsManageSubscriptions = false

    func tap(isPremium: Bool) {
        if isPremium {
            showsManageSubscriptions = true
        } else {
            showsPaywall = true
        }
    }
}

/// The card itself, in the Profile grouped-card style with a lime accent.
struct ProfileUnlimitedRow: View {
    let content: UnlimitedRowContent
    let action: () -> Void

    static let accessibilityID = "profile.unlimitedRow"

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: content.isActive ? "checkmark.seal.fill" : "infinity")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.Colors.textOnPastel)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Colors.lime))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(content.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.lime)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                    .fill(Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                    .strokeBorder(Theme.Colors.lime.opacity(0.7), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.title), \(content.subtitle)")
        .accessibilityHint(content.isActive ? "Opens Apple's subscription settings" : "Shows the subscription")
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
