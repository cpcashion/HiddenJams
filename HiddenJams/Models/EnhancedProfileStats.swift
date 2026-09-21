//
//  EnhancedProfileStats.swift
//  HiddenJams
//
//  Rich listening statistics computed from real Spotify data
//

import Foundation

/// Enhanced profile statistics with real listening data
struct EnhancedProfileStats {
    // MARK: - Recently Played
    var recentlyPlayed: [PlayHistory] = []
    
    // MARK: - Top Items by Time Range
    var topTracksThisMonth: [SpotifyTrack] = []      // short_term
    var topTracksSixMonths: [SpotifyTrack] = []      // medium_term
    var topTracksAllTime: [SpotifyTrack] = []        // long_term
    
    var topArtistsThisMonth: [SpotifyArtist] = []    // short_term
    var topArtistsAllTime: [SpotifyArtist] = []      // long_term
    
    // MARK: - Audio Features (REAL DATA)
    var audioFeatures: AudioFeatureProfile?          // Computed from top tracks
    var topGenres: [(name: String, count: Int)] = [] // From top artists
    
    // MARK: - Computed Stats
    var uniqueArtistsCount: Int = 0
    var uniqueTracksCount: Int = 0
    var totalListeningMinutes: Int = 0
    
    // MARK: - Discovery Metrics
    var discoveryRate: Double = 0.0          // % of recent artists not in all-time top
    var newArtistsThisMonth: [SpotifyArtist] = []
    
    // MARK: - Listening Patterns
    var mostActiveHour: Int? = nil           // Most common listening hour (0-23)
    var averageTrackLength: Int = 0          // In seconds
    
    // MARK: - Profile Freshness
    var lastFetched: Date = Date()
    var isDataValid: Bool = false
    
    // MARK: - Helpers
    var hasRealAudioFeatures: Bool {
        audioFeatures != nil
    }
    
    // MARK: - Computed Properties
    
    /// Calculate the discovery rate from artists
    mutating func calculateDiscoveryRate() {
        guard !topArtistsThisMonth.isEmpty else {
            discoveryRate = 0
            return
        }
        
        let allTimeIds = Set(topArtistsAllTime.map { $0.id })
        let recentIds = Set(topArtistsThisMonth.map { $0.id })
        let newIds = recentIds.subtracting(allTimeIds)
        
        discoveryRate = Double(newIds.count) / Double(recentIds.count)
        newArtistsThisMonth = topArtistsThisMonth.filter { newIds.contains($0.id) }
    }
    
    /// Get the top track that changed position the most
    var risingTracks: [SpotifyTrack] {
        // Tracks in this month's top 10 that aren't in all-time top 20
        let allTimeIds = Set(topTracksAllTime.prefix(20).map { $0.id })
        return topTracksThisMonth.prefix(10).filter { !allTimeIds.contains($0.id) }
    }
    
    /// Format listening minutes for display
    var formattedListeningTime: String {
        if totalListeningMinutes >= 1440 { // >= 24 hours
            let days = totalListeningMinutes / 1440
            return "\(days)+ days"
        } else if totalListeningMinutes >= 60 {
            let hours = totalListeningMinutes / 60
            return "\(hours)+ hours"
        } else {
            return "\(totalListeningMinutes) mins"
        }
    }
}

// MARK: - Genre Evolution
struct GenreShift: Identifiable {
    let id = UUID()
    let genre: String
    let previousRank: Int?
    let currentRank: Int
    let direction: TrendDirection
}

enum TrendDirection {
    case rising
    case falling
    case stable
    case new
}
