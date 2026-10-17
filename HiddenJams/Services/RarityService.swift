import Foundation

/// How rare an artist is, computed from Spotify + Last.fm signals.
/// Spotify's public API does not expose "monthly listeners" — so rarity is
/// derived from followers, popularity (inverted), and Last.fm crowd stats.
struct ArtistRarity {
    enum Tier: String {
        case mythic
        case ultraRare
        case rare
        case emerging
        case known

        var emoji: String {
            switch self {
            case .mythic: return "💎"
            case .ultraRare: return "🔥"
            case .rare: return "✨"
            case .emerging: return "🌱"
            case .known: return "🎵"
            }
        }

        var label: String {
            switch self {
            case .mythic: return "MYTHIC"
            case .ultraRare: return "ULTRA RARE"
            case .rare: return "RARE"
            case .emerging: return "EMERGING"
            case .known: return "KNOWN"
            }
        }

        var tagline: String {
            switch self {
            case .mythic: return "virtually undiscovered"
            case .ultraRare: return "deeper than deep cuts"
            case .rare: return "a true hidden gem"
            case .emerging: return "on the rise"
            case .known: return "gaining traction"
            }
        }
    }

    let tier: Tier
    /// 0-100, higher = rarer. Derived from 100 - Spotify popularity.
    let score: Int
    let followers: Int?
    let popularity: Int?
    let lastFmListeners: Int?
    let lastFmPlaycount: Int?
    let genres: [String]
    let artistName: String

    /// e.g. 99.7 for "rarer than 99.7% of artists on Spotify"
    var rarerThanPercent: Double {
        Double(score)
    }

    var formattedFollowers: String? {
        guard let followers else { return nil }
        if followers >= 1_000_000 {
            return String(format: "%.1fM", Double(followers) / 1_000_000)
        } else if followers >= 1_000 {
            return String(format: "%.1fK", Double(followers) / 1_000)
        }
        return "\(followers)"
    }
}

/// Computes artist rarity from Spotify + Last.fm. Cached per session.
class RarityService {
    static let shared = RarityService()

    private var cache: [String: ArtistRarity] = [:]
    private let spotifyAPI = SpotifyAPIService()
    private let lastFmService = LastFmService()

    private init() {}

    /// Rarity for an artist. Fetches full Spotify details + Last.fm stats if
    /// not cached. Spotify token is optional (Apple Music-only users get
    /// Last.fm data only).
    func rarity(for artist: SpotifyArtist, spotifyToken: String?) async -> ArtistRarity {
        let cacheKey = artist.id
        if let cached = cache[cacheKey] { return cached }

        var followers = artist.followers?.total
        var popularity = artist.popularity
        var genres = artist.genres ?? []

        // Enrich from Spotify if details are missing and we have a token
        if let token = spotifyToken, (followers == nil || popularity == nil) {
            if let full = try? await spotifyAPI.getArtists(ids: [artist.id], token: token).first {
                followers = full.followers?.total ?? followers
                popularity = full.popularity ?? popularity
                if genres.isEmpty { genres = full.genres ?? [] }
            }
        }

        // Last.fm crowd stats (independent of Spotify)
        var lfmListeners: Int?
        var lfmPlaycount: Int?
        if let info = try? await lastFmService.getArtistInfo(name: artist.name) {
            let l = info.listeners
            if l > 0 { lfmListeners = l }
            if let pc = Int(info.stats?.playcount ?? ""), pc > 0 { lfmPlaycount = pc }
        }

        let score = 100 - (popularity ?? 50)
        let tier: ArtistRarity.Tier
        switch score {
        case 95...100: tier = .mythic
        case 85..<95: tier = .ultraRare
        case 70..<85: tier = .rare
        case 50..<70: tier = .emerging
        default: tier = .known
        }

        let rarity = ArtistRarity(
            tier: tier,
            score: max(0, min(100, score)),
            followers: followers,
            popularity: popularity,
            lastFmListeners: lfmListeners,
            lastFmPlaycount: lfmPlaycount,
            genres: genres,
            artistName: artist.name
        )
        cache[cacheKey] = rarity
        return rarity
    }

    func clearCache() {
        cache.removeAll()
    }
}
