//
//  SpotifyGenreDeckCatalog.swift
//  HiddenJams
//
//  The live data source for GenreDeckBuilder: Spotify search and artist
//  lookups, plus Deezer previews. Short timeouts, no sleeps between calls,
//  and every failure degrades to "no result" instead of an error.
//

import Foundation

final class SpotifyGenreDeckCatalog: GenreDeckCatalog {
    private let token: String
    private let deezer = DeezerPreviewService()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    /// 50 results per search page; drops to 10 if Spotify rejects 50
    /// (newer Spotify app tiers cap search pages at 10).
    private var pageSize = 50
    /// Set when the batch artists endpoint isn't available to this app.
    private var batchArtistsUnavailable = false

    /// True once Spotify answered 401: the user needs to sign in again.
    private(set) var authFailed = false
    private(set) var failedRequests = 0

    init(token: String) {
        self.token = token
    }

    private struct HTTPResult {
        let data: Data
        let status: Int
    }

    // MARK: - GenreDeckCatalog

    func searchTracks(query: String, offset: Int) async -> GenreDeckSearchPage? {
        let limit = pageSize
        let safeOffset = max(0, min(offset, 1000 - limit))
        let url = URL(string: "https://api.spotify.com/v1/search?q=\(Self.encode(query))"
            + "&type=track&limit=\(limit)&offset=\(safeOffset)&market=from_token")
        guard let url, let response = await get(url) else { return nil }
        if response.status == 400, limit > 10 {
            pageSize = 10
            return await searchTracks(query: query, offset: offset)
        }
        guard response.status == 200,
              let decoded = try? JSONDecoder().decode(DeckSearchResponse.self, from: response.data) else {
            return nil
        }
        let tracks = decoded.tracks.items.compactMap { $0.value }.filter { $0.spotifyId != nil }
        return GenreDeckSearchPage(tracks: tracks, total: decoded.tracks.total, limit: limit)
    }

    func artists(ids: [String]) async -> [SpotifyArtist] {
        guard !ids.isEmpty else { return [] }
        if batchArtistsUnavailable { return await artistsOneByOne(ids) }
        guard let url = URL(string: "https://api.spotify.com/v1/artists?ids=\(ids.joined(separator: ","))"),
              let response = await get(url) else { return [] }
        if response.status == 403 || response.status == 404 {
            batchArtistsUnavailable = true
            return await artistsOneByOne(ids)
        }
        guard response.status == 200,
              let decoded = try? JSONDecoder().decode(DeckArtistsResponse.self, from: response.data) else {
            return []
        }
        return decoded.artists.compactMap { $0.value }
    }

    func previewURL(for track: SpotifyTrack) async -> String? {
        if let url = track.previewUrl, !url.isEmpty { return url }
        return await deezer.findPreview(
            isrc: track.isrc,
            title: track.name,
            artist: track.artists.first?.name ?? "",
            allowSearch: track.isrc == nil
        )
    }

    // MARK: - Requests

    private func artistsOneByOne(_ ids: [String]) async -> [SpotifyArtist] {
        let results = await GenreDeckBuilder.concurrentMap(
            ids, limit: 8, deadline: Date().addingTimeInterval(4)
        ) { [weak self] id -> SpotifyArtist? in
            guard let self,
                  let url = URL(string: "https://api.spotify.com/v1/artists/\(id)"),
                  let response = await self.get(url),
                  response.status == 200 else { return nil }
            return try? JSONDecoder().decode(SpotifyArtist.self, from: response.data)
        }
        return results.compactMap { $0 }
    }

    private func get(_ url: URL, retryOnRateLimit: Bool = true) async -> HTTPResult? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status == 429, retryOnRateLimit {
                // Honor short Retry-After waits only; a long one would blow
                // the time budget, so that request is simply skipped.
                let wait = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
                if wait <= 2 {
                    try await Task.sleep(nanoseconds: UInt64((wait + 0.25) * 1_000_000_000))
                    return await get(url, retryOnRateLimit: false)
                }
            }
            if status == 401 { authFailed = true }
            if status != 200 { failedRequests += 1 }
            return HTTPResult(data: data, status: status)
        } catch {
            failedRequests += 1
            return nil
        }
    }

    /// Strict query encoding: everything but unreserved ASCII is escaped
    /// (Foundation leaves "&" and "+" alone, which breaks "r&b").
    private static func encode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

// MARK: - Response models

/// Decodes what it can: one malformed (or null) item doesn't sink the page.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct DeckSearchResponse: Decodable {
    struct Page: Decodable {
        let items: [Lenient<SpotifyTrack>]
        let total: Int
    }
    let tracks: Page
}

private struct DeckArtistsResponse: Decodable {
    let artists: [Lenient<SpotifyArtist>]
}
