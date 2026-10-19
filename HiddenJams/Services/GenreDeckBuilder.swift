//
//  GenreDeckBuilder.swift
//  HiddenJams
//
//  Builds the Discover deck for Spotify users:
//
//   - Every track is verified against the genres the user picked, using the
//     credited artist's Spotify genres (GenreMatcher). Nothing gets in on a
//     search result alone.
//   - The slider decides where to look: at Deep it reads the obscure tail of
//     Spotify's results first, at Hot the popular head.
//   - The deck always aims for `target` tracks (50). When there aren't enough
//     within the slider's limits, popularity is raised step by step in the
//     background, and those tracks go after the ones that fit.
//   - Previews are resolved up front (Deezer, by ISRC), so the deck is made of
//     tracks that can actually play.
//   - Searches, artist lookups and previews all run in parallel against a
//     time budget (about 9 seconds).
//

import Foundation

struct GenreDeckRequest {
    /// Genres to draw from: the user's picks, or their top profile genres.
    var genres: [String]
    /// True when the user picked the genres themselves.
    var userSelected = true
    /// Slider limits: track popularity (15...90) and artist followers.
    var popularityCeiling: Int
    var followerCeiling: Int
    /// Never served: the user's library and tracks already shown this session.
    var excludedTrackIds: Set<String> = []
    /// Served recently: only repeated when nothing new is left.
    var isTrackSeen: (String) -> Bool = { _ in false }
    /// Artists served recently: ranked after new artists.
    var isArtistSeen: (String) -> Bool = { _ in false }
    /// Genres the user excluded in settings.
    var userExcludedGenres: [String] = []
    var target = 50
    var maxTracksPerArtist = 2
    var timeBudget: TimeInterval = 9
}

struct GenreDeckResult {
    var tracks: [SpotifyTrack] = []
    /// Deck tracks added above the slider's limits (or repeats) to reach the target.
    var relaxedCount = 0
    /// Deck tracks with a preview that's ready to play.
    var playableCount = 0
    var stats: [String: Int] = [:]
}

struct GenreDeckSearchPage {
    var tracks: [SpotifyTrack]
    var total: Int
    var limit: Int
}

/// Where the deck builder gets its data. The live implementation is
/// SpotifyGenreDeckCatalog; tests use a stub.
protocol GenreDeckCatalog {
    /// One page of Spotify track search results, or nil if the request failed.
    func searchTracks(query: String, offset: Int) async -> GenreDeckSearchPage?
    /// Full artist objects (genres, followers, popularity) for up to 50 ids.
    func artists(ids: [String]) async -> [SpotifyArtist]
    /// A playable 30-second preview of exactly this track, or nil.
    func previewURL(for track: SpotifyTrack) async -> String?
}

final class GenreDeckBuilder {
    private let catalog: any GenreDeckCatalog
    /// Progress messages for the loading screen.
    var onProgress: ((String) async -> Void)?
    private var artistCache: [String: SpotifyArtist] = [:]
    private var labelCache: [String: [[String]]] = [:]

    init(catalog: any GenreDeckCatalog) {
        self.catalog = catalog
    }

    private struct Candidate {
        let track: SpotifyTrack
        let family: Int
        /// 0 = the selected genre itself, 1 = only its parent family.
        let tier: Int
        /// 0 = within the slider's limits; +1 per step of relaxation.
        let level: Int
        let seenTrack: Bool
        let seenArtist: Bool
        let artistKey: String
        /// Distance from the slider's target popularity (plus a little jitter).
        let closeness: Double

        /// Slider compliance first, then freshness, then how close the track
        /// is to the slider's target popularity (in 10-point buckets), then
        /// genre exactness. This lets the popularity slider actually control
        /// the deck: at max it surfaces popular tracks, at min the obscure
        /// ones — instead of genre-exactness always winning.
        var sortKey: [Int] {
            [level, seenTrack ? 1 : 0, seenArtist ? 1 : 0, Int(closeness / 10), tier]
        }
    }

