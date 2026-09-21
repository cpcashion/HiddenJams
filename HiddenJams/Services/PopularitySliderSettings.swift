//
//  PopularitySliderSettings.swift
//  HiddenJams
//
//  Manages the popularity slider state and maps it to discovery thresholds
//

import SwiftUI
import Combine

/// Manages the popularity slider state for the concert crowd feature
/// Controls how "mainstream" vs "obscure" the discovered tracks should be
class PopularitySliderSettings: ObservableObject {
    /// The raw slider value from 0.0 (most obscure) to 1.0 (most popular)
    @Published var popularityLevel: Double {
        didSet {
            // Persist to UserDefaults
            UserDefaults.standard.set(popularityLevel, forKey: "popularitySliderLevel")
        }
    }
    
    /// Number of crowd characters to display based on popularity level
    var crowdSize: Int {
        // Maps 0.0 → 5 characters, 1.0 → 80 characters
        let minCrowd = 5
        let maxCrowd = 80
        return minCrowd + Int(Double(maxCrowd - minCrowd) * popularityLevel)
    }
    
    /// The actual Spotify popularity threshold to use in discovery
    /// Lower values = more obscure tracks
    var popularityThreshold: Int {
        // Maps 0.0 → threshold of 15, 1.0 → threshold of 90
        let minThreshold = 15
        let maxThreshold = 90
        return minThreshold + Int(Double(maxThreshold - minThreshold) * popularityLevel)
    }
    
    /// The follower threshold to use in discovery
    /// Scales from 2,000 (slider at 0) to 500,000 (slider at 1)
    /// This is our proxy for "monthly listeners" since Spotify API doesn't expose that data
    var followerThreshold: Int {
        let minFollowers = 2_000     // ~5-20K monthly listeners typically
        let maxFollowers = 500_000   // Mainstream level
        return minFollowers + Int(Double(maxFollowers - minFollowers) * popularityLevel)
    }
    
    /// Human-readable description of current setting
    var levelDescription: String {
        switch popularityLevel {
        case 0..<0.2:
            return "Deep Cuts"
        case 0.2..<0.4:
            return "Hidden Gems"
        case 0.4..<0.6:
            return "Underground"
        case 0.6..<0.8:
            return "Rising Stars"
        default:
            return "Mainstream"
        }
    }
    
    init() {
        // Load persisted value or default to 0.0 (most obscure)
        self.popularityLevel = UserDefaults.standard.double(forKey: "popularitySliderLevel")
    }
}
