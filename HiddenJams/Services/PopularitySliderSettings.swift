//
//  PopularitySliderSettings.swift
//  HiddenJams
//
//  Manages the discovery slider state and maps it to discovery thresholds
//

import SwiftUI
import Combine

/// Backing state for the obscurity slider.
///
/// The slider position is the single source of truth; every threshold is
/// derived from it through `ObscurityWindow`, so the number shown in the UI and
/// the number the discovery engine filters on can never drift apart.
class PopularitySliderSettings: ObservableObject {

    /// The raw slider value from 0.0 (most obscure) to 1.0 (most popular)
    @Published var popularityLevel: Double {
        didSet {
            UserDefaults.standard.set(popularityLevel, forKey: "popularitySliderLevel")
        }
    }

    /// The filter window this slider position represents.
    var window: ObscurityWindow {
        ObscurityWindow(level: popularityLevel)
    }

    /// Number of crowd characters to display based on popularity level
    var crowdSize: Int {
        let minCrowd = 5
        let maxCrowd = 80
        return minCrowd + Int(Double(maxCrowd - minCrowd) * popularityLevel)
    }

    /// Maximum Spotify popularity score for discovery.
    var popularityThreshold: Int {
        window.popularityCeiling
    }

    /// Maximum artist follower count for discovery.
    ///
    /// Followers are the honest unit here. Spotify's API exposes no play or
    /// stream count for tracks or artists, so "under 500 plays" is not
    /// something the app can truthfully promise — "under 500 followers" is.
    var followerThreshold: Int {
        window.followerCeiling
    }

    /// Short label, e.g. "Deep Cuts".
    var levelDescription: String {
        window.label
    }

    /// One-line explanation of what this setting returns.
    var levelSubtitle: String {
        window.subtitle
    }

    /// Formatted ceiling for display, e.g. "1.2K followers".
    var thresholdDescription: String {
        window.followerDescription
    }

    init() {
        // Default to 0.25 — deep cuts, but not so extreme that a first run
        // comes back empty for narrower genres.
        let stored = UserDefaults.standard.object(forKey: "popularitySliderLevel") as? Double
        self.popularityLevel = stored ?? 0.25
    }
}
