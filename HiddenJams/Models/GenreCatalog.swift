//
//  GenreCatalog.swift
//  HiddenJams
//
//  The one shared list of genres the app offers, plus the `selectedGenres`
//  persistence contract. Used by the genre picker (GenreSelectionView) and
//  onboarding screen 4 so the two lists can never drift.
//

import Foundation

enum GenreCatalog {
    /// The app's 31 picker genres, Title Case, in picker order.
    /// (Moved verbatim from `GenreSelectionView.commonGenres`.)
    static let common: [String] = [
        "Pop", "Rock", "Hip Hop", "Rap", "Country",
        "R&B", "Electronic", "Dance", "Indie", "Alternative",
        "Classical", "Jazz", "Blues", "Metal", "Punk",
        "Folk", "Reggae", "Soul", "Funk", "Latin",
        "Reggaeton", "K-Pop", "Anime", "Gospel", "Christian", "Worship",
        "Drum and Bass", "Jungle", "House", "Techno", "Ambient"
    ]

    /// Onboarding order (deep-cut friendly first). Same strings as `common`,
    /// lowercased exactly as persisted.
    static let onboardingOrder: [String] = [
        "soul", "jazz", "indie", "funk", "ambient", "folk", "electronic", "hip hop", "r&b", "alternative",
        "blues", "latin", "reggae", "rock", "classical", "house", "techno", "punk", "metal", "country",
        "pop", "dance", "rap", "drum and bass", "jungle", "k-pop", "reggaeton", "anime", "gospel", "christian", "worship"
    ]

    // MARK: - `selectedGenres` persistence

    /// UserDefaults / @AppStorage key read by GenreSelectionView,
    /// DashboardView, MainTabView and ListeningStatsStore.
    static let selectedGenresKey = "selectedGenres"

    /// The saved picks, or nil when the key is unset / empty.
    /// Unset or empty means "all genres" everywhere in the app.
    static func loadSelected(from defaults: UserDefaults = .standard) -> Set<String>? {
        guard let data = defaults.data(forKey: selectedGenresKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data),
              !decoded.isEmpty else { return nil }
        return decoded
    }

    /// Saves onboarding picks with the same encoding as the picker
    /// (JSONEncoder over `Set<String>` of lowercased names).
    /// Nothing picked → the key is removed, never written empty, so the rest
    /// of the app keeps its "missing = select all" default.
    static func saveOnboardingPicks(_ picks: Set<String>, to defaults: UserDefaults = .standard) {
        let normalized = Set(picks.map { $0.lowercased() })
        guard !normalized.isEmpty else {
            defaults.removeObject(forKey: selectedGenresKey)
            return
        }
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: selectedGenresKey)
        }
    }
}
