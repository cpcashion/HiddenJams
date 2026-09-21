//
//  ArtistFirstDiscovery.swift
//  HiddenJams
//
//  Finds obscure artists in a genre, then their tracks.
//

import Foundation

/// Discovery built around artists rather than tracks.
///
/// ## Why artist-first
///
/// The original engine searched *tracks* by genre and then tried to work out
/// how obscure each one was. That has two problems:
///
///  1. A track's `popularity` says nothing about whether the *artist* is
///     undiscovered. A famous artist's deep cut scores low, so the old engine
///     surfaced album filler by well-known acts — the opposite of the point.
///  2. Track objects do not carry follower counts, so judging obscurity meant
///     a second round-trip per artist.
///
/// Searching artists directly fixes both. The artist objects Spotify returns
/// already carry `followers.total` and `popularity`, so the slider can filter
/// them with no extra requests, and "obscure" means what the user expects:
/// an artist hardly anyone follows.
///
/// Every endpoint used here is current. Nothing in this file depends on the
/// Related Artists, Recommendations or Audio Features endpoints that Spotify
/// deprecated in November 2024.
final class ArtistFirstDiscovery {

    private let spotifyAPI: SpotifyAPIService
    private let lastFm: LastFmService
    private let crossReference: SpotifyCrossReferenceService

    init(
        spotifyAPI: SpotifyAPIService = SpotifyAPIService(),
        lastFm: LastFmService = LastFmService(),
        crossReference: SpotifyCrossReferenceService = SpotifyCrossReferenceService()
    ) {
        self.spotifyAPI = spotifyAPI
        self.lastFm = lastFm
        self.crossReference = crossReference
    }

    // MARK: - Artist Search

    /// Finds artists in the given genres that fall inside the obscurity window.
    ///
    /// - Parameters:
    ///   - genres: Genres to search, as Spotify spells them (e.g. "drum and bass").
    ///   - window: The slider's filter window.
    ///   - excludedArtistIds: Artists already shown, so repeat runs stay fresh.
    ///   - targetCount: Stop early once this many qualifying artists are found.
    /// - Returns: Qualifying artists, most obscure first.
    func findArtists(
        genres: [String],
        window: ObscurityWindow,
        excludedArtistIds: Set<String> = [],
        targetCount: Int = 60,
        token: String,
        progress: ((String) -> Void)? = nil
    ) async -> [SpotifyArtist] {

        guard !genres.isEmpty else { return [] }

        var found: [String: SpotifyArtist] = [:]

        // Rotating offsets keep repeat runs from returning the same first page.
        // Spotify caps search offset at 1000, and `searchArtists` clamps for us.
        let offsets = [0, 50, 150, 300, 500, 750]

        outer: for genre in genres.prefix(6) {
            for query in queries(for: genre, window: window) {
                for offset in offsets.shuffled().prefix(3) {
                    if found.count >= targetCount { break outer }

                    do {
                        progress?("Searching \(genre)…")

                        let artists = try await spotifyAPI.searchArtists(
                            query: query,
                            limit: 50,
                            offset: offset,
                            token: token
                        )

                        for artist in artists {
                            guard let id = artist.spotifyId else { continue }
                            guard !excludedArtistIds.contains(id) else { continue }
                            guard found[id] == nil else { continue }
                            guard window.admits(artist: artist) else { continue }
                            found[id] = artist
                        }

                        // Stay well inside Spotify's rate limit.
                        try await Task.sleep(nanoseconds: 120_000_000)
                    } catch {
                        // A single failed page should never sink the run.
                        print("⚠️ Artist search failed for '\(query)' @\(offset): \(error)")
                        continue
                    }
                }
            }
        }

        return rank(Array(found.values))
    }

    /// Builds the query variants to try for one genre.
    ///
    /// `tag:hipster` is Spotify's own "bottom 10% by popularity" filter. It is
    /// by far the cheapest way to reach genuinely obscure artists, so at the
    /// obscure end of the slider we lead with it and keep the plain genre
    /// search as a fallback for genres where the tag returns little.
    private func queries(for genre: String, window: ObscurityWindow) -> [String] {
        let quoted = "genre:\"\(genre)\""
        if window.useHipsterTag {
            return ["\(quoted) tag:hipster", quoted]
        }
        return [quoted]
    }

