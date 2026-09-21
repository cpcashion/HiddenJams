//
//  ProfileDataService.swift
//  HiddenJams
//
//  Service for fetching and computing rich profile data from Spotify
//

import Foundation
import Combine

@MainActor
class ProfileDataService: ObservableObject {
    // MARK: - Published Properties
    @Published var stats: EnhancedProfileStats = EnhancedProfileStats()
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = ""
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    private let apiService = SpotifyAPIService()
    
    // MARK: - Fetch All Profile Data
    
    /// Fetches all enhanced profile data in parallel
    func fetchAllProfileData(token: String) async {
        isLoading = true
        errorMessage = nil
        loadingMessage = "Fetching your listening history..."
        
        var newStats = EnhancedProfileStats()
        
        do {
            // Fetch all data in parallel for speed
            async let recentlyPlayedTask = fetchRecentlyPlayed(token: token)
            async let topTracksThisMonthTask = fetchTopTracks(token: token, timeRange: .shortTerm)
            async let topTracksSixMonthsTask = fetchTopTracks(token: token, timeRange: .mediumTerm)
            async let topTracksAllTimeTask = fetchTopTracks(token: token, timeRange: .longTerm)
            async let topArtistsThisMonthTask = fetchTopArtists(token: token, timeRange: .shortTerm)
            async let topArtistsAllTimeTask = fetchTopArtists(token: token, timeRange: .longTerm)
            
            // Await all results
            loadingMessage = "Analyzing your music taste..."
            
            newStats.recentlyPlayed = await recentlyPlayedTask
            newStats.topTracksThisMonth = await topTracksThisMonthTask
            newStats.topTracksSixMonths = await topTracksSixMonthsTask
            newStats.topTracksAllTime = await topTracksAllTimeTask
            newStats.topArtistsThisMonth = await topArtistsThisMonthTask
            newStats.topArtistsAllTime = await topArtistsAllTimeTask
            
            // Fetch audio features for top tracks
            loadingMessage = "Analyzing audio characteristics..."
            let audioFeatures = await fetchAudioFeatures(for: newStats.topTracksAllTime, token: token)
            newStats.audioFeatures = audioFeatures
            
            // Calculate genres from top artists
            newStats.topGenres = calculateTopGenres(from: newStats.topArtistsAllTime)
            
            // Calculate computed stats
            loadingMessage = "Crunching the numbers..."
            calculateStats(&newStats)
            
            newStats.isDataValid = true
            newStats.lastFetched = Date()
            
            self.stats = newStats
            print("✅ Profile data loaded successfully")
            print("   Recently played: \(newStats.recentlyPlayed.count)")
            print("   Top tracks (month): \(newStats.topTracksThisMonth.count)")
            print("   Top artists (all time): \(newStats.topArtistsAllTime.count)")
            print("   Audio features: \(newStats.hasRealAudioFeatures ? "Real data" : "Not available")")
            if let features = newStats.audioFeatures {
                print("   Energy: \(Int(features.energy * 100))%, Dance: \(Int(features.danceability * 100))%")
            }
            
        } catch {
            errorMessage = "Failed to load profile data: \(error.localizedDescription)"
            print("❌ Profile data fetch failed: \(error)")
        }
        
        isLoading = false
        loadingMessage = ""
    }
    
    // MARK: - Individual Fetch Methods
    
    private func fetchRecentlyPlayed(token: String) async -> [PlayHistory] {
        do {
            return try await apiService.getRecentlyPlayed(token: token, limit: 50)
        } catch {
            print("⚠️ Failed to fetch recently played: \(error)")
            return []
        }
    }
    
    private func fetchTopTracks(token: String, timeRange: TimeRange) async -> [SpotifyTrack] {
        do {
            return try await apiService.getTopTracks(token: token, limit: 50, timeRange: timeRange)
        } catch {
            print("⚠️ Failed to fetch top tracks (\(timeRange.rawValue)): \(error)")
            return []
        }
    }
    
    private func fetchTopArtists(token: String, timeRange: TimeRange) async -> [SpotifyArtist] {
        do {
            return try await apiService.getTopArtists(token: token, limit: 50, timeRange: timeRange)
        } catch {
            print("⚠️ Failed to fetch top artists (\(timeRange.rawValue)): \(error)")
            return []
        }
    }
    
    /// Returns nil — Spotify withdrew `/audio-features` in November 2024.
    /// See `AIProfileAnalyzer.fetchAndCalculateAudioFeatures` for the details.
    private func fetchAudioFeatures(for tracks: [SpotifyTrack], token: String) async -> AudioFeatureProfile? {
        return nil
    }
    
    private func calculateTopGenres(from artists: [SpotifyArtist]) -> [(name: String, count: Int)] {
        var genreCounts: [String: Int] = [:]
        
        for artist in artists {
            for genre in artist.genres ?? [] {
                genreCounts[genre, default: 0] += 1
            }
        }
        
        return genreCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (name: $0.key, count: $0.value) }
    }
    
    // MARK: - Stats Calculation
    
    private func calculateStats(_ stats: inout EnhancedProfileStats) {
        // Unique counts
        let allTracks = stats.topTracksThisMonth + stats.topTracksSixMonths + stats.topTracksAllTime
        let allArtists = stats.topArtistsThisMonth + stats.topArtistsAllTime
        
        stats.uniqueTracksCount = Set(allTracks.map { $0.id }).count
        stats.uniqueArtistsCount = Set(allArtists.map { $0.id }).count
        
        // Total listening time from recently played (estimate based on track duration)
        let recentDuration = stats.recentlyPlayed.reduce(0) { $0 + $1.track.durationMs }
        stats.totalListeningMinutes = recentDuration / 60000
        
        // Average track length
        if !allTracks.isEmpty {
            let totalDuration = allTracks.reduce(0) { $0 + $1.durationMs }
            stats.averageTrackLength = totalDuration / allTracks.count / 1000 // Convert to seconds
        }
        
        // Most active hour
        stats.mostActiveHour = calculateMostActiveHour(from: stats.recentlyPlayed)
        
        // Discovery rate
        stats.calculateDiscoveryRate()
    }
    
    private func calculateMostActiveHour(from history: [PlayHistory]) -> Int? {
        var hourCounts: [Int: Int] = [:]
        
        for play in history {
            if let date = play.playedAtDate {
                let hour = Calendar.current.component(.hour, from: date)
                hourCounts[hour, default: 0] += 1
            }
        }
        
        return hourCounts.max(by: { $0.value < $1.value })?.key
    }
}
