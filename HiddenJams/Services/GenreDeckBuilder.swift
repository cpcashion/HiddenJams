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
    /// Never served: artists (Spotify artist ids) already shown this Discover
    /// session. A track is out if ANY of its credited artists is in here.
    var excludedArtistIds: Set<String> = []
    /// Never served: songs already shown this session, by normalized
    /// artist name + title (catches the same song under another track id).
    var excludedSongKeys: Set<String> = []
    /// Served in an earlier Discover session (persisted history): never
    /// served again. A short deck beats a repeat.
    var isTrackSeen: (String) -> Bool = { _ in false }
    /// Artists served in an earlier session: never served again. A track is
    /// out if ANY of its credited artists has been served.
    var isArtistSeen: (String) -> Bool = { _ in false }
    /// How many search waves to run at most while fresh in-slider tracks are
    /// still short of the target. Each wave reads new query/offset pages and
    /// the next page of searches that are still turning up new music.
    var maxSearchWaves = 5
    /// Genres the user excluded in settings.
    var userExcludedGenres: [String] = []
    var target = 50
    /// One track per artist per deck, so an artist can never play twice
    /// (or back to back). Counted over every credited artist.
    var maxTracksPerArtist = 1
    var timeBudget: TimeInterval = 9
}

struct GenreDeckResult {
    var tracks: [SpotifyTrack] = []
    /// Deck tracks added above the slider's limits to reach the target (never repeats).
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
        let artistKey: String
        /// Every credited artist's Spotify id (main artist first).
        let artistIds: [String]
        /// Distance from the slider's target popularity (plus a little jitter).
        let closeness: Double

        /// Slider compliance first, then how close the track
        /// is to the slider's target popularity (in 10-point buckets), then
        /// genre exactness. This lets the popularity slider actually control
        /// the deck: at max it surfaces popular tracks, at min the obscure
        /// ones — instead of genre-exactness always winning.
        var sortKey: [Int] {
            [level, Int(closeness / 10), tier]
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
        /// Next pages of searches that turned up new, verified music.
        var continuations: [PlannedPage] = []
        /// Spotify's page size as observed (50, or 10 on newer app tiers).
        var observedPageSize = 50

        // 1. Search in waves until every genre has enough fresh, in-slider
        //    tracks (by distinct artist) or the search budget runs out. Every
        //    wave draws new random offsets and query slices, so each Discover
        //    tap reads a different part of Spotify's pool.
        for wave in 0..<max(1, request.maxSearchWaves) {
            var focus = Set(matcher.families.indices)
            var broaden = Set<Int>()
            if wave == 0 {
                await onProgress?("Searching for music…")
            } else {
                var strongArtists: [Int: Set<String>] = [:]
                var exactArtists: [Int: Set<String>] = [:]
                for candidate in candidates.values where candidate.tier == 0 {
                    exactArtists[candidate.family, default: []].insert(candidate.artistKey)
                    if candidate.level == 0 { strongArtists[candidate.family, default: []].insert(candidate.artistKey) }
                }
                focus = Set(matcher.families.indices.filter { strongArtists[$0, default: []].count < share + 3 })
                broaden = Set(matcher.families.indices.filter { exactArtists[$0, default: []].count < share })
                guard !focus.isEmpty, Date() < searchDeadline.addingTimeInterval(-0.5) else { break }
                await onProgress?("Finding hidden gems…")
            }

            // Smaller Spotify pages (10) need more requests for the same pool.
            let pageBoost = observedPageSize < 50 ? 2 : 1
            let basePages = (wave == 0 ? Self.firstWavePages(familyCount: matcher.families.count) : 12) * pageBoost
            let follow = continuations.filter { focus.contains($0.family) && !fetchedPages.contains($0.key) }
            continuations = []
            let fresh = Self.searchPlan(
                families: matcher.families,
                slider: slider,
                pages: max(0, basePages - follow.count),
                only: focus,
                broaden: broaden,
                skipping: fetchedPages.union(follow.map(\.key))
            )
            let plan = Array((follow + fresh).prefix(max(basePages, follow.count)))
            guard !plan.isEmpty else { break }
            fetchedPages.formUnion(plan.map(\.key))

            let searched = await search(plan, deadline: searchDeadline)
            if let size = searched.pageSize { observedPageSize = size }
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
            var acceptedPerPage: [String: Int] = [:]
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
                    let songKey = Self.songKey(for: candidate.track)
                    guard !titleKeys.contains(titleKey), !titleKeys.contains(songKey) else {
                        stats["duplicate", default: 0] += 1
                        continue
                    }
                    titleKeys.insert(titleKey)
                    titleKeys.insert(songKey)
                    candidates[id] = candidate
                    acceptedPerPage[entry.page.key, default: 0] += 1
                }
            }

