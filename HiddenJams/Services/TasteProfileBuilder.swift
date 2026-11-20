//
//  TasteProfileBuilder.swift
//  HiddenJams
//
//  Onboarding v5, post-sign-in taste profile ("Digging through your
//  library…" + the reveal chapters). Every number shown comes from the
//  user's real library; nothing is faked, and a stage that can't run is
//  not shown.
//
//  Data sources
//  - Spotify: top artists (`/me/top/artists`) + saved songs (via the
//    existing AIProfileAnalyzer run, which the app needs anyway).
//  - Apple Music: library songs with `Song.playCount` + `genreNames`.
//    No top-artists list for Apple users (Chris, Nov 18).
//  - Rarity: `TasteRarityProvider` (Last.fm today, Launch's hybrid
//    provider later). Never Spotify popularity.
//

import Foundation
import Combine
import SwiftUI
import MusicKit

// MARK: - Model

struct TasteProfile: Codable, Equatable {
    struct GenreShare: Codable, Equatable, Hashable {
        /// Lowercased catalog genre (same strings as `selectedGenres`).
        let genre: String
        /// 0-1 share of the user's genre-tagged listening.
        let share: Double
    }

    struct SignatureArtist: Codable, Equatable, Hashable {
        let name: String
        let imageURL: URL?
        let savedSongs: Int
    }

    struct DeepCut: Codable, Equatable {
        let title: String
        let artistName: String
        let artworkURL: URL?
        /// Apple library artwork (drawn with `ArtworkImage`).
        let appleArtwork: Artwork?
        /// Artist's Last.fm listeners (the rarity signal).
        let artistListeners: Int?
        /// How often the user played it (Apple Music only).
        let userPlayCount: Int?
        let rarityScore: Int
    }

    var topGenres: [GenreShare] = []
    /// 0-100; nil when too few artists had a rarity signal.
    var rarityScore: Int?
    var ratedArtistCount: Int = 0
    /// Spotify only (empty for Apple Music-only users).
    var signatureArtists: [SignatureArtist] = []
    var deepestCut: DeepCut?
    var librarySize: Int = 0
    var sources: [MusicSource] = []
    var generatedAt: Date = Date()

    var tier: ArtistRarity.Tier? { rarityScore.map(TasteRarity.tier(forScore:)) }

    /// < 10 songs → "Fresh start" instead of the chapters.
    var isEmptyLibrary: Bool { librarySize < TasteProfileBuilder.minimumLibrarySize }

    static let storageKey = "hj.tasteProfile.v1"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }

    static func load(from defaults: UserDefaults = .standard) -> TasteProfile? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(TasteProfile.self, from: data)
    }
}

// MARK: - Pure helpers (unit-tested)

enum TasteProfileBuilder {
    static let minimumLibrarySize = 10
    static let minimumRatedArtists = 3

    /// Catalog genres (lowercased, picker order) with one matcher each.
    /// Genres in the same matcher family (Hip Hop + Rap) keep the first.
    private static let catalogMatchers: [(genre: String, matcher: GenreMatcher)] = {
        var seenFamilies = Set<String>()
        var result: [(String, GenreMatcher)] = []
        for genre in GenreCatalog.common.map({ $0.lowercased() }) {
            let key = GenreMatcher.family(for: genre).key
            guard !key.isEmpty, seenFamilies.insert(key).inserted else { continue }
            result.append((genre, GenreMatcher(selections: [genre])))
        }
        return result
    }()

    /// Catalog genres a raw label (Spotify "neo soul", Apple "R&B/Soul")
    /// belongs to. Apple's slash-joined names are split first.
    static func catalogGenres(forLabel label: String) -> [String] {
        let parts = label.split(separator: "/").map { GenreMatcher.tokens(String($0)) }
        return catalogMatchers.compactMap { entry in
            guard let hit = entry.matcher.match(labels: parts), hit.tier == 0 else { return nil }
            return entry.genre
        }
    }

    /// Top catalog genres with shares, from raw label → weight.
    /// A label matching several genres splits its weight between them.
    /// Labels that map to no catalog genre are ignored.
    static func genreShares(weightedLabels: [String: Double], limit: Int = 5) -> [TasteProfile.GenreShare] {
        var weights: [String: Double] = [:]
        for (label, weight) in weightedLabels where weight > 0 {
            let genres = catalogGenres(forLabel: label)
            guard !genres.isEmpty else { continue }
            let each = weight / Double(genres.count)
            for g in genres { weights[g, default: 0] += each }
        }
        let total = weights.values.reduce(0, +)
        guard total > 0 else { return [] }
        return weights
            .map { TasteProfile.GenreShare(genre: $0.key, share: $0.value / total) }
            .sorted { $0.share != $1.share ? $0.share > $1.share : $0.genre < $1.genre }
            .prefix(limit)
            .map { $0 }
    }

