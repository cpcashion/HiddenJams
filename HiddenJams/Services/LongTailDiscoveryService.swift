//
//  LongTailDiscoveryService.swift
//  HiddenJams
//
//  Long-tail candidate generation — reaches the obscure depths of the
//  catalog that Spotify's search and recommendations endpoints never
//  surface (both are popularity-biased / deterministic for fixed seeds,
//  which is why two users could get identical queues).
//
//  Strategy:
//    1. Taste seeds — per-session weighted sample of the user's own
//       artists, biased toward their deeper cuts, genre-filtered to the
//       session's selection when one exists.
//    2. Genre entry points — Last.fm tag-top artists for the session
//       genres (popular head, used only as walk entry points).
//    3. Graph walk — Last.fm `artist.getSimilar` on every seed. Similar
//       artists skew obscure; similar artists of obscure artists live
//       deep in the long tail.
//    4. Spotify resolve — searchArtist + top-tracks for each discovered
//       artist, pre-filtered by popularity. The main pipeline's
//       filters/scoring/lottery then keep only the genuine hidden gems.
//

import Foundation

final class LongTailDiscoveryService {
    private let lastFm = LastFmService()
    private let spotifyAPI = SpotifyAPIService()

    /// Generates long-tail Spotify track candidates.
    /// - Returns: Tracks from obscure artists related to the user's taste
    ///   and the session genres. Unfiltered beyond light popularity
    ///   pre-checks — the caller applies the full filter pipeline.
    func discover(
        profile: ListeningProfile,
        sessionGenres: [String],
        token: String,
        popularityThreshold: Double,
        maxArtists: Int = 36,
        maxTracks: Int = 140,
        updateProgress: @escaping (String) async -> Void
    ) async -> [SpotifyTrack] {
        // 1. Taste seeds: the user's own artists, per-session sample with
        // a mild deep-cut bias (obscure seeds walk deeper into the tail).
        let tasteSeeds = sampleTasteSeeds(profile: profile, sessionGenres: sessionGenres, count: 8)
        print("🌊 Long-tail: taste seeds: \(tasteSeeds)")

        // 2. Genre entry points via Last.fm tags.
        var entryArtists = tasteSeeds
        if !sessionGenres.isEmpty {
            await updateProgress("Mapping the \(sessionGenres.prefix(2).joined(separator: ", ")) underground...")
            for genre in sessionGenres.prefix(3) {
                do {
                    let tops = try await lastFm.getTagTopTracks(tag: genre.lowercased(), limit: 6)
                    for (_, artist) in tops where !entryArtists.contains(where: { $0.caseInsensitiveCompare(artist) == .orderedSame }) {
                        entryArtists.append(artist)
                    }
                } catch {
                    print("⚠️ Long-tail: tag tops failed for '\(genre)': \(error)")
                }
                if entryArtists.count >= 14 { break }
            }
        }
        guard !entryArtists.isEmpty else {
            print("⚠️ Long-tail: no entry artists — skipping")
            return []
        }

        // 3. Graph walk: similar artists for every entry point.
        await updateProgress("Walking the long tail...")
        var discovered: [String] = []
        var seen = Set<String>()
        for entry in entryArtists {
            for name in [entry] + discovered { seen.insert(name.lowercased()) }
            do {
                let similar = try await lastFm.getSimilarArtists(artistName: entry, limit: 20)
                for artist in similar {
                    let key = artist.name.lowercased()
                    if seen.insert(key).inserted {
                        discovered.append(artist.name)
                    }
                }
            } catch {
                print("⚠️ Long-tail: similar-artists failed for '\(entry)': \(error)")
            }
            if discovered.count >= maxArtists { break }
        }
        print("🌊 Long-tail: discovered \(discovered.count) artists from \(entryArtists.count) entry points")

        // 3b. Depth charge: if level 1 was thin, walk one level deeper from
        // the first few discoveries — similar-of-similar lives deepest in
        // the tail, where the freshest gems are.
        if discovered.count < 15 {
            await updateProgress("Going deeper underground...")
            let depthSeeds = Array(discovered.prefix(6))
            for seed in depthSeeds {
                do {
                    let similar = try await lastFm.getSimilarArtists(artistName: seed, limit: 15)
                    for artist in similar {
                        let key = artist.name.lowercased()
                        if seen.insert(key).inserted {
                            discovered.append(artist.name)
                        }
                    }
                } catch {
                    print("⚠️ Long-tail: level-2 walk failed for '\(seed)': \(error)")
                }
                if discovered.count >= maxArtists { break }
            }
            print("🌊 Long-tail: after depth charge, \(discovered.count) artists")
        }

        // 4. Resolve to Spotify tracks, preferring obscure artists.
        // Per-session shuffle so two users walk the same graph differently.
        // Served artists are skipped BEFORE the top-tracks call — no point
        // resolving artists the user has already heard.
        var candidates: [SpotifyTrack] = []
        var seenTrackIds = Set<String>()
        let history = DiscoveryHistoryManager.shared
        let artistCap = min(discovered.count, maxArtists)
        for artistName in discovered.prefix(artistCap).shuffled() {
            guard candidates.count < maxTracks else { break }
            do {
                let artists = try await spotifyAPI.searchArtist(name: artistName, token: token)
                guard let artist = artists.first else { continue }
                // Skip artists already served (persistent history)
                if history.isArtistSeen(artistId: artist.id) { continue }
                // Latency optimization: an artist this popular won't yield
                // tracks under the obscurity threshold — skip the top-tracks call.
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
                // Resolution failures are routine (name mismatches, etc.)
                continue
            }
        }
        print("🌊 Long-tail: resolved \(candidates.count) candidate tracks")
        return candidates
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