            // 4. Pagination: searches that are still yielding new music get
            //    their next page in the following wave.
            for page in searched.pages where acceptedPerPage[page.page.key, default: 0] > 0 {
                let next = page.page.offset + page.limit
                guard next < min(page.total, 1000) else { continue }
                continuations.append(PlannedPage(query: page.page.query, offset: next,
                                                 family: page.page.family, depth: page.page.depth))
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
        // so the deck has its full count -- but never an artist the deck
        // already has (this fill used to count artists from scratch, which
        // let a second track by a deck artist in).
        if deck.count < request.target {
            let inDeck = Set(deck.map { $0.track.id })
            deck += Self.selectDeck(
                pool.filter { missing.contains($0.track.id) && !inDeck.contains($0.track.id) },
                count: request.target - deck.count,
                maxPerArtist: perArtist,
                familyOrder: familyOrder,
                alreadyChosen: deck
            )
        }

        result.tracks = deck.map { $0.track.withPreview(previews[$0.track.id] ?? $0.track.previewUrl) }
        result.playableCount = result.tracks.filter { !($0.previewUrl ?? "").isEmpty }.count
        result.relaxedCount = deck.filter { $0.level > 0 || $0.tier > 0 }.count
        stats["deck"] = result.tracks.count
        stats["playable"] = result.playableCount
        stats["relaxed"] = result.relaxedCount
        stats["preview_missing"] = missing.count
        stats["elapsed_ms"] = Int(Date().timeIntervalSince(started) * 1000)
        result.stats = stats
        return result
    }

    // MARK: - Search

    private struct FetchedPage {
        let page: PlannedPage
        let limit: Int
        let total: Int
    }

    private struct SearchOutcome {
        var found: [(track: SpotifyTrack, family: Int, page: PlannedPage)] = []
        var pages: [FetchedPage] = []
        var ok = 0
        var failed = 0
        var pageSize: Int?
    }

    private func search(
        _ plan: [PlannedPage],
        deadline: Date
    ) async -> SearchOutcome {
        var outcome = SearchOutcome()
        var retries: [PlannedPage] = []

        let pages = await Self.concurrentMap(plan, limit: 8, deadline: deadline) { [catalog] page -> GenreDeckSearchPage? in
            await catalog.searchTracks(query: page.query, offset: page.offset)
        }
        for (page, response) in zip(plan, pages) {
            guard let response else { outcome.failed += 1; continue }
            outcome.ok += 1
            outcome.pageSize = response.limit
            if response.tracks.isEmpty, response.total > 0, page.offset > 0 {
                // Landed past the end of a short result list: aim inside it.
                let maxOffset = max(0, min(response.total, 1000) - response.limit)
                retries.append(PlannedPage(
                    query: page.query,
                    offset: Int((Double(maxOffset) * page.depth).rounded()),
                    family: page.family,
                    depth: page.depth
                ))
                continue
            }
            outcome.pages.append(FetchedPage(page: page, limit: response.limit, total: response.total))
            outcome.found += response.tracks.map { (track: $0, family: page.family, page: page) }
        }

        if !retries.isEmpty {
            let again = await Self.concurrentMap(retries, limit: 8, deadline: deadline) { [catalog] page -> GenreDeckSearchPage? in
                await catalog.searchTracks(query: page.query, offset: page.offset)
            }
            for (page, response) in zip(retries, again) {
                guard let response else { outcome.failed += 1; continue }
                outcome.ok += 1
                outcome.pages.append(FetchedPage(page: page, limit: response.limit, total: response.total))
                outcome.found += response.tracks.map { (track: $0, family: page.family, page: page) }
            }
        }
        return outcome
    }

