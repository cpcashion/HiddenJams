//
//  TasteRarityProvider.swift
//  HiddenJams
//
//  Rarity for the post-sign-in taste profile. Deliberately NOT Spotify
//  popularity (gated / removed in Spotify Development Mode).
//
//  This is a THIN adapter. Launch's hybrid-discovery Phase 2 adds
//  `RarityProviding` (Services/RarityProvider.swift) with `ObscuritySignal`
//  and a shared Last.fm cache + rate limiter. When that lands, replace
//  `LastFmTasteRarityProvider` with an adapter over `RarityProviding`
//  (see `TasteRarityProvider` docs) — the taste-profile code only talks to
//  this protocol, so nothing else changes.
//

import Foundation

/// One artist's rarity as the taste profile needs it.
struct TasteArtistRarity: Codable, Equatable {
    enum Source: String, Codable { case lastFm, spotify, unknown }

    /// 0-100, higher = rarer (same scale as `ArtistRarity.score`).
    let score: Int
    let listeners: Int?
    let playcount: Int?
    let source: Source

    var tier: ArtistRarity.Tier { TasteRarity.tier(forScore: score) }
}

/// Source of artist rarity for the taste profile.
///
/// Phase 2 plug-in (Launch): back this with `RarityProviding`, e.g.
/// ```
/// struct HybridTasteRarityProvider: TasteRarityProvider {
///     let provider: RarityProviding
///     func rarities(forArtists names: [String], deadline: Date) async -> [String: TasteArtistRarity] {
///         let signals = await provider.signals(forArtists: names, deadline: deadline)
///         return signals.compactMapValues { s in
///             guard let pop = s.popularity else { return nil }      // unknown → skipped, never faked
///             return TasteArtistRarity(score: 100 - pop, listeners: s.listeners,
///                                      playcount: s.playcount, source: .init(s.source))
///         }
///     }
/// }
/// ```
/// and swap the default in `TasteRarity.makeDefaultProvider()`.
protocol TasteRarityProvider {
    /// Rarity per artist name (keys = the names passed in). Artists with no
    /// usable signal are omitted. Must return by `deadline` (best effort).
    func rarities(forArtists names: [String], deadline: Date) async -> [String: TasteArtistRarity]
}

enum TasteRarity {
    /// The provider the taste profile uses today.
    static func makeDefaultProvider() -> TasteRarityProvider {
        LastFmTasteRarityProvider()
    }

    /// Same tier cut-offs as `RarityService` so the profile reads on the
    /// same ladder as the card badges.
    static func tier(forScore score: Int) -> ArtistRarity.Tier {
        switch score {
        case 95...: return .mythic
        case 85..<95: return .ultraRare
        case 70..<85: return .rare
        case 50..<70: return .emerging
        default: return .known
        }
    }

    /// Minimal listeners → 0-100 rarity mapping (log scale):
    /// ≤1K listeners → 100, 10K → 81, 100K → 63, 1M → 44, 10M → 25.
    /// TODO(Launch Phase 2): swap for RarityProvider's static
    /// `pseudoPopularity(listeners:)` (rarity = 100 - pseudoPopularity) so
    /// discovery and the taste profile share one mapping.
    static func score(forListeners listeners: Int) -> Int {
        guard listeners > 1_000 else { return 100 }
        let raw = 100 - (log10(Double(listeners)) - 3) * 18.75
        return max(0, min(100, Int(raw.rounded())))
    }

    /// Tier weights for the profile score (known 0 … mythic 1).
    static func weight(for tier: ArtistRarity.Tier) -> Double {
        switch tier {
        case .known: return 0
        case .emerging: return 0.35
        case .rare: return 0.65
        case .ultraRare: return 0.9
        case .mythic: return 1
        }
    }
}

/// Interim implementation: calls the EXISTING Last.fm client directly
/// (artist.getInfo listeners/playcount). No extra cache or rate limiter on
/// purpose; Launch's Phase 2 brings the shared ones. `LastFmService`
/// already spaces its own requests.
final class LastFmTasteRarityProvider: TasteRarityProvider {
    private let lastFm: LastFmService

    init(lastFm: LastFmService = LastFmService()) {
        self.lastFm = lastFm
    }

    func rarities(forArtists names: [String], deadline: Date) async -> [String: TasteArtistRarity] {
        var result: [String: TasteArtistRarity] = [:]
        for name in names {
            if Date() >= deadline || Task.isCancelled { break }
            guard let info = try? await lastFm.getArtistInfo(name: name) else { continue }
            let listeners = info.listeners
            guard listeners > 0 else { continue }   // unknown → omitted, never guessed
            result[name] = TasteArtistRarity(
                score: TasteRarity.score(forListeners: listeners),
                listeners: listeners,
                playcount: Int(info.stats?.playcount ?? ""),
                source: .lastFm
            )
        }
        return result
    }
}
