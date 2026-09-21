//
//  UserDataManager.swift
//  HiddenJams
//
//  Centralized service for persisting user data including Spotify profile and library tracks
//

import Foundation

class UserDataManager {
    static let shared = UserDataManager()
    
    // MARK: - Keys
    private let userProfileKey = "spotify_user_profile"
    private let lastAnalysisDateKey = "last_analysis_date"
    private let libraryFileName = "user_library.json"
    
    // MARK: - User Profile Persistence
    
    func saveUserProfile(_ user: SpotifyUser) {
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: userProfileKey)
            print("✅ Saved user profile for: \(user.displayName ?? "Unknown")")
        }
    }
    
    func loadUserProfile() -> SpotifyUser? {
        guard let data = UserDefaults.standard.data(forKey: userProfileKey),
              let user = try? JSONDecoder().decode(SpotifyUser.self, from: data) else {
            return nil
        }
        print("✅ Loaded user profile: \(user.displayName ?? "Unknown")")
        return user
    }
    
    // MARK: - Library Tracks Persistence (File-based for large data)
    
    func saveUserLibrary(_ tracks: [SpotifyTrack]) {
        guard let url = libraryFileURL else {
            print("❌ Could not get library file URL")
            return
        }
        
        do {
            // Create directory if needed
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            // Encode and save
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: url)
            
            // Save timestamp
            UserDefaults.standard.set(Date(), forKey: lastAnalysisDateKey)
            
            print("✅ Saved \(tracks.count) tracks to library cache")
        } catch {
            print("❌ Failed to save library: \(error)")
        }
    }
    
    func loadUserLibrary() -> [SpotifyTrack]? {
        guard let url = libraryFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let tracks = try JSONDecoder().decode([SpotifyTrack].self, from: data)
            print("✅ Loaded \(tracks.count) tracks from library cache")
            return tracks
        } catch {
            print("❌ Failed to load library: \(error)")
            return nil
        }
    }
    
    // MARK: - Analysis Timestamp
    
    var lastAnalysisDate: Date? {
        UserDefaults.standard.object(forKey: lastAnalysisDateKey) as? Date
    }
    
    var daysSinceLastAnalysis: Int? {
        guard let lastDate = lastAnalysisDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
    }
    
    // MARK: - Validation
    
    var hasValidCachedData: Bool {
        // Check if we have both profile and library data
        guard loadUserProfile() != nil else { return false }
        guard let url = libraryFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return false }
        return true
    }
    
    // MARK: - Clear All Data
    
    func clearAllData() {
        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: userProfileKey)
        UserDefaults.standard.removeObject(forKey: lastAnalysisDateKey)
        UserDefaults.standard.removeObject(forKey: "listening_profile")
        
        // Clear library file
        if let url = libraryFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        print("🗑️ Cleared all user data")
    }
    
    // MARK: - Helpers
    
    private var libraryFileURL: URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsURL
            .appendingPathComponent("HiddenJams")
            .appendingPathComponent(libraryFileName)
    }
}
