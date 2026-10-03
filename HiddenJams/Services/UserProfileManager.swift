//
//  UserProfileManager.swift
//  HiddenJams
//
//  Owns the app-level user profile. Creates it on first launch, links
//  provider identities as the user connects them, and persists locally.
//  Backend sync (Supabase/Firebase) plugs in here when the server lands —
//  the local store is the cache, the profile id is the sync key.
//

import Foundation
import Combine

final class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()

    @Published private(set) var profile: UserProfile

    private let storageKey = "hiddenjams.userprofile.v1"
    private let defaults = UserDefaults.standard

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            var p = saved
            p.lastActiveAt = Date()
            self.profile = p
        } else {
            self.profile = UserProfile.fresh()
        }
        // Adopt the existing monster avatar assignment (if any) into the
        // profile so it syncs with the backend later.
        if profile.monsterAvatarName == nil,
           UserDefaults.standard.string(forKey: "monsterAvatarName") != nil {
            profile.monsterAvatarName = MonsterAvatar.assignedName
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: storageKey)
        }
        // TODO(backend): push to Supabase/Firebase here (debounced).
    }

    private func mutate(_ change: (inout UserProfile) -> Void) {
        var p = profile
        change(&p)
        p.lastActiveAt = Date()
        profile = p
        save()
    }

    // MARK: - Linking

    /// Called after Spotify OAuth completes with the fetched SpotifyUser.
    func linkSpotify(user: SpotifyUser) {
        mutate { p in
            // Detect account switch: different Spotify id than before.
            if let existing = p.spotifyUserId, existing != user.id {
                print("👤 Spotify account switched: \(existing) -> \(user.id)")
            }
            p.linkedProviders.spotify = true
            p.spotifyUserId = user.id
            if let name = user.displayName, !name.isEmpty {
                p.displayName = name
            }
            if let email = user.email, !email.isEmpty {
                p.email = email
            }
            if let url = user.images?.first?.url {
                p.avatarURL = url
            }
        }
    }

    func unlinkSpotify() {
        mutate { p in
            p.linkedProviders.spotify = false
            p.spotifyUserId = nil
            // Keep displayName/email — they may have come from Apple ID.
        }
    }

    /// Called after Sign in with Apple succeeds.
    func linkAppleID(userIdentifier: String, fullName: PersonNameComponents?, email: String?) {
        mutate { p in
            p.linkedProviders.appleID = true
            p.appleIDUserIdentifier = userIdentifier
            // Apple only gives us the name/email on FIRST sign-in — never
            // overwrite a good Spotify-derived value with nil.
            if p.displayName == nil,
               let given = fullName?.givenName {
                let family = fullName?.familyName ?? ""
                let combined = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
                if !combined.isEmpty { p.displayName = combined }
            }
            if p.email == nil, let email, !email.isEmpty {
                p.email = email
            }
        }
    }

    /// Called when MusicKit authorization succeeds.
    func linkAppleMusic() {
        mutate { p in p.linkedProviders.appleMusic = true }
    }

    func unlinkAppleMusic() {
        mutate { p in p.linkedProviders.appleMusic = false }
    }

    // MARK: - Profile edits

    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { $0.displayName = trimmed }
    }

    func setMonsterAvatar(name: String) {
        mutate { $0.monsterAvatarName = name }
    }

    // MARK: - Subscription

    func setSubscriptionTier(_ tier: SubscriptionTier) {
        mutate { $0.subscriptionTier = tier }
    }

    var isPremium: Bool { profile.subscriptionTier == .premium }

    // MARK: - Backend sync (stub)

    /// Payload the backend will accept. Keyed by profile.id.
    var syncPayload: [String: Any] {
        [
            "id": profile.id.uuidString,
            "display_name": profile.effectiveDisplayName,
            "email": profile.email as Any,
            "avatar_url": profile.avatarURL?.absoluteString as Any,
            "providers": [
                "spotify": profile.linkedProviders.spotify,
                "apple_music": profile.linkedProviders.appleMusic,
                "apple_id": profile.linkedProviders.appleID,
            ],
            "spotify_user_id": profile.spotifyUserId as Any,
            "subscription_tier": profile.subscriptionTier.rawValue,
            "created_at": ISO8601DateFormatter().string(from: profile.createdAt),
            "last_active_at": ISO8601DateFormatter().string(from: profile.lastActiveAt),
        ]
    }
}
