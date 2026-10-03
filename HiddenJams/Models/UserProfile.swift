//
//  UserProfile.swift
//  HiddenJams
//
//  Unified user profile — the app-level identity that links every music
//  provider the user connects. Spotify gives us a full identity (id, name,
//  email, photo). Apple Music via MusicKit gives us almost nothing, so
//  Apple Music users link Sign in with Apple for a verified identity.
//
//  Profiles persist locally today; the model is Codable and backend-ready
//  (Supabase/Firebase) for sync when we add the server side.
//

import Foundation

/// Which external identities are linked to this profile.
struct LinkedProviders: Codable, Equatable {
    var spotify: Bool = false
    var appleMusic: Bool = false
    var appleID: Bool = false
}

/// Subscription tier. Cached from StoreKit 2; the store is source of truth.
enum SubscriptionTier: String, Codable {
    case free
    case premium
}

struct UserProfile: Codable, Equatable {
    /// Stable app-level identity. Created on first launch, never changes.
    /// This is what the backend will key on.
    var id: UUID

    /// Best display name we have: Spotify display_name, Apple ID full name,
    /// or a user-entered name. Falls back to "Music Lover".
    var displayName: String?

    /// From Spotify (user-read-email scope) or Sign in with Apple.
    /// Nil for Apple Music-only users who haven't linked Apple ID.
    var email: String?

    /// Spotify profile image URL. Nil for non-Spotify users.
    var avatarURL: URL?

    /// Monster avatar assignment for users without a photo (persisted —
    /// the same monster forever). See ProfileView monsterAvatarName.
    var monsterAvatarName: String?

    /// Provider linkage state.
    var linkedProviders: LinkedProviders

    /// Spotify user id, when linked. Used to detect account switches.
    var spotifyUserId: String?

    /// Sign in with Apple user identifier, when linked.
    var appleIDUserIdentifier: String?

    /// Subscription state. Updated by SubscriptionManager from StoreKit.
    var subscriptionTier: SubscriptionTier

    var createdAt: Date
    var lastActiveAt: Date

    // MARK: - Derived

    var effectiveDisplayName: String {
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "Music Lover"
    }

    var hasVerifiedIdentity: Bool {
        linkedProviders.spotify || linkedProviders.appleID
    }

    /// True when the user can be reached / identified for a real account
    /// (needed for subscriptions, sync, support).
    var isAccountComplete: Bool {
        hasVerifiedIdentity && email != nil
    }

    // MARK: - Factory

    static func fresh() -> UserProfile {
        UserProfile(
            id: UUID(),
            displayName: nil,
            email: nil,
            avatarURL: nil,
            monsterAvatarName: nil,
            linkedProviders: LinkedProviders(),
            spotifyUserId: nil,
            appleIDUserIdentifier: nil,
            subscriptionTier: .free,
            createdAt: Date(),
            lastActiveAt: Date()
        )
    }
}
