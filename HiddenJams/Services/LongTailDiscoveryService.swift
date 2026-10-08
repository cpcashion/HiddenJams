//
//  LongTailDiscoveryService.swift
//  HiddenJams
//
//  Long-tail candidate generation — reaches the obscure depths of the
//  catalog that Spotify's search and recommendations endpoints never
//  surface (both are popularity-biased / deterministic for fixed seeds,
//  which is why two users could get identical queues).
//
//  FRONTIER CHAINING: the walk is stateful across sessions. Every artist
//  name the walk has ever visited is persisted; each session starts from
//  where the last one ended (the frontier) and only traverses UNEXPLORED
//  territory. The Last.fm similar-artist graph is effectively infinite,
//  so this guarantees fresh candidates every session, forever — the
//  structural answer to "same songs over and over" AND to "couldn't find
//  new music."
//
//  Strategy per session:
//    1. Seeds — frontier artists (forward motion) + fresh taste seeds
//       (taste anchoring, re-sampled every session).
//    2. Graph walk — Last.fm `artist.getSimilar`, skipping every visited
//       name. Similar artists of obscure artists live deep in the tail.
//    3. Depth charge — if level 1 is thin, walk similar-of-similar.
//    4. Spotify resolve — searchArtist + top-tracks, skipping served
//       artists and pre-filtering by popularity.
//

import Foundation

final class LongTailDiscoveryService {
    private let lastFm = LastFmService()
    private let spotifyAPI = SpotifyAPIService()

    // Persistent walk state — the walk never revisits.
    private let exploredKey = "longtail_explored_artists"
    private let frontierKey = "longtail_frontier"

    /// Generates long-tail Spotify track candidates.
    /// - Returns: Tracks from obscure, never-before-visited artists related
    ///   to the user's taste and the session genres.
    func discover(
        profile: ListeningProfile,
        sessionGenres: [String],
        token: String,
        popularityThreshold: Double,
        maxArtists: Int = 40,
        maxTracks: Int = 160,
        updateProgress: @escaping (String) async -> Void
    ) async -> [SpotifyTrack] {
        var explored = loadExplored()
        let genreKey = sessionGenres.sorted().joined(separator: "|")

        // 1. Seeds: frontier (forward motion) + fresh taste seeds (anchoring).
        var seeds: [String] = []
        let frontier = loadFrontier()[genreKey] ?? []
        let frontierSeeds = Array(frontier.shuffled().prefix(6))
        seeds.append(contentsOf: frontierSeeds)
        let tasteSeeds = sampleTasteSeeds(profile: profile, sessionGenres: sessionGenres, count: 8)
        for seed in tasteSeeds where !seeds.contains(where: { $0.caseInsensitiveCompare(seed) == .orderedSame }) {
            seeds.append(seed)
        }
        // Genre entry points when there's no frontier yet.
        if seeds.count < 6, !sessionGenres.isEmpty {
            await updateProgress("Mapping the \(sessionGenres.prefix(2).joined(separator: ", ")) underground...")
            for genre in sessionGenres.prefix(3) {
                do {
                    let tops = try await lastFm.getTagTopTracks(tag: genre.lowercased(), limit: 6)
                    for (_, artist) in tops where !seeds.contains(where: { $0.caseInsensitiveCompare(artist) == .orderedSame }) {
                        seeds.append(artist)
                    }
                } catch {
                    print("⚠️ Long-tail: tag tops failed for '\(genre)': \(error)")
                }
                if seeds.count >= 12 { break }
            }
        }
        guard !seeds.isEmpty else {
            print("⚠️ Long-tail: no seeds — skipping")
            return []
        }
        print("🌊 Long-tail: \(seeds.count) seeds (\(frontierSeeds.count) frontier, \(tasteSeeds.count) taste)")

        // 2. Graph walk — only unexplored territory.
        await updateProgress("Walking the long tail...")
        var discovered: [String] = []
        for seed in seeds {
            explored.insert(seed.lowercased())
            do {
                let similar = try await lastFm.getSimilarArtists(artistName: seed, limit: 20)
                for artist in similar {
                    let key = artist.name.lowercased()
                    if !explored.contains(key) {
                        explored.insert(key)
                        discovered.append(artist.name)
                    }
                }
            } catch {
                print("⚠️ Long-tail: similar-artists failed for '\(seed)': \(error)")
            }
            if discovered.count >= maxArtists { break }
        }
        print("🌊 Long-tail: discovered \(discovered.count) NEW artists")

        // 3. Depth charge: if level 1 was thin, walk similar-of-similar.
        if discovered.count < 15 {
            await updateProgress("Going deeper underground...")
            let depthSeeds = Array(discovered.prefix(6))
            for seed in depthSeeds {
                do {
                    let similar = try await lastFm.getSimilarArtists(artistName: seed, limit: 15)
                    for artist in similar {
                        let key = artist.name.lowercased()
                        if !explored.contains(key) {
                            explored.insert(key)
                            discovered.append(artist.name)
                        }
                    }
                } catch {
                    print("⚠️ Long-tail: level-2 walk failed for '\(seed)': \(error)")
                }
                if discovered.count >= maxArtists { break }
            }
            print("🌊 Long-tail: after depth charge, \(discovered.count) new artists")
        }

        // Persist walk state BEFORE resolving (even if resolution fails,
        // we never walk here again).
        saveExplored(explored)
        var frontierMap = loadFrontier()
        frontierMap[genreKey] = Array(discovered.shuffled().prefix(12))
        saveFrontier(frontierMap)

        // 4. Resolve to Spotify tracks, preferring obscure artists.
        // Per-session shuffle so the same graph yields different tracks.
        // Served artists are skipped BEFORE the top-tracks call.
        var candidates: [SpotifyTrack] = []
        var seenTrackIds = Set<String>()
        let history = DiscoveryHistoryManager.shared
        for artistName in discovered.shuffled() {
            guard candidates.count < maxTracks else { break }
            do {
                let artists = try await spotifyAPI.searchArtist(name: artistName, token: token)
                guard let artist = artists.first else { continue }
                if history.isArtistSeen(artistId: artist.id) { continue }
                let artistPop = Double(artist.popularity ?? 100)
                guard artistPop < max(popularityThreshold + 25, 55) else { continue }

                let tracks = try await spotifyAPI.getArtistTopTracks(artistId: artist.id, token: token)
                for track in tracks {
                    guard Double(track.popularity) < popularityThreshold,
                          seenTrackIds.insert(track.id).inserted else { continue }
                    candidates.append(track)
                    if candidates.count >= maxTracks { break }
                }
            } catch {
                continue
            }
        }
        print("🌊 Long-tail: resolved \(candidates.count) candidate tracks from \(discovered.count) new artists")
        return candidates
    }