    /// 0 at the slider's Deep end, 1 at Hot.
    static func sliderPosition(popularityCeiling: Int) -> Double {
        min(1, max(0, Double(popularityCeiling - 15) / 75))
    }

    static func firstWavePages(familyCount: Int) -> Int {
        min(18, max(12, 8 + 3 * familyCount))
    }

    /// How far each search page may stray from the slider's depth, so every
    /// Discover tap reads a different slice of Spotify's results.
    static let depthSpread = 0.25

    /// Which searches to run: each family's Spotify genres, plain and in
    /// random release-year slices (each slice has its own 1,000-result
    /// window, so the reachable pool is many times larger than one query's),
    /// each read at a random offset around the depth the slider sets (Deep:
    /// the obscure tail, Hot: the popular head), shared out across families
    /// in turn. Nothing here is fixed or cached: two calls with the same
    /// input plan different pages.
    static func searchPlan(
        families: [GenreMatcher.Family],
        slider: Double,
        pages: Int,
        only: Set<Int>,
        broaden: Set<Int>,
        skipping: Set<String>
    ) -> [PlannedPage] {
        guard pages > 0 else { return [] }
        let year = Calendar.current.component(.year, from: Date())
        // Obscure end: any era. Popular end: mostly recent releases.
        let yearSpan = slider < 0.6 ? 40 : 10
        let center = 0.92 - 0.9 * slider
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
            var queries: [String] = []
            for genre in genres {
                let base = "genre:\"\(genre)\""
                queries.append(base)
                let single = year - Int.random(in: 0...yearSpan)
                queries.append("\(base) year:\(single)")
                let from = year - Int.random(in: 1...yearSpan)
                let to = min(year, from + Int.random(in: 1...4))
                queries.append("\(base) year:\(from)-\(to)")
            }
            queries.shuffle()
            var used = Set<String>()
            perFamily.append(queries.compactMap { query -> PlannedPage? in
                // A couple of tries to find an offset not already read.
                for _ in 0..<3 {
                    let depth = min(1, max(0, center + Double.random(in: -depthSpread...depthSpread)))
                    let offset = Int((depth * 950).rounded())
                    let page = PlannedPage(query: query, offset: offset, family: index, depth: depth)
                    if !skipping.contains(page.key), used.insert(page.key).inserted { return page }
                }
                return nil
            })
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
        if track.artists.contains(where: { artist in artist.spotifyId.map { request.excludedArtistIds.contains($0) } ?? false }) {
            return .rejected("session_artist")
        }
        if request.excludedSongKeys.contains(Self.songKey(for: track)) { return .rejected("session_song") }
        // Earlier sessions (persisted history) are hard exclusions too: a
        // served song or artist never comes back, even when the pool is thin.
        if request.isTrackSeen(trackId) { return .rejected("history_track") }
        if track.artists.contains(where: { artist in artist.spotifyId.map(request.isArtistSeen) ?? false }) {
            return .rejected("history_artist")
        }
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
            artistKey: artistId,
            artistIds: Self.artistIds(of: track),
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
    /// share, at most `maxPerArtist` per artist (counted over every credited
    /// artist, including `alreadyChosen`). The artist limit is never relaxed:
    /// a short deck beats a repeated artist. Ordered most-fitting first,
    /// alternating between genres.
    private static func selectDeck(
        _ pool: [Candidate],
        count: Int,
        maxPerArtist: Int,
        familyOrder: [Int],
        alreadyChosen: [Candidate] = []
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
        for earlier in alreadyChosen {
            for id in earlier.artistIds { perArtistCount[id, default: 0] += 1 }
        }
        func artistRoom(_ candidate: Candidate) -> Bool {
            candidate.artistIds.allSatisfy { perArtistCount[$0, default: 0] < max(maxPerArtist, 1) }
        }
        func take(_ candidate: Candidate) {
            chosen.append(candidate)
            chosenIds.insert(candidate.track.id)
            perFamily[candidate.family, default: 0] += 1
            for id in candidate.artistIds { perArtistCount[id, default: 0] += 1 }
        }

        for candidate in ordered where chosen.count < count {
            if perFamily[candidate.family, default: 0] < quota, artistRoom(candidate) {
                take(candidate)
            }
        }
        for candidate in ordered where chosen.count < count && !chosenIds.contains(candidate.track.id) {
            if artistRoom(candidate) {
                take(candidate)
            }
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

    // MARK: - Repeat keys

    /// Every credited artist's Spotify id, main artist first.
    static func artistIds(of track: SpotifyTrack) -> [String] {
        var seen = Set<String>()
        return track.artists.compactMap { $0.spotifyId }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The same song regardless of Spotify track id: normalized main artist
    /// name + core title ("The Band - Song (Radio Edit)" == "band|song").
    static func songKey(for track: SpotifyTrack) -> String {
        var artist = (track.artists.first?.name ?? "").lowercased()
        if !artist.allSatisfy(\.isASCII) {
            artist = artist.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        }
        var words = artist.replacingOccurrences(of: "&", with: " and ")
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
        if words.first == "the" { words.removeFirst() }
        return "song:" + words.joined() + "|" + DeezerPreviewService.coreTitle(track.name)
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

/// Everything Discover has ever served, so nothing repeats: no track (by
/// Spotify id or by artist + title) and no artist (by Spotify id, any
/// credited artist) comes back, however many times Discover is tapped and
/// across app launches. Saved to UserDefaults after every deck (`save`) and
/// read back before the next one (`load`); earlier builds only kept this in
/// memory, so every relaunch started from an empty memory and replayed the
/// same songs.
struct DiscoverySessionMemory: Codable, Equatable {
    private(set) var trackIds = Set<String>()
    private(set) var songKeys = Set<String>()
    private(set) var artistIds = Set<String>()

    static let storageKey = "discover_served_memory_v1"

    /// The saved memory, or an empty one on first run (or unreadable data).
    static func load(from defaults: UserDefaults = .standard) -> DiscoverySessionMemory {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(DiscoverySessionMemory.self, from: data) else {
            return DiscoverySessionMemory()
        }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Folds in ids served before this memory existed (DiscoveryHistoryManager),
    /// so tracks and artists from older builds don't come back either.
    mutating func absorb(trackIds tracks: Set<String>, artistIds artists: Set<String>) {
        trackIds.formUnion(tracks)
        artistIds.formUnion(artists)
    }

    /// Adds the session's exclusions to a deck request.
    func apply(to request: inout GenreDeckRequest) {
        request.excludedTrackIds.formUnion(trackIds)
        request.excludedSongKeys.formUnion(songKeys)
        request.excludedArtistIds.formUnion(artistIds)
    }

    /// Final gate: keeps only tracks that repeat nothing already served
    /// (this session, earlier sessions, or earlier in `tracks`), and records
    /// the ones it keeps.
    mutating func admit(_ tracks: [SpotifyTrack]) -> [SpotifyTrack] {
        var kept: [SpotifyTrack] = []
        for track in tracks {
            let artists = GenreDeckBuilder.artistIds(of: track)
            let songKey = GenreDeckBuilder.songKey(for: track)
            guard !trackIds.contains(track.id),
                  !songKeys.contains(songKey),
                  !artists.contains(where: { artistIds.contains($0) }) else { continue }
            trackIds.insert(track.id)
            songKeys.insert(songKey)
            artistIds.formUnion(artists)
            kept.append(track)
        }
        return kept
    }
}
