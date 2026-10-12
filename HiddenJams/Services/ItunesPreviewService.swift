//
//  ItunesPreviewService.swift
//  HiddenJams
//
//  Fallback service to fetch 30s previews from iTunes when Spotify fails.
//  Also used as the primary playable-source resolver for Apple Music discovery
//  candidates (no Spotify token required).
//

import Foundation

/// Abstraction over the iTunes Search API catalog. Lets the discovery
/// pipeline (and its tests) swap in a stub without touching the network.
protocol ItunesCatalog {
    func searchTrack(name: String, artist: String) async -> ItunesPreviewService.ItunesTrack?
    func searchGenreTracks(genre: String, limit: Int) async -> [ItunesPreviewService.ItunesTrack]
}

class ItunesPreviewService: ItunesCatalog {
    private let baseURL = "https://itunes.apple.com/search"

    struct ItunesResponse: Codable {
        let resultCount: Int
        let results: [ItunesTrack]
    }

    struct ItunesTrack: Codable {
        let trackId: Int
        let trackName: String
        let artistName: String
        let previewUrl: String?
        let trackViewUrl: String?
        let artworkUrl100: String?
        let collectionName: String?
        let primaryGenreName: String?
        let releaseDate: String?
        let trackTimeMillis: Int?

        /// 100x100 artwork upscaled to 600x600 (iTunes supports arbitrary sizes)
        var artworkURL: URL? {
            guard let raw = artworkUrl100 else { return nil }
            return URL(string: raw.replacingOccurrences(of: "100x100", with: "600x600"))
        }

        /// Convert to the SpotifyTrack shape the discovery pipeline understands.
        /// Uses a deterministic namespaced id ("itunes:<trackId>") so `id` is
        /// stable; `isSpotifyOrigin` stays false so no Spotify API lookup is
        /// ever attempted for these candidates.
        /// - Parameters:
        ///   - previewURL: playable preview (usually `previewUrl`)
        ///   - popularity: 0-100 pseudo-popularity mapped from Last.fm listeners
        func toSpotifyTrack(previewURL: String?, popularity: Int) -> SpotifyTrack {
            // Stable namespaced artist ID (not nil): SpotifyArtist.id falls
            // back to a random UUID when spotifyId is nil, which silently
            // broke session artist dedup and DiscoveryHistoryManager artist
            // tracking for every Apple Music track. A normalized-name ID is
            // stable across discovers. (isSpotifyOrigin stays false — it
            // checks for ":" — so enrichment still skips these correctly.)
            let artist = SpotifyArtist(
                spotifyId: "itunesartist:\(artistName.lowercased().filter { $0.isLetter || $0.isNumber })",
                name: artistName,
                genres: primaryGenreName.map { [$0] },
                popularity: nil,
                images: nil,
                followers: nil
            )
            let images: [SpotifyImage] = artworkURL.map { [SpotifyImage(url: $0, height: nil, width: nil)] } ?? []
            let album = SpotifyAlbum(
                spotifyId: nil,
                name: collectionName ?? "Unknown Album",
                images: images,
                releaseDate: releaseDate,
                tracks: nil,
                artists: nil
            )
            return SpotifyTrack(
                spotifyId: "itunes:\(trackId)",
                name: trackName,
                artists: [artist],
                album: album,
                popularity: popularity,
                previewUrl: previewURL,
                uri: trackViewUrl ?? "",
                durationMs: trackTimeMillis ?? 0
            )
        }
    }

    func findPreview(for trackName: String, artist: String) async -> String? {
        await searchTrack(name: trackName, artist: artist)?.previewUrl
    }

    /// Direct genre discovery via the iTunes Search API.
    ///
    /// This is the guaranteed-discovery backend of last resort: it needs no
    /// API key, no Last.fm, and no Spotify token. If the device can reach
    /// Apple at all (which Apple Music itself requires), this returns tracks.
    /// Results arrive newest-relevance-first with preview URLs, artwork, and
    /// genre metadata inline — no second lookup needed.
    func searchGenreTracks(genre: String, limit: Int = 200) async -> [ItunesTrack] {
        // VARIED QUERIES: iTunes Search has no offset parameter, so we vary
        // the search terms to get different result sets each run. Each variation
        // hits a different slice of the catalog.
        let variations = Self.queryVariations(for: genre).shuffled()
        var allResults: [ItunesTrack] = []
        var seenIds = Set<Int>()

        for term in variations.prefix(3) {
            var components = URLComponents(string: baseURL)!
            components.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "media", value: "music"),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 200))")
            ]

            guard let url = components.url else { continue }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ItunesResponse.self, from: data)
                // Deduplicate by track ID, shuffle for variety
                for track in response.results.shuffled() {
                    if seenIds.insert(track.trackId).inserted {
                        allResults.append(track)
                    }
                }
            } catch {
                print("⚠️ iTunes genre search failed for '\(term)': \(error.localizedDescription)")
                continue
            }
        }

        return Array(allResults.shuffled().prefix(limit))
    }

    /// Generate varied search terms for a genre to hit different catalog slices.
    private static func queryVariations(for genre: String) -> [String] {
        let lower = genre.lowercased()
        var variations = [genre, "\(genre) music"]

        // Genre synonyms to expand reach
        let synonyms: [String: [String]] = [
            "electronic": ["electronica", "edm", "techno", "house music", "dance electronic"],
            "rock": ["rock music", "alternative rock", "indie rock", "hard rock"],
            "hip-hop": ["hip hop", "rap", "hip-hop music", "rap music"],
            "pop": ["pop music", "dance pop", "indie pop"],
            "jazz": ["jazz music", "smooth jazz", "bebop"],
            "classical": ["classical music", "orchestral", "symphony"],
            "country": ["country music", "americana", "folk country"],
            "r&b": ["r&b music", "soul music", "neo soul"],
            "metal": ["heavy metal", "metal music", "thrash metal"],
            "punk": ["punk rock", "punk music", "hardcore punk"],
            "folk": ["folk music", "indie folk", "acoustic folk"],
            "blues": ["blues music", "electric blues"],
            "reggae": ["reggae music", "dub", "dancehall"],
            "latin": ["latin music", "reggaeton", "salsa music"],
            "k-pop": ["kpop", "k-pop music", "korean pop"],
        ]

        if let syns = synonyms[lower] {
            variations.append(contentsOf: syns)
        }

        return variations
    }

    /// Full iTunes Search API lookup for a track. Returns the best fuzzy match
    /// with artwork, album, genre, and release-date metadata.
    func searchTrack(name: String, artist: String) async -> ItunesTrack? {
        // Clean up query
        let cleanTrack = name.replacingOccurrences(of: " - Remastered", with: "")
            .replacingOccurrences(of: " - Remaster", with: "")
            .components(separatedBy: " (")[0] // Remove (feat. X) or (2011 Remaster)

        let query = "\(cleanTrack) \(artist)"

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ItunesResponse.self, from: data)

            // Find best match
            if let match = response.results.first(where: { result in
                // Simple fuzzy match check
                let resultTrack = result.trackName.lowercased()
                let targetTrack = cleanTrack.lowercased()
                return resultTrack.contains(targetTrack) || targetTrack.contains(resultTrack)
            }) {
                return match
            }

            // Fallback to first result if strict match fails
            return response.results.first

        } catch {
            print("⚠️ iTunes search failed for \(name): \(error.localizedDescription)")
            return nil
        }
    }
}
