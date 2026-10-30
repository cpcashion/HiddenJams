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
    private let savedIdsKey = "hiddenjams_saved_track_ids"

    /// IDs of every track ever saved to a Hidden Jams playlist (Spotify,
    /// Apple Music, or in-app), by swipe right, watch thumbs up, or
    /// auto-save. Used so an auto-save never duplicates a track the user
    /// already saved — Spotify's add-to-playlist doesn't dedupe.
    private(set) var savedTrackIds: Set<String> = []

    private init() {
        load()
        if let ids = UserDefaults.standard.stringArray(forKey: savedIdsKey) {
            savedTrackIds = Set(ids)
        }
        savedTrackIds.formUnion(savedTracks.map(\.id))
    }

    /// True if this track has already been saved anywhere by Hidden Jams.
    func hasSaved(trackId: String) -> Bool {
        savedTrackIds.contains(trackId)
    }

    /// Records that a track was saved (any destination).
    func markSaved(trackId: String) {
        guard savedTrackIds.insert(trackId).inserted else { return }
        UserDefaults.standard.set(Array(savedTrackIds), forKey: savedIdsKey)
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
        // Removing a gem means it may be saved (or auto-saved) again later.
        if savedTrackIds.remove(track.id) != nil {
            UserDefaults.standard.set(Array(savedTrackIds), forKey: savedIdsKey)
        }
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