    struct PlannedPage {
        let query: String
        let offset: Int
        let family: Int
        /// 0 = head of the results (popular), 1 = deepest reachable (obscure).
        let depth: Double
        var key: String { "\(query)@\(offset)" }
    }

    private enum Verdict {
        case accepted(Candidate)
        case rejected(String)
    }

    private enum PreviewLookup {
        case found(String)
        case missing
    }

    // MARK: - Build

    func build(_ request: GenreDeckRequest) async -> GenreDeckResult {
        let started = Date()
        let deadline = started.addingTimeInterval(request.timeBudget)
        let searchDeadline = started.addingTimeInterval(request.timeBudget * 0.45)
        var result = GenreDeckResult()
        var stats: [String: Int] = [:]

        let matcher = GenreMatcher(selections: request.genres, userExcluded: request.userExcludedGenres)
        guard !matcher.families.isEmpty, request.target > 0 else { return result }

        let slider = Self.sliderPosition(popularityCeiling: request.popularityCeiling)
        let targetPopularity = Double(max(0, request.popularityCeiling - 15))
        let share = Int((Double(request.target) / Double(matcher.families.count)).rounded(.up))

        var candidates: [String: Candidate] = [:]
        var titleKeys = Set<String>()
        var fetchedPages = Set<String>()

        // 1. Search: one wave, plus a second for genres that came up short.
        for wave in 0..<2 {
            var focus = Set(matcher.families.indices)
            var broaden = Set<Int>()
            if wave == 0 {
                await onProgress?("Searching for music…")
            } else {
                var strong: [Int: Int] = [:]
                var exact: [Int: Int] = [:]
                for candidate in candidates.values where candidate.tier == 0 && !candidate.seenTrack {
                    exact[candidate.family, default: 0] += 1
                    if candidate.level == 0 { strong[candidate.family, default: 0] += 1 }
                }
                focus = Set(matcher.families.indices.filter { strong[$0, default: 0] < share + 3 })
                broaden = Set(matcher.families.indices.filter { exact[$0, default: 0] < share })
                guard !focus.isEmpty, Date() < searchDeadline.addingTimeInterval(-1) else { break }
                await onProgress?("Finding hidden gems…")
            }

            let plan = Self.searchPlan(
                families: matcher.families,
                slider: slider,
                pages: wave == 0 ? Self.firstWavePages(familyCount: matcher.families.count) : 12,
                only: focus,
                broaden: broaden,
                skipping: fetchedPages
            )
            guard !plan.isEmpty else { break }
            fetchedPages.formUnion(plan.map(\.key))

            let searched = await search(plan, deadline: searchDeadline)
            stats["pages_ok", default: 0] += searched.ok
            stats["pages_failed", default: 0] += searched.failed
            stats["found", default: 0] += searched.found.count

            // 2. Artist details: genres, followers. Featured artists only for
            //    tracks whose main artist has no genres listed.
            let hydrateDeadline = searchDeadline.addingTimeInterval(1)
            await hydrate(searched.found.compactMap { $0.track.artists.first?.spotifyId }, deadline: hydrateDeadline)
            let featured = searched.found.flatMap { entry -> [String] in
                guard let main = entry.track.artists.first?.spotifyId,
                      (artistCache[main]?.genres ?? []).isEmpty else { return [] }
                return entry.track.artists.dropFirst().compactMap { $0.spotifyId }
            }
            await hydrate(featured, deadline: hydrateDeadline)

            // 3. Verify every track.
            for entry in searched.found {
                guard let id = entry.track.spotifyId, candidates[id] == nil else {
                    stats["duplicate", default: 0] += 1
                    continue
                }
                switch verify(entry.track, source: entry.family, request: request,
                              matcher: matcher, targetPopularity: targetPopularity) {
                case .rejected(let reason):
                    stats[reason, default: 0] += 1
                case .accepted(let candidate):
                    let titleKey = candidate.artistKey + "|" + DeezerPreviewService.coreTitle(candidate.track.name)
                    guard titleKeys.insert(titleKey).inserted else {
                        stats["duplicate", default: 0] += 1
                        continue
                    }
                    candidates[id] = candidate
                }
            }
        }

        let pool = Array(candidates.values)
        stats["verified"] = pool.count
        guard !pool.isEmpty else {
            stats["elapsed_ms"] = Int(Date().timeIntervalSince(started) * 1000)
            result.stats = stats
            return result
        }

        // 4. Pick the deck and make sure it plays. Tracks without a preview
        //    are swapped for the next best ones.
        await onProgress?("Developing your playlist…")
        let familyOrder = Array(matcher.families.indices).shuffled()
        let perArtist = request.maxTracksPerArtist
        var previews: [String: String] = [:]
        var missing = Set<String>()
        var deck: [Candidate] = []
        for _ in 0..<4 {
            let usable = pool.filter { !missing.contains($0.track.id) }
            deck = Self.selectDeck(usable, count: request.target, maxPerArtist: perArtist, familyOrder: familyOrder)
            var lookups = deck.filter { previews[$0.track.id] == nil }
            guard !lookups.isEmpty, Date() < deadline else { break }
            // A few spares, so a handful of misses don't cost another round.
            let planned = Set(deck.map { $0.track.id })
            lookups += Self.selectDeck(
                usable.filter { !planned.contains($0.track.id) && previews[$0.track.id] == nil },
                count: max(4, lookups.count / 5),
                maxPerArtist: perArtist,
                familyOrder: familyOrder
            )
            let tracks = lookups.map(\.track)
            let outcomes = await Self.concurrentMap(tracks, limit: 10, deadline: deadline) { [catalog] track -> PreviewLookup? in
                if let url = await catalog.previewURL(for: track) { return .found(url) }
                return .missing
            }
            for (track, outcome) in zip(tracks, outcomes) {
                switch outcome {
                case .found(let url)?: previews[track.id] = url
                case .missing?: missing.insert(track.id)
                case nil: break  // not reached before the deadline
                }
            }
        }
        // Still short (tiny genre, or previews unavailable): use what's left
        // so the deck has its full count.
        if deck.count < request.target {
            let inDeck = Set(deck.map { $0.track.id })
            deck += Self.selectDeck(
                pool.filter { missing.contains($0.track.id) && !inDeck.contains($0.track.id) },
                count: request.target - deck.count,
                maxPerArtist: perArtist,
                familyOrder: familyOrder
            )
        }

        result.tracks = deck.map { $0.track.withPreview(previews[$0.track.id] ?? $0.track.previewUrl) }
        result.playableCount = result.tracks.filter { !($0.previewUrl ?? "").isEmpty }.count
        result.relaxedCount = deck.filter { $0.level > 0 || $0.tier > 0 || $0.seenTrack }.count
        stats["deck"] = result.tracks.count
        stats["playable"] = result.playableCount
        stats["relaxed"] = result.relaxedCount
        stats["preview_missing"] = missing.count
        stats["elapsed_ms"] = Int(Date().timeIntervalSince(started) * 1000)
        result.stats = stats
        return result
    }