    // MARK: - Persistent walk state

    private func loadExplored() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: exploredKey) ?? [])
    }

    private func saveExplored(_ explored: Set<String>) {
        // Cap the stored set to keep UserDefaults lean (50k names max —
        // effectively infinite for walk purposes).
        let capped = Array(explored.suffix(50_000))
        UserDefaults.standard.set(capped, forKey: exploredKey)
    }

    private func loadFrontier() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: frontierKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveFrontier(_ frontier: [String: [String]]) {
        if let encoded = try? JSONEncoder().encode(frontier) {
            UserDefaults.standard.set(encoded, forKey: frontierKey)
        }
    }

    // MARK: - Taste seeds

    /// Per-session sample of the user's artists. Mild deep-cut bias:
    /// weight = 1 - 0.6 * influence, so their less-frequent artists seed
    /// more often (deeper tail) while favorites still appear.
    /// When session genres are selected, seeds are restricted to artists
    /// whose profile genres intersect the selection.
    private func sampleTasteSeeds(
        profile: ListeningProfile,
        sessionGenres: [String],
        count: Int
    ) -> [String] {
        var pool = profile.topArtists
        if !sessionGenres.isEmpty {
            let lowered = sessionGenres.map { $0.lowercased() }
            let filtered = pool.filter { artist in
                artist.genres.contains { genre in
                    let g = genre.lowercased()
                    return lowered.contains { s in g.contains(s) || s.contains(g) }
                }
            }
            // Only narrow when it leaves a usable pool.
            if filtered.count >= 3 { pool = filtered }
        }
        guard !pool.isEmpty else { return [] }
        let sampled = DiscoveryRandomization.weightedSample(
            pool,
            count: min(count, pool.count),
            weight: { max(0.15, 1.0 - 0.6 * $0.influence) }
        )
        return sampled.map { $0.name }
    }
}
