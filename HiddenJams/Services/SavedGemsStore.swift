//
//  SavedGemsStore.swift
//  HiddenJams
//
//  In-app collection of liked gems. Used when the user hasn't connected
//  Spotify (so there's no Spotify playlist to save into) — e.g. Apple Music
//  only listeners. Persists across launches.
//

import Foundation
import Combine

/// In-app collection of liked gems. Plain class (like SpotifyAuthManager);
/// all callers run on the main thread.
class SavedGemsStore: ObservableObject {
    static let shared = SavedGemsStore()

    @Published private(set) var savedTracks: [SpotifyTrack] = []

    private let storageKey = "hiddenjams_saved_gems"

    private init() {
        load()
    }

    func save(_ track: RecommendedTrack) {
        save(track.track)
    }

    func save(_ track: SpotifyTrack) {
        guard !contains(track) else { return }
        savedTracks.insert(track, at: 0)
        persist()
        print("💾 Saved '\(track.name)' to My Gems (\(savedTracks.count) total)")
    }

    func remove(_ track: SpotifyTrack) {
        savedTracks.removeAll { $0.id == track.id }
        persist()
    }

    func contains(_ track: SpotifyTrack) -> Bool {
        savedTracks.contains { $0.id == track.id }
    }

    // MARK: - Persistence

    private func persist() {
        if let encoded = try? JSONEncoder().encode(savedTracks) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SpotifyTrack].self, from: data) {
            savedTracks = decoded
        }
    }
}