    // MARK: - Search

    private func search(
        _ plan: [PlannedPage],
        deadline: Date
    ) async -> (found: [(track: SpotifyTrack, family: Int)], ok: Int, failed: Int) {
        var found: [(track: SpotifyTrack, family: Int)] = []
        var ok = 0
        var failed = 0
        var retries: [PlannedPage] = []

        let pages = await Self.concurrentMap(plan, limit: 8, deadline: deadline) { [catalog] page -> GenreDeckSearchPage? in
            await catalog.searchTracks(query: page.query, offset: page.offset)
        }
        for (page, response) in zip(plan, pages) {
            guard let response else { failed += 1; continue }
            ok += 1
            if response.tracks.isEmpty, response.total > 0, page.offset > 0 {
                // Landed past the end of a short result list: aim inside it.
                let maxOffset = max(0, min(response.total, 1000) - response.limit)
                retries.append(PlannedPage(
                    query: page.query,
                    offset: Int((Double(maxOffset) * page.depth).rounded()),
                    family: page.family,
                    depth: page.depth
                ))
            }
            found += response.tracks.map { (track: $0, family: page.family) }
        }

        if !retries.isEmpty {
            let again = await Self.concurrentMap(retries, limit: 8, deadline: deadline) { [catalog] page -> GenreDeckSearchPage? in
                await catalog.searchTracks(query: page.query, offset: page.offset)
            }
            for (page, response) in zip(retries, again) {
                guard let response else { failed += 1; continue }
                ok += 1
                found += response.tracks.map { (track: $0, family: page.family) }
            }
        }
        return (found, ok, failed)
    }