    /// Profile rarity: weight-averaged tier weights over the rated artists
    /// (known 0 … mythic 1) × 100, so it reads on the card-badge ladder.
    /// Nil when fewer than `minimumRatedArtists` have a signal.
    static func profileScore(artistWeights: [(name: String, weight: Double)],
                             rarities: [String: TasteArtistRarity]) -> (score: Int, rated: Int)? {
        var sum = 0.0, totalWeight = 0.0, rated = 0
        for (name, weight) in artistWeights {
            guard let r = rarities[name], weight > 0 else { continue }
            sum += TasteRarity.weight(for: r.tier) * weight
            totalWeight += weight
            rated += 1
        }
        guard rated >= minimumRatedArtists, totalWeight > 0 else { return nil }
        return (Int((sum / totalWeight * 100).rounded()), rated)
    }

    /// Artists ranked by weight, case-insensitively merged.
    static func rankedArtists(_ weights: [String: Double]) -> [(name: String, weight: Double)] {
        weights.map { ($0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .map { (name: $0.0, weight: $0.1) }
    }
}

// MARK: - Flow model (drives the loading screen)

@MainActor
final class TasteProfileFlowModel: ObservableObject {
    enum Stage: Int, CaseIterable, Identifiable {
        case connected, artists, songs, genres, rarity, deepest
        var id: Int { rawValue }

        /// Share of the progress ring (prototype timing 5/16/20/26/15/11).
        var weight: Double {
            switch self {
            case .connected: return 5
            case .artists: return 16
            case .songs: return 20
            case .genres: return 26
            case .rarity: return 15
            case .deepest: return 11
            }
        }
    }

    enum LineState: Equatable { case wait, run, done }

    /// One line of the "Digging through your library" list. Every line is
    /// listed up front (waiting), runs, then lands with its real count.
    struct StageLine: Identifiable, Equatable {
        let stage: Stage
        var text: String
        /// Real result as shown ("1,284", "72/100"); nil = no count.
        var count: String?
        /// The same number for the count-up; `outOf100` appends "/100".
        var value: Double?
        var outOf100 = false
        var state: LineState
        var done: Bool { state == .done }
        var id: Int { stage.rawValue }
    }

    @Published private(set) var lines: [StageLine] = []
    @Published private(set) var progress: Double = 0
    /// Genre pills under the list, and how many of them are lit.
    @Published private(set) var cloudGenres: [String] = []
    @Published private(set) var filledCount: Int = 0
    /// Known once the library is read: fewer than 10 songs.
    @Published private(set) var isEmptyLibrary = false
    @Published private(set) var isSlow = false
    @Published private(set) var isFinished = false
    @Published private(set) var profile: TasteProfile?
    /// Real runs animate counts as they land; the DEBUG parity clock
    /// drives them frame by frame like the prototype.
    private(set) var animatesCounts = true

    /// Each line stays at least this long, even when the work is instant.
    var minimumDwell: Duration = .milliseconds(600)
    /// After this long on one stage: "Big library. Still reading…".
    var slowAfter: TimeInterval = 12
    /// Hard cap for the whole sequence; past it we show what we have and
    /// let the library read finish in the background.
    var hardCap: TimeInterval = 45

    private var hasStarted = false
    private var completedWeight: Double = 0
    private let totalWeight = Stage.allCases.map(\.weight).reduce(0, +)

    init() {}

    /// Fixed state (previews and the DEBUG parity fixtures).
    init(lines: [StageLine], progress: Double, cloudGenres: [String], filledCount: Int,
         isEmptyLibrary: Bool = false, profile: TasteProfile? = nil, isFinished: Bool = false) {
        self.lines = lines
        self.progress = progress
        self.cloudGenres = cloudGenres
        self.filledCount = filledCount
        self.isEmptyLibrary = isEmptyLibrary
        self.profile = profile
        self.isFinished = isFinished
        self.hasStarted = true
    }

    /// Sets every published field at once (used by the DEBUG parity clock).
    func apply(lines: [StageLine], progress: Double, cloudGenres: [String], filledCount: Int,
               isEmptyLibrary: Bool, profile: TasteProfile?, isFinished: Bool) {
        hasStarted = true
        animatesCounts = false
        if self.lines != lines { self.lines = lines }
        if self.progress != progress { self.progress = progress }
        if self.cloudGenres != cloudGenres { self.cloudGenres = cloudGenres }
        if self.filledCount != filledCount { self.filledCount = filledCount }
        if self.isEmptyLibrary != isEmptyLibrary { self.isEmptyLibrary = isEmptyLibrary }
        if self.profile != profile { self.profile = profile }
        if self.isFinished != isFinished { self.isFinished = isFinished }
    }

    static func connectedText(_ sources: [MusicSource]) -> String {
        "Connected to " + (sources.isEmpty ? "your music" : sources.map(\.displayName).joined(separator: " and "))
    }

    func run(sources: [MusicSource],
             spotifyToken: String?,
             analyzer: AIProfileAnalyzer,
             spotifyAPI: SpotifyAPIService,
             appleMusic: AppleMusicService,
             rarityProvider: TasteRarityProvider? = nil) async {
        guard !hasStarted else { return }
        let rarityProvider = rarityProvider ?? TasteRarity.makeDefaultProvider()
        hasStarted = true
        let started = Date()
        let capDeadline = started.addingTimeInterval(hardCap)
        let usesSpotify = sources.contains(.spotify) && spotifyToken != nil
        let usesApple = sources.contains(.appleMusic)
        let appleOnly = usesApple && !usesSpotify

        // Every line is listed up front, like the prototype.
        lines = [
            StageLine(stage: .connected, text: Self.connectedText(sources), state: .wait),
            StageLine(stage: .artists, text: appleOnly ? "Finding the artists you play most" : "Pulling in your top artists", state: .wait),
            StageLine(stage: .songs, text: appleOnly ? "Reading your library" : "Reading your saved songs", state: .wait),
            StageLine(stage: .genres, text: "Sorting your genres", state: .wait),
            StageLine(stage: .rarity, text: "Checking how rare it all is", state: .wait),
            StageLine(stage: .deepest, text: "Finding your deepest cut", state: .wait),
        ]

        // 1 · Connected
        await stage(.connected, Self.connectedText(sources)) { nil }

        // 2 · Artists
        var topArtists: [SpotifyArtist] = []
        var applePlays: [AppleLibraryPlayStat] = []
        var artistWeights: [String: Double] = [:]
        var displayName: [String: String] = [:]   // lowercased → as shown
        func addArtist(_ name: String, _ weight: Double) {
            let key = name.lowercased()
            displayName[key] = displayName[key] ?? name
            artistWeights[key, default: 0] += weight
        }
        await stage(.artists, appleOnly ? "Finding the artists you play most" : "Pulling in your top artists") {
            if usesSpotify, let token = spotifyToken {
                topArtists = (try? await spotifyAPI.getTopArtists(token: token, limit: 50)) ?? []
                for (i, a) in topArtists.enumerated() { addArtist(a.name, Double(50 - i)) }
            }
            if usesApple {
                applePlays = (try? await appleMusic.fetchLibraryPlayStats()) ?? []
                for s in applePlays where s.artistName != "Unknown Artist" { addArtist(s.artistName, 1 + Double(s.playCount)) }
            }
            return artistWeights.isEmpty ? nil : artistWeights.count
        }

        // 3 · Songs (the app's own library analysis; real progress)
        await stage(.songs, appleOnly ? "Reading your library" : "Reading your saved songs") {
            if !analyzer.isAnalyzing {
                Task { await analyzer.analyzeAllConnectedSources(spotifyToken: spotifyToken) }
                // Let it flip `isAnalyzing` before polling.
                try? await Task.sleep(for: .milliseconds(100))
            }
            while analyzer.isAnalyzing && Date() < capDeadline && !Task.isCancelled {
                self.progress = (self.completedWeight + Stage.songs.weight * min(analyzer.analysisProgress, 1)) / self.totalWeight
                try? await Task.sleep(for: .milliseconds(150))
            }
            let count = max(analyzer.libraryTracks.count, applePlays.count)
            return count
        }
        let library = analyzer.libraryTracks
        let librarySize = max(library.count, applePlays.count)

        var profile = TasteProfile(librarySize: librarySize, sources: sources, generatedAt: Date())
        if profile.isEmptyLibrary {
            // Prototype's empty variant: three lines, "Looking around…".
            withAnimation(.easeInOut(duration: 0.3)) {
                isEmptyLibrary = true
                lines.removeAll { $0.stage.rawValue > Stage.songs.rawValue }
            }
        }

        // 4 · Genres
        if !profile.isEmptyLibrary {
        await stage(.genres, "Sorting your genres") {
            var labels: [String: Double] = [:]
            for t in library where t.source == .spotify {
                for g in t.genreNames { labels[g, default: 0] += 1 }
            }
            if labels.isEmpty {
                // Saved songs not read yet: fall back to top-artist genres.
                for (i, a) in topArtists.enumerated() {
                    for g in a.genres ?? [] { labels[g, default: 0] += Double(50 - i) }
                }
            }
            for s in applePlays {
                for g in s.genreNames { labels[g, default: 0] += 1 + Double(s.playCount) }
            }
            profile.topGenres = TasteProfileBuilder.genreShares(weightedLabels: labels)
            for share in profile.topGenres.prefix(10) {
                self.cloudGenres.append(share.genre)
                self.filledCount = self.cloudGenres.count
                try? await Task.sleep(for: .milliseconds(120))
            }
            return nil
        }
        }

        let ranked = TasteProfileBuilder.rankedArtists(artistWeights)
        var rarities: [String: TasteArtistRarity] = [:]
        if !profile.isEmptyLibrary && !ranked.isEmpty {
            // 5 · Rarity (Last.fm / hybrid — never Spotify popularity)
            await stage(.rarity, "Checking how rare it all is") {
                let names = ranked.prefix(25).map { displayName[$0.name] ?? $0.name }
                let deadline = min(Date().addingTimeInterval(8), capDeadline)
                let byName = await rarityProvider.rarities(forArtists: names, deadline: deadline)
                for (name, r) in byName { rarities[name.lowercased()] = r }
                if let result = TasteProfileBuilder.profileScore(artistWeights: ranked, rarities: rarities) {
                    profile.rarityScore = result.score
                    profile.ratedArtistCount = result.rated
                    return result.score
                }
                return nil
            }

            // 6 · Deepest cut
            if rarities.isEmpty {
                lines.removeAll { $0.stage == .deepest }
            } else {
                await stage(.deepest, "Finding your deepest cut") {
                    profile.deepestCut = Self.deepestCut(library: library, applePlays: applePlays, rarities: rarities)
                    return nil
                }
            }
        }

        if ranked.isEmpty || profile.isEmptyLibrary {
            lines.removeAll { $0.stage == .rarity || $0.stage == .deepest }
        }

        // Signature artists: Spotify only (no top-artists list for Apple).
        if usesSpotify {
            profile.signatureArtists = topArtists.prefix(3).map { a in
                let key = a.name.lowercased()
                let saved = library.filter { $0.artistName.lowercased() == key }.count
                return .init(name: a.name, imageURL: a.images?.first?.url, savedSongs: saved)
            }
        }

        profile.generatedAt = Date()
        profile.save()
        self.profile = profile
        self.progress = 1
        isFinished = true
    }

    static func deepestCut(library: [LibraryTrack],
                           applePlays: [AppleLibraryPlayStat],
                           rarities: [String: TasteArtistRarity]) -> TasteProfile.DeepCut? {
        var best: TasteProfile.DeepCut?
        func consider(_ cut: TasteProfile.DeepCut) {
            guard let current = best else { best = cut; return }
            if cut.rarityScore > current.rarityScore
                || (cut.rarityScore == current.rarityScore && (cut.userPlayCount ?? 0) > (current.userPlayCount ?? 0)) {
                best = cut
            }
        }
        for s in applePlays {
            guard let r = rarities[s.artistName.lowercased()] else { continue }
            consider(.init(title: s.title, artistName: s.artistName, artworkURL: nil, appleArtwork: s.artwork,
                           artistListeners: r.listeners, userPlayCount: s.playCount > 0 ? s.playCount : nil,
                           rarityScore: r.score))
        }
        for t in library where t.source == .spotify {
            guard let r = rarities[t.artistName.lowercased()] else { continue }
            consider(.init(title: t.title, artistName: t.artistName, artworkURL: t.artworkURL, appleArtwork: nil,
                           artistListeners: r.listeners, userPlayCount: nil, rarityScore: r.score))
        }
        return best
    }

    // MARK: - Stage runner

    private func stage(_ stage: Stage, _ text: String, work: () async -> Int?) async {
        if let i = lines.firstIndex(where: { $0.stage == stage }) {
            lines[i].text = text
            lines[i].state = .run
        } else {
            lines.append(StageLine(stage: stage, text: text, state: .run))
        }
        isSlow = false
        let began = ContinuousClock.now
        let slowWatch = Task { [slowAfter] in
            try? await Task.sleep(for: .seconds(slowAfter))
            if !Task.isCancelled { self.isSlow = true }
        }
        let value = await work()
        slowWatch.cancel()
        isSlow = false
        let elapsed = ContinuousClock.now - began
        if elapsed < minimumDwell { try? await Task.sleep(for: minimumDwell - elapsed) }
        if let i = lines.firstIndex(where: { $0.stage == stage }) {
            let outOf100 = stage == .rarity
            lines[i].value = value.map(Double.init)
            lines[i].outOf100 = outOf100
            lines[i].count = value.map { outOf100 ? "\($0)/100" : $0.formatted() }
            lines[i].state = .done
        }
        completedWeight += stage.weight
        progress = completedWeight / totalWeight
    }

}
