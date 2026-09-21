import Foundation
import Combine

class DiscoveryHistoryManager: ObservableObject {
    static let shared = DiscoveryHistoryManager()
    
    private let historyKey = "discovery_history_seen_ids"
    private let artistHistoryKey = "discovery_history_seen_artist_ids"
    private let timestampsKey = "discovery_history_timestamps"
    
    // History expires after 7 days
    private let expirationDays: TimeInterval = 7
    
    @Published var seenTrackIds: Set<String> = []
    @Published var seenArtistIds: Set<String> = []
    
    // Track timestamps for each ID (for expiration)
    private var trackTimestamps: [String: Date] = [:]
    private var artistTimestamps: [String: Date] = [:]
    
    private init() {
        loadHistory()
        cleanupExpiredHistory()
    }
    
    func loadHistory() {
        // Load Tracks
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            seenTrackIds = decoded
        }
        
        // Load Artists
        if let data = UserDefaults.standard.data(forKey: artistHistoryKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            seenArtistIds = decoded
        }
        
        // Load Timestamps
        if let data = UserDefaults.standard.data(forKey: timestampsKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            // Split into track and artist timestamps based on prefix
            for (key, date) in decoded {
                if key.hasPrefix("track:") {
                    let id = String(key.dropFirst(6))
                    trackTimestamps[id] = date
                } else if key.hasPrefix("artist:") {
                    let id = String(key.dropFirst(7))
                    artistTimestamps[id] = date
                }
            }
        }
    }
    
    /// Clean up entries older than expirationDays
    private func cleanupExpiredHistory() {
        let now = Date()
        let expirationInterval = expirationDays * 24 * 60 * 60  // days to seconds
        
        // Remove expired tracks
        var expiredTrackCount = 0
        for (trackId, timestamp) in trackTimestamps {
            if now.timeIntervalSince(timestamp) > expirationInterval {
                seenTrackIds.remove(trackId)
                trackTimestamps.removeValue(forKey: trackId)
                expiredTrackCount += 1
            }
        }
        
        // Remove expired artists (Re-enabled)
        var expiredArtistCount = 0
        for (artistId, timestamp) in artistTimestamps {
            if now.timeIntervalSince(timestamp) > expirationInterval {
                seenArtistIds.remove(artistId)
                artistTimestamps.removeValue(forKey: artistId)
                expiredArtistCount += 1
            }
        }
        
        if expiredTrackCount > 0 || expiredArtistCount > 0 {
            print("🧹 History cleanup: Removed \(expiredTrackCount) expired tracks and \(expiredArtistCount) expired artists")
            saveHistory()
        }
    }
    
    func addToHistory(trackIds: [String], artistIds: [String] = []) {
        let now = Date()
        
        // Add tracks with timestamps
        for id in trackIds {
            seenTrackIds.insert(id)
            trackTimestamps[id] = now
        }
        
        // Add artists with timestamps (Re-enabled)
        for id in artistIds {
            seenArtistIds.insert(id)
            artistTimestamps[id] = now
        }
        
        saveHistory()
    }
    
    func isSeen(trackId: String) -> Bool {
        // Check if track exists and hasn't expired
        guard seenTrackIds.contains(trackId) else { return false }
        
        // If we have a timestamp, check expiration
        if let timestamp = trackTimestamps[trackId] {
            let expirationInterval = expirationDays * 24 * 60 * 60
            if Date().timeIntervalSince(timestamp) > expirationInterval {
                // Expired - remove and return false
                seenTrackIds.remove(trackId)
                trackTimestamps.removeValue(forKey: trackId)
                saveHistory()
                return false
            }
        }
        
        return true
    }
    
    func isArtistSeen(artistId: String) -> Bool {
        // Check if artist exists and hasn't expired
        guard seenArtistIds.contains(artistId) else { return false }
        
        // If we have a timestamp, check expiration
        if let timestamp = artistTimestamps[artistId] {
            let expirationInterval = expirationDays * 24 * 60 * 60
            if Date().timeIntervalSince(timestamp) > expirationInterval {
                // Expired - remove and return false
                seenArtistIds.remove(artistId)
                artistTimestamps.removeValue(forKey: artistId)
                saveHistory()
                return false
            }
        }
        
        return true
    }
    
    func clearHistory() {
        seenTrackIds.removeAll()
        seenArtistIds.removeAll()
        trackTimestamps.removeAll()
        artistTimestamps.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(seenTrackIds) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
        if let encoded = try? JSONEncoder().encode(seenArtistIds) {
            UserDefaults.standard.set(encoded, forKey: artistHistoryKey)
        }
        
        // Save timestamps with prefixes to distinguish track vs artist
        var combinedTimestamps: [String: Date] = [:]
        for (id, date) in trackTimestamps {
            combinedTimestamps["track:\(id)"] = date
        }
        for (id, date) in artistTimestamps {
            combinedTimestamps["artist:\(id)"] = date
        }
        if let encoded = try? JSONEncoder().encode(combinedTimestamps) {
            UserDefaults.standard.set(encoded, forKey: timestampsKey)
        }
    }
    
    var historyCount: Int {
        return seenTrackIds.count
    }
    
    /// Force cleanup of all expired entries (can be called manually)
    func forceCleanup() {
        cleanupExpiredHistory()
    }
}
