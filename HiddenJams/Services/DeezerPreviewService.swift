//
//  DeezerPreviewService.swift
//  HiddenJams
//
//  30-second previews from Deezer's free API (no key needed). Spotify no
//  longer hands out preview clips, so this is where most previews come from.
//
//  Lookups are exact: by ISRC (the recording's universal ID) first, then by
//  artist + title with strict matching. It never falls back to "whatever
//  came up first" — that's how the wrong song used to play.
//

import Foundation

/// Keeps requests under a rate limit (N per rolling window), shared by
/// every caller.
actor RequestPacer {
    private let maxRequests: Int
    private let window: TimeInterval
    private var starts: [Date] = []

    init(maxRequests: Int, per window: TimeInterval) {
        self.maxRequests = maxRequests
        self.window = window
    }

    /// Waits for a free slot. Returns false if the task was cancelled first.
    func acquire() async -> Bool {
        while !Task.isCancelled {
            let now = Date()
            starts.removeAll { now.timeIntervalSince($0) >= window }
            if starts.count < maxRequests {
                starts.append(now)
                return true
            }
            let wait = max(0.02, window - now.timeIntervalSince(starts[0]))
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        return false
    }
}

class DeezerPreviewService {
    /// Deezer allows 50 requests per 5 seconds per IP; stay just under.
    static let pacer = RequestPacer(maxRequests: 45, per: 5)

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        return URLSession(configuration: config)
    }()

    private enum Lookup {
        case found(DeezerTrack)
        case notFound
        case failed
    }

    /// Preview for exactly this recording, or nil.
    /// - Parameter allowSearch: also try an artist + title search when there's
    ///   no ISRC match. Costs a second request, so the deck builder skips it.
    func findPreview(isrc: String?, title: String, artist: String, allowSearch: Bool = true) async -> String? {
        if let isrc, !isrc.isEmpty {
            switch await lookup(isrc: isrc) {
            case .found(let track):
                // The ISRC identifies the recording; just guard against bad data.
                if let preview = track.preview, !preview.isEmpty,
                   Self.titlesMatch(track.title, title) || Self.artistsMatch(track.artist.name, artist) {
                    return preview
                }
                return nil
            case .notFound:
                if !allowSearch { return nil }
            case .failed:
                break
            }
        }
        guard allowSearch else { return nil }
        return await searchPreview(title: title, artist: artist)
    }

    /// Title + artist only (no ISRC available).
    func findPreview(for trackName: String, artist: String) async -> String? {
        await searchPreview(title: trackName, artist: artist)
    }

    // MARK: - Requests

    private func lookup(isrc: String) async -> Lookup {
        guard let url = URL(string: "https://api.deezer.com/track/isrc:\(Self.encode(isrc))") else {
            return .failed
        }
        for attempt in 0..<2 {
            guard await Self.pacer.acquire(),
                  let response = try? await session.data(from: url) else { return .failed }
            let data = response.0
            if let track = try? JSONDecoder().decode(DeezerTrack.self, from: data) {
                return .found(track)
            }
            guard let envelope = try? JSONDecoder().decode(DeezerErrorEnvelope.self, from: data) else {
                return .failed
            }
            // 4 = over the rate limit: wait a moment and try once more.
            if envelope.error.code == 4, attempt == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            // 800 = "no data": Deezer doesn't have this recording.
            return envelope.error.code == 800 ? .notFound : .failed
        }
        return .failed
    }

    private func searchPreview(title: String, artist: String) async -> String? {
        let cleanArtist = artist.replacingOccurrences(of: "\"", with: "")
        let cleanTitle = Self.searchTitle(title).replacingOccurrences(of: "\"", with: "")
        guard !cleanArtist.isEmpty, !cleanTitle.isEmpty else { return nil }
        let query = "artist:\"\(cleanArtist)\" track:\"\(cleanTitle)\""
        guard let url = URL(string: "https://api.deezer.com/search?q=\(Self.encode(query))&limit=10"),
              await Self.pacer.acquire(),
              let response = try? await session.data(from: url),
              let result = try? JSONDecoder().decode(DeezerSearchResponse.self, from: response.0) else {
            return nil
        }
        let match = result.data.first { track in
            guard let preview = track.preview, !preview.isEmpty else { return false }
            return Self.titlesMatch(track.title, title) && Self.artistsMatch(track.artist.name, artist)
        }
        return match?.preview
    }

    // MARK: - Matching

    /// A title reduced to what identifies the recording: featured credits and
    /// store-specific version tags ("Original Mix", "Radio Edit",
    /// "2011 Remaster") are dropped; real versions ("VIP", "X Remix") stay.
    static func coreTitle(_ raw: String) -> String {
        // Runs for every deck candidate, so plain string scanning, no regex.
        var text = raw.lowercased()
        if !text.allSatisfy(\.isASCII) {
            text = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        }
        // "Song - Radio Edit" -> "Song (Radio Edit)"
        if let dash = text.range(of: " - ") {
            text = String(text[..<dash.lowerBound]) + " (" + String(text[dash.upperBound...]) + ")"
        }
        // Drop bracketed credits and version tags.
        var kept = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "(" || char == "[",
               let end = text[index...].firstIndex(of: char == "(" ? ")" : "]"),
               isCreditOrVersionTag(text[text.index(after: index)..<end]) {
                index = text.index(after: end)
                continue
            }
            kept.append(char)
            index = text.index(after: index)
        }
        // A trailing "feat. Someone" outside brackets.
        for marker in [" feat.", " feat ", " ft.", " ft ", " featuring "] {
            if let range = kept.range(of: marker) {
                kept = String(kept[..<range.lowerBound])
            }
        }
        return kept.filter { $0.isLetter || $0.isNumber }
    }

    private static func isCreditOrVersionTag(_ inner: Substring) -> Bool {
        let tag = inner.trimmingCharacters(in: .whitespaces)
        for credit in ["feat.", "feat ", "featuring", "ft.", "ft ", "with "] where tag.hasPrefix(credit) {
            return true
        }
        for version in ["original mix", "radio edit", "album version", "single version", "remaster",
                        "explicit", "clean version", "mono", "stereo"] where tag.contains(version) {
            return true
        }
        return false
    }

    static func titlesMatch(_ a: String, _ b: String) -> Bool {
        let x = coreTitle(a)
        return !x.isEmpty && x == coreTitle(b)
    }

    static func artistsMatch(_ a: String, _ b: String) -> Bool {
        func words(_ s: String) -> [String] {
            var text = s.lowercased()
            if !text.allSatisfy(\.isASCII) {
                text = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            }
            var list = text.replacingOccurrences(of: "&", with: " and ")
                .split { !($0.isLetter || $0.isNumber) }
                .map(String.init)
            if list.first == "the" { list.removeFirst() }
            return list
        }
        let x = words(a)
        let y = words(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        if x.joined() == y.joined() { return true }
        // "Artist" vs "Artist & Friend" (but not "Side" vs "Side Effect")
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        guard long.count > short.count, Array(long.prefix(short.count)) == short else { return false }
        return ["and", "x", "feat", "ft", "featuring", "with", "vs"].contains(long[short.count])
    }

    /// Title for the search query: anything after " - " and anything in
    /// brackets removed.
    private static func searchTitle(_ raw: String) -> String {
        var text = raw
        if let dash = text.range(of: " - ") {
            text = String(text[..<dash.lowerBound])
        }
        var kept = ""
        var depth = 0
        for char in text {
            if char == "(" || char == "[" { depth += 1; continue }
            if char == ")" || char == "]" { depth = max(0, depth - 1); continue }
            if depth == 0 { kept.append(char) }
        }
        return kept.trimmingCharacters(in: .whitespaces)
    }

    private static func encode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

// MARK: - Deezer API Models

struct DeezerSearchResponse: Codable {
    let data: [DeezerTrack]
}

struct DeezerTrack: Codable {
    let id: Int
    let title: String
    let preview: String?
    let artist: DeezerArtist
}

struct DeezerArtist: Codable {
    let id: Int
    let name: String
}

struct DeezerErrorEnvelope: Codable {
    struct Body: Codable {
        let code: Int
    }
    let error: Body
}
