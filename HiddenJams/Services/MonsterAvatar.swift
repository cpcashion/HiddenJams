import Foundation

/// Cute monster profile pictures for Apple Music users.
///
/// MusicKit gives this app no user profile photo, so every Apple Music
/// connection is assigned one permanent random monster as their pfp.
/// Spotify users keep their real Spotify photo; monsters are only the
/// fallback when there is no Spotify image.
enum MonsterAvatar {
    static let all: [String] = [
        "monster-pink", "monster-mint", "monster-blue", "monster-lilac",
        "monster-coral", "monster-orange", "monster-yellow", "monster-lime",
        "monster-emerald", "monster-teal", "monster-cyan", "monster-indigo",
        "monster-violet", "monster-magenta", "monster-rose", "monster-peach",
        "monster-tan", "monster-cocoa", "monster-slate", "monster-cream",
    ]

    private static let storageKey = "monsterAvatarName"

    /// The user's assigned monster. Picks a random one and persists it
    /// on first access, so the monster stays stable across launches.
    static var assignedName: String {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           all.contains(saved) {
            return saved
        }
        let pick = all.randomElement() ?? all[0]
        UserDefaults.standard.set(pick, forKey: storageKey)
        return pick
    }
}