    /// Most obscure first — fewest followers, then lowest popularity.
    private func rank(_ artists: [SpotifyArtist]) -> [SpotifyArtist] {
        artists.sorted { lhs, rhs in
            let lf = lhs.followers?.total ?? 0
            let rf = rhs.followers?.total ?? 0
            if lf != rf { return lf < rf }
            return (lhs.popularity ?? 0) < (rhs.popularity ?? 0)
        }
    }

    // MARK: - Similar Artists (replaces Spotify's deprecated Related Artists)

    /// Finds artists similar to the given names via Last.fm, then resolves them
    /// back to Spotify and filters by the window.
    ///
    /// This is the direct replacement for `/artists/{id}/related-artists`.
    /// Last.fm's similarity graph is community-built and, for underground
    /// music, generally deeper than Spotify's was.
    func similarArtists(
        toArtistsNamed seedNames: [String],
        window: ObscurityWindow,
        excludedArtistIds: Set<String> = [],
        limitPerSeed: Int = 20,
        token: String
    ) async -> [SpotifyArtist] {

        guard !seedNames.isEmpty else { return [] }

        var similarNames: [String] = []

        for seed in seedNames.prefix(5) {
            do {
                let similar = try await lastFm.getSimilarArtists(
                    artistName: seed,
                    limit: limitPerSeed
                )
                similarNames.append(contentsOf: similar.map { $0.name })
            } catch {
                print("⚠️ Last.fm similar-artist lookup failed for '\(seed)': \(error)")
                continue
            }
        }

        guard !similarNames.isEmpty else { return [] }

        // De-duplicate case-insensitively before spending Spotify lookups.
        var seenNames = Set<String>()
        let uniqueNames = similarNames.filter { name in
            let key = name.lowercased()
            guard !seenNames.contains(key) else { return false }
            seenNames.insert(key)
            return true
        }

        var resolved: [SpotifyArtist] = []

        do {
            let matches = try await crossReference.findSpotifyArtists(
                names: Array(uniqueNames.prefix(40)),
                token: token
            )

            let ids = matches
                .map { $0.spotifyID }
                .filter { !excludedArtistIds.contains($0) }

            guard !ids.isEmpty else { return [] }

            // Fetch full artist objects so follower counts are present.
            for chunk in ids.chunked(into: 50) {
                let artists = try await spotifyAPI.getArtists(ids: chunk, token: token)
                resolved.append(contentsOf: artists.filter { window.admits(artist: $0) })
            }
        } catch {
            print("⚠️ Resolving Last.fm artists to Spotify failed: \(error)")
            return []
        }

        return rank(resolved)
    }

    // MARK: - Tracks

    /// Collects playable tracks for the given artists.
    ///
    /// Uses each artist's top tracks, which for an obscure artist is simply
    /// their best-known handful — exactly what a listener should hear first.
    /// `maxPerArtist` keeps one prolific artist from flooding the results.
    func tracks(
        for artists: [SpotifyArtist],
        maxPerArtist: Int = 2,
        market: String = "US",
        token: String,
        progress: ((String) -> Void)? = nil
    ) async -> [SpotifyTrack] {

        var collected: [SpotifyTrack] = []
        var processed = 0

        for artist in artists {
            guard let artistId = artist.spotifyId else { continue }

            do {
                let top = try await spotifyAPI.getArtistTopTracks(
                    artistId: artistId,
                    market: market,
                    token: token
                )
                collected.append(contentsOf: top.prefix(maxPerArtist))

                processed += 1
                if processed % 10 == 0 {
                    progress?("Collecting tracks… \(processed)/\(artists.count)")
                }

                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                print("⚠️ Top tracks failed for \(artist.name): \(error)")
                continue
            }
        }

        return collected
    }
}