    /// 0 at the slider's Deep end, 1 at Hot.
    static func sliderPosition(popularityCeiling: Int) -> Double {
        min(1, max(0, Double(popularityCeiling - 15) / 75))
    }

    static func firstWavePages(familyCount: Int) -> Int {
        min(18, max(12, 8 + 3 * familyCount))
    }

    /// Which searches to run: each family's Spotify genres (plus year slices
    /// when the slider leans obscure, since each slice has its own
    /// 1,000-result window), read at a depth set by the slider, shared out
    /// across families in turn.
    static func searchPlan(
        families: [GenreMatcher.Family],
        slider: Double,
        pages: Int,
        only: Set<Int>,
        broaden: Set<Int>,
        skipping: Set<String>
    ) -> [PlannedPage] {
        let year = Calendar.current.component(.year, from: Date())
        var perFamily: [[PlannedPage]] = []
        for (index, family) in families.enumerated() {
            guard only.contains(index) else {
                perFamily.append([])
                continue
            }
            var genres = family.searches.shuffled()
            if broaden.contains(index) {
                genres += family.broaderSearches.shuffled()
            }
            var queries = genres.map { "genre:\"\($0)\"" }
            if slider < 0.6 {
                let sliced = genres.prefix(4).map { "genre:\"\($0)\" year:\(year - Int.random(in: 0...8))" }
                queries = alternate(queries, Array(sliced))
            }
            perFamily.append(queries.map { query -> PlannedPage in
                let depth = min(1, max(0, 0.92 - 0.9 * slider + Double.random(in: -0.08...0.08)))
                return PlannedPage(query: query, offset: Int((depth * 950).rounded()), family: index, depth: depth)
            }.filter { !skipping.contains($0.key) })
        }

        var plan: [PlannedPage] = []
        let order = perFamily.indices.shuffled()
        var round = 0
        while plan.count < pages {
            var added = false
            for family in order where round < perFamily[family].count && plan.count < pages {
                plan.append(perFamily[family][round])
                added = true
            }
            if !added { break }
            round += 1
        }
        return plan
    }

