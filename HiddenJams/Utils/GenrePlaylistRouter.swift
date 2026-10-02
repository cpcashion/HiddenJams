//
//  GenrePlaylistRouter.swift
//  HiddenJams
//
//  Routes swipe-right saves into per-genre playlists ("HJ - Rock",
//  "HJ - Drum and Bass", ...) instead of a single bucket. Genre is resolved
//  from the discovery session first (the user's own genre pick — the most
//  trustworthy signal), then from the artist's genre metadata. Anything
//  unmappable falls back to the classic "Hidden Gems" playlist.
//
//  NOTE: this maps genre STRINGS to genre buckets. It never matches genre
//  words against track or artist names (the build-22 "jungle" rule).
//

import Foundation

/// Decides which playlist a swiped-right track belongs in.
enum GenrePlaylistRouter {

    /// The catch-all playlist when no genre bucket maps.
    static let fallbackPlaylistName = "Hidden Gems"

    /// Playlist name prefix for genre buckets: "HJ - Rock".
    static func playlistName(forBucket bucket: String?) -> String {
        guard let bucket else { return fallbackPlaylistName }
        return "HJ - \(bucket)"
    }

    /// Full routing decision for a swipe-right save.
    /// - Parameter sessionGenres: the genres selected for this discovery
    ///   session (persisted `selectedGenres`). A single-genre session is the
    ///   strongest signal — the user told us what this is.
    static func playlistName(for track: RecommendedTrack, sessionGenres: Set<String>) -> String {
        playlistName(forBucket: bucket(for: track, sessionGenres: sessionGenres))
    }

    /// Coarse bucket ("Rock", "Drum and Bass", ...) or nil.
    static func bucket(for track: RecommendedTrack, sessionGenres: Set<String>) -> String? {
        if sessionGenres.count == 1, let only = sessionGenres.first,
           let bucket = bucket(forGenre: only) {
            return bucket
        }
        for artist in track.track.artists {
            for genre in artist.genres ?? [] {
                if let bucket = bucket(forGenre: genre) { return bucket }
            }
        }
        // Last resort: a single session genre that didn't map directly
        // (e.g. an unusual subgenre string) still names its own bucket
        // rather than the misc pile — but only when unambiguous.
        if sessionGenres.count == 1, let only = sessionGenres.first {
            let cleaned = only.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return titleCased(cleaned) }
        }
        return nil
    }

    // MARK: - Genre string -> coarse bucket

    /// Normalized (lowercased, alphanumeric-only) matcher -> bucket.
    /// Matchers are written human-readable; normalized once at startup.
    private static let matchers: [(matcher: String, bucket: String)] = {
        let table: [(bucket: String, matchers: [String])] = [
            ("Drum and Bass", ["drum and bass", "drum-and-bass", "drum n bass", "dnb", "jungle", "liquid funk", "neurofunk", "breakbeat", "drumstep"]),
            ("Dubstep", ["dubstep", "brostep", "riddim", "tearout"]),
            ("Hip-Hop", ["hip-hop", "hip hop", "rap", "trap", "drill", "grime", "boom bap", "cloud rap", "emo rap", "trap soul"]),
            ("R&B", ["r&b", "rhythm and blues", "neo soul", "neo-soul", "soul", "quiet storm", "new jack swing"]),
            ("Pop", ["dance pop", "dance-pop", "synthpop", "synth pop", "electropop", "indie pop", "art pop", "hyperpop", "k-pop", "j-pop", "pop rock", "pop"]),
            ("Rock", ["indie rock", "alternative rock", "alt rock", "alternative", "indie", "psychedelic rock", "garage rock", "hard rock", "classic rock", "prog rock", "progressive rock", "post rock", "post-rock", "shoegaze", "grunge", "britpop", "emo", "screamo", "stoner rock", "surf rock", "rock"]),
            ("Metal", ["heavy metal", "death metal", "black metal", "thrash metal", "doom metal", "metalcore", "deathcore", "nu metal", "power metal", "speed metal", "metal"]),
            ("Punk", ["pop punk", "pop-punk", "hardcore punk", "post-punk", "post punk", "skate punk", "punk"]),
            ("Electronic", ["electronica", "edm", "big beat", "trip hop", "trip-hop", "downtempo", "idm", "uk garage", "future garage", "bassline", "future bass", "bass music", "chillwave", "vaporwave", "lo-fi", "lofi", "drone", "industrial", "ebm", "witch house", "deconstructed club", "dance", "electronic"]),
            ("House", ["deep house", "tech house", "progressive house", "french house", "acid house", "house"]),
            ("Techno", ["detroit techno", "minimal techno", "acid techno", "hard techno", "techno"]),
            ("Trance", ["psytrance", "goa trance", "uplifting trance", "trance"]),
            ("Ambient", ["ambient", "dark ambient", "ambient dub", "field recordings", "new age", "space music"]),
            ("Jazz", ["bebop", "hard bop", "cool jazz", "modal jazz", "smooth jazz", "fusion", "jazz fusion", "swing", "nu jazz", "nu-jazz", "acid jazz", "jazz rap", "jazz funk", "bossa nova", "jazz"]),
            ("Funk", ["p-funk", "funk", "boogie", "disco", "nu-disco", "nudisco", "french disco"]),
            ("Blues", ["delta blues", "chicago blues", "electric blues", "blues rock", "blues"]),
            ("Reggae", ["roots reggae", "dub", "dancehall", "ska", "rocksteady", "lovers rock", "reggae"]),
            ("Latin", ["reggaeton", "latin pop", "salsa", "bachata", "cumbia", "tango", "flamenco", "samba", "bossa", "mariachi", "latin jazz", "latin"]),
            ("Afrobeats", ["afrobeats", "afrobeat", "afro pop", "afropop", "amapiano", "azonto"]),
            ("Country", ["outlaw country", "country pop", "americana", "bluegrass", "honky tonk", "alt country", "country"]),
            ("Folk", ["singer-songwriter", "indie folk", "freak folk", "anti-folk", "antifolk", "acoustic folk", "folk"]),
            ("Classical", ["contemporary classical", "orchestral", "symphonic", "chamber music", "opera", "baroque", "minimalism", "classical"]),
            ("Soundtrack", ["film score", "soundtrack", "video game music", "score", "musical theatre", "show tunes"]),
            ("Gospel", ["gospel", "christian music", "worship", "ccm"]),
            ("World", ["celtic", "klezmer", "qawwali", "fado", "flamenco", "world"]),
        ]
        return table.flatMap { entry in
            entry.matchers.map { (matcher: norm($0), bucket: entry.bucket) }
        }
    }()

    /// Maps a genre string to its coarse bucket, or nil when unmappable.
    /// Exact normalized matches win; otherwise the LONGEST containing
    /// matcher wins (most specific: "pop punk" -> Punk, not Pop).
    static func bucket(forGenre genre: String) -> String? {
        let n = norm(genre)
        guard !n.isEmpty else { return nil }
        if let exact = matchers.first(where: { $0.matcher == n }) {
            return exact.bucket
        }
        let candidates = matchers.filter { n.contains($0.matcher) || $0.matcher.contains(n) }
        return candidates.max(by: { $0.matcher.count < $1.matcher.count })?.bucket
    }

    // MARK: - Helpers

    /// Lowercased, alphanumeric only: "Hip-Hop/Rap" -> "hiphoprap".
    static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func titleCased(_ s: String) -> String {
        s.split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
