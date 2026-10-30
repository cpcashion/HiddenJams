//
//  ListeningStatsStore.swift
//  HiddenJams
//
//  Build 78: lightweight, on-device activity log that powers the Profile
//  stats the Home pills link to. Records only what actually happens in the
//  app — no estimates, no invented numbers:
//    • a "play" each time a discovery-deck track comes up in the player
//    • a "save" each time a track is saved to Hidden Jams, tagged with how
//      (swipe right, watch thumbs up, or auto-save after playing through)
//  History starts with build 78; nothing earlier was tracked.
//

import Foundation
import Combine

final class ListeningStatsStore: ObservableObject {
    static let shared = ListeningStatsStore()

    enum Source: String, Codable {
        case spotify
        case appleMusic

        var displayName: String {
            switch self {
            case .spotify: return "Spotify"
            case .appleMusic: return "Apple Music"
            }
        }
    }

    enum SaveMethod: String, Codable, CaseIterable {
        case swipe
        case watch
        case auto

        var displayName: String {
            switch self {
            case .swipe: return "Swiped right"
            case .watch: return "Watch 👍"
            case .auto: return "Auto-saved"
            }
        }
    }

    struct Event: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        let trackId: String
        let title: String
        let artist: String
        let artworkURL: URL?
        let source: Source
        /// Coarse genre bucket ("Rock", "House", ...) when one maps.
        let genre: String?
        let date: Date
        /// Only set for saves.
        let method: SaveMethod?
    }

    struct SourceCount: Identifiable {
        let source: Source
        let count: Int
        var id: String { source.rawValue }
    }

    struct GenreCount: Identifiable {
        let genre: String
        let count: Int
        var id: String { genre }
    }

    struct DaySaves: Identifiable {
        let day: Date
        let events: [Event]
        var id: Date { day }
    }

    @Published private(set) var plays: [Event] = []   // newest first
    @Published private(set) var saves: [Event] = []   // newest first

    private let playsKey = "hiddenjams_stats_plays_v1"
    private let savesKey = "hiddenjams_stats_saves_v1"
    private let maxEvents = 3000

    private init() {
        plays = Self.load(playsKey)
        saves = Self.load(savesKey)
    }

    // MARK: - Recording

    /// A discovery-deck track came up in the player.
    func recordPlay(_ track: RecommendedTrack) {
        // Ignore immediate repeats of the same track (re-renders, resumes).
        if let last = plays.first, last.trackId == track.id,
           Date().timeIntervalSince(last.date) < 60 * 10 { return }
        plays.insert(Self.event(for: track, method: nil), at: 0)
        if plays.count > maxEvents { plays.removeLast(plays.count - maxEvents) }
        Self.persist(plays, key: playsKey)
    }

    /// A track was saved to Hidden Jams.
    func recordSave(_ track: RecommendedTrack, method: SaveMethod) {
        guard !saves.contains(where: { $0.trackId == track.id }) else { return }
        saves.insert(Self.event(for: track, method: method), at: 0)
        if saves.count > maxEvents { saves.removeLast(saves.count - maxEvents) }
        Self.persist(saves, key: savesKey)
    }

    // MARK: - Derived stats (all from recorded events)

    var uniqueTracksPlayed: Int { Set(plays.map(\.trackId)).count }

    func plays(since date: Date) -> [Event] { plays.filter { $0.date >= date } }
    func saves(since date: Date) -> [Event] { saves.filter { $0.date >= date } }

    var startOfWeek: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? Date().addingTimeInterval(-7 * 24 * 3600)
    }

    /// Unique tracks per source.
    var playsBySource: [SourceCount] {
        var seen: [Source: Set<String>] = [:]
        for e in plays { seen[e.source, default: []].insert(e.trackId) }
        return seen.map { SourceCount(source: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    func saveCount(_ method: SaveMethod) -> Int { saves.filter { $0.method == method }.count }

    /// Unique discovered tracks per genre bucket.
    var discoveredGenreCounts: [GenreCount] {
        var seen: [String: Set<String>] = [:]
        for e in plays { if let g = e.genre { seen[g, default: []].insert(e.trackId) } }
        return seen.map { GenreCount(genre: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.genre < $1.genre : $0.count > $1.count }
    }

    /// Saves grouped by calendar day, newest day first.
    var savesByDay: [DaySaves] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: saves) { cal.startOfDay(for: $0.date) }
        return grouped.map { DaySaves(day: $0.key, events: $0.value) }.sorted { $0.day > $1.day }
    }

    // MARK: - Helpers

    private static func event(for track: RecommendedTrack, method: SaveMethod?) -> Event {
        return Event(
            trackId: track.id,
            title: track.track.name,
            artist: track.track.artistNames,
            artworkURL: track.track.album.albumArtURL,
            source: track.track.isSpotifyOrigin ? .spotify : .appleMusic,
            genre: GenrePlaylistRouter.bucket(for: track, sessionGenres: sessionGenres()),
            date: Date(),
            method: method
        )
    }

    private static func sessionGenres() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: "selectedGenres"),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return decoded
    }

    private static func load(_ key: String) -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Event].self, from: data) else { return [] }
        return decoded
    }

    private static func persist(_ events: [Event], key: String) {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