    private static func alternate(_ a: [String], _ b: [String]) -> [String] {
        var out: [String] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    // MARK: - Artists

    private func hydrate(_ ids: [String], deadline: Date) async {
        var seen = Set<String>()
        let missing = ids.filter { artistCache[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty else { return }
        let batches = missing.chunked(into: 50)
        let results = await Self.concurrentMap(batches, limit: 6, deadline: deadline) { [catalog] batch -> [SpotifyArtist]? in
            await catalog.artists(ids: batch)
        }
        for artist in results.compactMap({ $0 }).joined() {
            if let id = artist.spotifyId { artistCache[id] = artist }
        }
    }

    // MARK: - Verification

    private func verify(
        _ track: SpotifyTrack,
        source: Int,
        request: GenreDeckRequest,
        matcher: GenreMatcher,
        targetPopularity: Double
    ) -> Verdict {
        guard let trackId = track.spotifyId, !trackId.isEmpty else { return .rejected("no_id") }
        if request.excludedTrackIds.contains(trackId) { return .rejected("known_track") }
        if track.durationMs > 0 && track.durationMs < 45_000 { return .rejected("too_short") }
        if Self.isCompilation(track.album.name) { return .rejected("compilation") }
        guard let credited = track.artists.first, let artistId = credited.spotifyId else {
            return .rejected("no_artist")
        }
        if Self.bannedArtists.contains(credited.name) { return .rejected("banned") }

        // The main artist decides the genre. Only when Spotify lists no
        // genres for them can a featured artist vouch for the track.
        let primary = artistCache[artistId] ?? credited
        let primaryLabels = labels(primary.genres)
        var matched: (family: Int, tier: Int)?
        if !primaryLabels.isEmpty {
            guard let match = matcher.match(labels: primaryLabels, preferring: source) else {
                return .rejected("wrong_genre")
            }
            guard !matcher.isExcluded(labels: primaryLabels) else { return .rejected("excluded_genre") }
            matched = match
        } else {
            for other in track.artists.dropFirst() {
                guard let id = other.spotifyId else { continue }
                let otherLabels = labels(artistCache[id]?.genres)
                guard !otherLabels.isEmpty else { continue }
                if let match = matcher.match(labels: otherLabels, preferring: source),
                   !matcher.isExcluded(labels: otherLabels) {
                    matched = match
                    break
                }
            }
        }
        guard let match = matched else { return .rejected("unverified_genre") }

        if !matcher.families[match.family].allowsNonLatinScript,
           !(Self.isLatinScript(track.name) && Self.isLatinScript(credited.name)) {
            return .rejected("script")
        }

        var artists = track.artists
        artists[0] = primary
        return .accepted(Candidate(
            track: track.withArtists(artists),
            family: match.family,
            tier: match.tier,
            level: Self.relaxationLevel(
                popularity: track.popularity,
                followers: primary.followers?.total,
                popularityCeiling: request.popularityCeiling,
                followerCeiling: request.followerCeiling
            ),
            seenTrack: request.isTrackSeen(trackId),
            seenArtist: request.isArtistSeen(artistId),
            artistKey: artistId,
            closeness: abs(Double(track.popularity) - targetPopularity) + Double.random(in: 0..<3)
        ))
    }

    /// Canonical labels for a genre list, cached: many artists share the same
    /// genre list, and every candidate needs them.
    private func labels(_ genres: [String]?) -> [[String]] {
        guard let genres, !genres.isEmpty else { return [] }
        let key = genres.joined(separator: "\u{1F}")
        if let cached = labelCache[key] { return cached }
        let computed = genres.map(GenreMatcher.tokens).filter { !$0.isEmpty }
        labelCache[key] = computed
        return computed
    }

    /// 0 when the track fits the slider. Each step above allows +10
    /// popularity and 3x the followers.
    static func relaxationLevel(popularity: Int, followers: Int?, popularityCeiling: Int, followerCeiling: Int) -> Int {
        var level = 0
        if popularity > popularityCeiling {
            level = Int((Double(popularity - popularityCeiling) / 10).rounded(.up))
        }
        if let followers, followerCeiling > 0, followers > followerCeiling {
            var ceiling = Double(followerCeiling)
            var steps = 0
            while Double(followers) > ceiling && steps < 10 {
                ceiling *= 3
                steps += 1
            }
            level = max(level, steps)
        }
        return level
    }

    // MARK: - Deck selection

    /// Picks `count` tracks: best tiers first, each selected genre gets its
    /// share, at most `maxPerArtist` per artist (relaxed only as a last
    /// resort). Ordered most-fitting first, alternating between genres.
    private static func selectDeck(
        _ pool: [Candidate],
        count: Int,
        maxPerArtist: Int,
        familyOrder: [Int]
    ) -> [Candidate] {
        guard count > 0, !pool.isEmpty else { return [] }
        let ordered = pool.sorted { a, b in
            if a.sortKey != b.sortKey { return a.sortKey.lexicographicallyPrecedes(b.sortKey) }
            return a.closeness < b.closeness
        }
        let familyCount = Set(pool.map(\.family)).count
        let quota = Int((Double(count) / Double(max(familyCount, 1))).rounded(.up))

        var chosen: [Candidate] = []
        var chosenIds = Set<String>()
        var perFamily: [Int: Int] = [:]
        var perArtistCount: [String: Int] = [:]
        func take(_ candidate: Candidate) {
            chosen.append(candidate)
            chosenIds.insert(candidate.track.id)
            perFamily[candidate.family, default: 0] += 1
            perArtistCount[candidate.artistKey, default: 0] += 1
        }

        for candidate in ordered where chosen.count < count {
            if perFamily[candidate.family, default: 0] < quota,
               perArtistCount[candidate.artistKey, default: 0] < maxPerArtist {
                take(candidate)
            }
        }
        for candidate in ordered where chosen.count < count && !chosenIds.contains(candidate.track.id) {
            if perArtistCount[candidate.artistKey, default: 0] < maxPerArtist {
                take(candidate)
            }
        }
        for candidate in ordered where chosen.count < count && !chosenIds.contains(candidate.track.id) {
            take(candidate)
        }
        return interleave(chosen, familyOrder: familyOrder)
    }

    private static func interleave(_ deck: [Candidate], familyOrder: [Int]) -> [Candidate] {
        let groups = Dictionary(grouping: deck) { $0.sortKey }
        var out: [Candidate] = []
        for key in groups.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            let members = groups[key] ?? []
            let byFamily = Dictionary(grouping: members) { $0.family }
                .mapValues { $0.sorted { $0.closeness < $1.closeness } }
            let order = familyOrder.filter { byFamily[$0] != nil }
                + byFamily.keys.filter { !familyOrder.contains($0) }.sorted()
            var cursors: [Int: Int] = [:]
            var remaining = members.count
            while remaining > 0 {
                for family in order {
                    let list = byFamily[family] ?? []
                    let index = cursors[family, default: 0]
                    if index < list.count {
                        out.append(list[index])
                        cursors[family] = index + 1
                        remaining -= 1
                    }
                }
            }
        }
        return out
    }

    // MARK: - Concurrency

    /// Runs `transform` over `items` with at most `limit` in flight, keeping
    /// input order. Items not finished by `deadline` come back nil.
    /// The work is network-bound, so tasks stay on the main actor and simply
    /// overlap their waits; no state is shared across threads.
    static func concurrentMap<T: Sendable, R: Sendable>(
        _ items: [T],
        limit: Int,
        deadline: Date,
        _ transform: @escaping (T) async -> R?
    ) async -> [R?] {
        guard !items.isEmpty else { return [] }
        let timeout = deadline.timeIntervalSinceNow
        guard timeout > 0 else { return Array(repeating: nil, count: items.count) }
        return await withTaskGroup(of: (Int, R?).self, returning: [R?].self) { group in
            var results = [R?](repeating: nil, count: items.count)
            // Deadline timer: when it fires, stragglers are cancelled.
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return (-1, nil)
            }
            var next = 0
            var running = 0
            while next < items.count && running < max(limit, 1) {
                let index = next
                let item = items[index]
                group.addTask { @MainActor in (index, await transform(item)) }
                next += 1
                running += 1
            }
            while let (index, value) = await group.next() {
                if index < 0 {
                    group.cancelAll()
                    break
                }
                results[index] = value
                running -= 1
                if next < items.count, Date() < deadline {
                    let nextIndex = next
                    let item = items[nextIndex]
                    group.addTask { @MainActor in (nextIndex, await transform(item)) }
                    next += 1
                    running += 1
                } else if running == 0 {
                    group.cancelAll()
                    break
                }
            }
            return results
        }
    }

    // MARK: - Filters

    private static let bannedArtists: Set<String> = ["Happy Pills"]

    static func isCompilation(_ albumName: String) -> Bool {
        let lower = albumName.lowercased()
        return ["best of", "greatest hits", "compilation", "collection", "essential"]
            .contains { lower.contains($0) }
    }

    /// False when the text contains CJK, Arabic, Cyrillic, Hebrew, Thai or
    /// Hangul characters.
    static func isLatinScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3040...0x30FF).contains(value) { return false }   // Hiragana, Katakana
            if (0x4E00...0x9FFF).contains(value) { return false }   // CJK
            if (0x0600...0x06FF).contains(value) { return false }   // Arabic
            if (0x0400...0x04FF).contains(value) { return false }   // Cyrillic
            if (0x0590...0x05FF).contains(value) { return false }   // Hebrew
            if (0x0E00...0x0E7F).contains(value) { return false }   // Thai
            if (0xAC00...0xD7AF).contains(value) { return false }   // Hangul
        }
        return true
    }
}
