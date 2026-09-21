//
//  ObscurityWindow.swift
//  HiddenJams
//
//  Translates the discovery slider into concrete, Spotify-queryable filters.
//

import Foundation

/// The filter window the slider represents.
///
/// ## Why followers and popularity, not play counts
///
/// The Spotify Web API does not expose stream or play counts for tracks or
/// artists — there is no public endpoint for it and there never has been. The
/// closest signals it *does* give us, on every artist object, are:
///
///   - `followers.total` — how many people follow the artist
///   - `popularity`      — a 0–100 score Spotify derives from recent play volume
///
/// Together these are a good proxy for "how discovered is this artist". An
/// artist with 300 followers and popularity 8 is genuinely obscure; one with
/// 400,000 followers and popularity 70 is not. So the slider filters on those
/// two numbers, and the UI describes them in follower terms rather than
/// promising a play count we cannot actually source.
struct ObscurityWindow {

    /// Raw slider position, 0.0 (most obscure) to 1.0 (mainstream).
    let level: Double

    /// Maximum follower count an artist may have to qualify.
    let followerCeiling: Int

    /// Maximum Spotify popularity score (0–100) an artist may have to qualify.
    let popularityCeiling: Int

    /// Whether to add Spotify's `tag:hipster` modifier, which restricts results
    /// to the lowest-popularity decile of a genre. Only meaningful at the
    /// obscure end — at higher levels it fights the window instead of helping.
    let useHipsterTag: Bool

    /// Short label for the slider UI.
    let label: String

    /// Plain-language description of what the user will get.
    let subtitle: String

    // MARK: - Construction

    init(level rawLevel: Double) {
        let level = min(max(rawLevel, 0.0), 1.0)
        self.level = level

        // Exponential curve: 100 followers at 0.0 → 1,000,000 at 1.0.
        //
        // Linear scaling would waste most of the slider's travel on the range
        // nobody cares about. Everything interesting for this app lives under
        // ~50k followers, so the curve gives fine control down there and
        // coarse control up top, which is how people actually use it.
        let minFollowers = 100.0
        let maxFollowers = 1_000_000.0
        let growth = maxFollowers / minFollowers
        self.followerCeiling = Int(minFollowers * pow(growth, level))

        // Popularity climbs more gently — a brand new artist can sit at 0 even
        // with a few thousand followers, so this is the looser of the two bounds.
        self.popularityCeiling = 5 + Int(95.0 * pow(level, 1.3))

        self.useHipsterTag = level < 0.35

        switch level {
        case ..<0.15:
            self.label = "Undiscovered"
            self.subtitle = "Almost nobody has heard these"
        case ..<0.35:
            self.label = "Deep Cuts"
            self.subtitle = "A few hundred listeners"
        case ..<0.55:
            self.label = "Hidden Gems"
            self.subtitle = "Small but real followings"
        case ..<0.75:
            self.label = "Underground"
            self.subtitle = "Building an audience"
        case ..<0.9:
            self.label = "Rising"
            self.subtitle = "On their way up"
        default:
            self.label = "Mainstream"
            self.subtitle = "Established artists"
        }
    }

    // MARK: - Filtering

    /// Whether an artist falls inside this window.
    func admits(artist: SpotifyArtist) -> Bool {
        let followers = artist.followers?.total ?? 0
        let popularity = artist.popularity ?? 0
        return followers <= followerCeiling && popularity <= popularityCeiling
    }

    /// A widened copy, used when a search comes back too thin to fill a screen.
    /// Widening the ceilings beats returning an empty list.
    func relaxed(by factor: Double = 4.0) -> ObscurityWindow {
        ObscurityWindow(
            level: level,
            followerCeiling: Int(Double(followerCeiling) * factor),
            popularityCeiling: min(popularityCeiling + 20, 100),
            useHipsterTag: false,
            label: label,
            subtitle: subtitle
        )
    }

    /// Human-readable ceiling, e.g. "1.2K followers".
    var followerDescription: String {
        if followerCeiling >= 1_000_000 {
            return String(format: "%.1fM followers", Double(followerCeiling) / 1_000_000)
        }
        if followerCeiling >= 1_000 {
            return String(format: "%.1fK followers", Double(followerCeiling) / 1_000)
        }
        return "\(followerCeiling) followers"
    }

    // Memberwise init kept private so `relaxed(by:)` can bypass the curve while
    // callers still have to go through `init(level:)`.
    private init(
        level: Double,
        followerCeiling: Int,
        popularityCeiling: Int,
        useHipsterTag: Bool,
        label: String,
        subtitle: String
    ) {
        self.level = level
        self.followerCeiling = followerCeiling
        self.popularityCeiling = popularityCeiling
        self.useHipsterTag = useHipsterTag
        self.label = label
        self.subtitle = subtitle
    }
}
