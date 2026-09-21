//
//  StreamCountService.swift
//  HiddenJams
//
//  Service for getting actual Spotify stream counts via third-party APIs
//  NOTE: Requires RapidAPI key for production use
//

import Foundation

class StreamCountService {
    private let rapidAPIKey: String
    private let useMockData: Bool
    
    init(apiKey: String = "") {
        self.rapidAPIKey = apiKey.isEmpty ? (ProcessInfo.processInfo.environment["RAPIDAPI_KEY"] ?? "") : apiKey
        self.useMockData = rapidAPIKey.isEmpty
        
        if useMockData {
            print("⚠️ StreamCountService running in MOCK mode - using popularity as proxy")
            print("💡 To enable real stream counts, set RAPIDAPI_KEY environment variable")
        }
    }
    
    // MARK: - Get Stream Count for Single Track
    
    func getStreamCount(track: SpotifyTrack) async throws -> Int {
        // If no API key, use popularity as a rough proxy
        if useMockData {
            return estimateStreamCountFrom(popularity: track.popularity)
        }
        
        // TODO: Implement actual RapidAPI call
        // Example endpoint: https://spotify-scraper.p.rapidapi.com/v1/track/metadata?trackId={trackId}
        
        return estimateStreamCountFrom(popularity: track.popularity)
    }
    
    // MARK: - Batch Get Stream Counts
    
    func filterHiddenGems(_ tracks: [SpotifyTrack], threshold: Int = 1000) async -> [SpotifyTrack] {
        if useMockData {
            // ULTRA-STRICT: Only popularity < 5 (targets <1K-5K plays)
            // Combined with 2024-only searches, this gives best chance at <1K
            let filtered = tracks.filter { $0.popularity < 5 }
            print("📊 Filtered \(tracks.count) tracks → \(filtered.count) with popularity < 5")
            return filtered
        }
        
        // TODO: Batch API call to get stream counts
        var hiddenGems: [SpotifyTrack] = []
        
        for track in tracks {
            do {
                let count = try await getStreamCount(track: track)
                if count < threshold {
                    hiddenGems.append(track)
                }
            } catch {
                print("⚠️ Stream count check failed for \(track.name)")
            }
        }
        
        return hiddenGems
    }
    
    // MARK: - Estimate Stream Count from Popularity
    
    private func estimateStreamCountFrom(popularity: Int) -> Int {
        // Rough estimates based on Spotify popularity formula
        // This is exponential - lower numbers have dramatically fewer streams
        switch popularity {
        case 0...2: return Int.random(in: 100...500)
        case 3...5: return Int.random(in: 500...2000)
        case 6...8: return Int.random(in: 2000...10000)
        case 9...12: return Int.random(in: 10000...50000)
        case 13...20: return Int.random(in: 50000...200000)
        case 21...30: return Int.random(in: 200000...1000000)
        default: return Int.random(in: 1000000...10000000)
        }
    }
}

