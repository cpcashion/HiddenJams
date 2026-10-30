//
//  ProfileStatsView.swift
//  HiddenJams
//
//  Build 78: the Profile sections the three Home stat pills open —
//  Tracks, Gems, Genres. Everything shown is real data:
//    • library numbers from the taste analysis (AIProfileAnalyzer)
//    • the current discovery deck (passed in)
//    • saves recorded by SavedGemsStore
//    • plays/saves recorded on-device by ListeningStatsStore (build 78+)
//  Nothing is estimated; empty states say when there's nothing yet.
//

import SwiftUI

/// Which Profile stats section a Home pill asked for.
enum ProfileStatFocus: String, Hashable {
    case tracks, gems, genres

    /// ScrollViewReader anchor id.
    var anchorId: String { "profile-stats-\(rawValue)" }

    /// Build 79: title of the pushed stat detail screen.
    var title: String {
        switch self {
        case .tracks: return "Tracks"
        case .gems: return "Gems"
        case .genres: return "Genres"
        }
    }

    var iconName: String {
        switch self {
        case .tracks: return "music.note.list"
        case .gems: return "sparkles"
        case .genres: return "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .tracks: return Theme.Colors.pink
        case .gems: return Theme.Colors.mint
        case .genres: return Theme.Colors.butter
        }
    }
}

struct ProfileStatsView: View {
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @ObservedObject private var stats = ListeningStatsStore.shared
    @ObservedObject private var savedGems = SavedGemsStore.shared

    /// Gems in the current discovery deck (the Home "Gems Found" number).
    let deckGemCount: Int
    /// Section to briefly highlight after a pill tap.
    let highlighted: ProfileStatFocus?
    /// Build 79: show just one section (the pushed stat detail screen,
    /// whose navigation title replaces the section header).
    var only: ProfileStatFocus? = nil

    var body: some View {
        VStack(spacing: 32) {
            if only == nil || only == .tracks {
                tracksSection
                    .modifier(StatHighlight(on: highlighted == .tracks, color: Theme.Colors.pink))
                    .id(ProfileStatFocus.tracks.anchorId)
            }
            if only == nil || only == .gems {
                gemsSection
                    .modifier(StatHighlight(on: highlighted == .gems, color: Theme.Colors.mint))
                    .id(ProfileStatFocus.gems.anchorId)
            }
            if only == nil || only == .genres {
                genresSection
                    .modifier(StatHighlight(on: highlighted == .genres, color: Theme.Colors.butter))
                    .id(ProfileStatFocus.genres.anchorId)
            }
        }
    }

    // MARK: - Tracks

    private var tracksSection: some View {
        let library = profileAnalyzer.libraryTracks
        let spotifyCount = library.filter { $0.source == .spotify }.count
        let appleCount = library.filter { $0.source == .appleMusic }.count
        let thisWeek = Set(stats.plays(since: stats.startOfWeek).map(\.trackId)).count

        return VStack(alignment: .leading, spacing: 14) {
            header("Tracks", icon: "music.note.list")

            HStack(spacing: 10) {
                tile("\(profileAnalyzer.profile.totalTracksAnalyzed)", "In your library", Theme.Colors.pink)
                tile("\(stats.uniqueTracksPlayed)", "Discovered", Theme.Colors.lavender)
                tile("\(thisWeek)", "This week", Theme.Colors.peach)
            }

            if !library.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        caption("LIBRARY BY SOURCE")
                        if spotifyCount > 0 { countRow("Spotify", spotifyCount, total: library.count, color: Theme.Colors.pink) }
                        if appleCount > 0 { countRow("Apple Music", appleCount, total: library.count, color: Theme.Colors.lavender) }
                        if profileAnalyzer.profile.totalTracksAnalyzed > 0 {
                            Text("Analyzed \(profileAnalyzer.profile.lastAnalyzed.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
            }

            if !stats.playsBySource.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        caption("DISCOVERED BY SOURCE")
                        ForEach(stats.playsBySource) { entry in
                            countRow(entry.source.displayName, entry.count, total: max(stats.uniqueTracksPlayed, 1),
                                     color: entry.source == .spotify ? Theme.Colors.pink : Theme.Colors.lavender)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("RECENTLY DISCOVERED")
                if stats.plays.isEmpty {
                    emptyNote("Tracks you hear in a discovery session will show up here.")
                } else {
                    ForEach(Array(stats.plays.prefix(5))) { event in
                        eventRow(event, detail: event.date.formatted(.relative(presentation: .named)))
                    }
                }
            }
        }
    }

    // MARK: - Gems

    private var gemsSection: some View {
        let savesThisWeek = stats.saves(since: stats.startOfWeek).count
        return VStack(alignment: .leading, spacing: 14) {
            header("Gems", icon: "sparkles")

            HStack(spacing: 10) {
                tile("\(deckGemCount)", "In your deck", Theme.Colors.mint)
                tile("\(savedGems.savedTrackIds.count)", "Saved", Theme.Colors.lime)
                tile("\(savesThisWeek)", "Saved this week", Theme.Colors.butter)
            }

            if !stats.saves.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        caption("HOW YOU SAVED THEM")
                        ForEach(ListeningStatsStore.SaveMethod.allCases, id: \.self) { method in
                            let n = stats.saveCount(method)
                            if n > 0 {
                                countRow(method.displayName, n, total: stats.saves.count, color: color(for: method))
                            }
                        }
                        Text("Counted since this update")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                caption("SAVE TIMELINE")
                if stats.saves.isEmpty {
                    emptyNote("Swipe right, tap 👍 on your watch, or let a track play through to save it.")
                } else {
                    ForEach(Array(stats.savesByDay.prefix(5))) { group in
                        Text(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .padding(.top, 4)
                        ForEach(Array(group.events.prefix(4))) { event in
                            eventRow(event, detail: event.method?.displayName ?? "")
                        }
                        if group.events.count > 4 {
                            Text("+\(group.events.count - 4) more")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func color(for method: ListeningStatsStore.SaveMethod) -> Color {
        switch method {
        case .swipe: return Theme.Colors.mint
        case .watch: return Theme.Colors.lavender
        case .auto: return Theme.Colors.butter
        }
    }

    // MARK: - Genres

    private var genresSection: some View {
        let weights = profileAnalyzer.profile.genreWeights
        let sorted: [GenreShare] = weights
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { GenreShare(name: $0.key, weight: $0.value) }
        let totalWeight = max(weights.values.reduce(0, +), 0.0001)
        let topWeight = max(sorted.first?.weight ?? 1, 0.0001)
        let libraryCounts = libraryGenreCounts()
        let discovered = stats.discoveredGenreCounts

        return VStack(alignment: .leading, spacing: 14) {
            header("Genres", icon: "square.grid.2x2")

            HStack(spacing: 10) {
                tile("\(weights.count)", "In your taste", Theme.Colors.butter)
                tile("\(discovered.count)", "Discovered", Theme.Colors.peach)
                tile(sorted.first?.name.capitalized ?? "—", "Top genre", Theme.Colors.lavender)
            }

            if sorted.isEmpty {
                emptyNote("Connect a music source and analyze your library to see your genres.")
            } else {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        caption("TOP GENRES")
                        ForEach(Array(sorted.prefix(8).enumerated()), id: \.offset) { index, entry in
                            let share = entry.weight / totalWeight
                            let tracks = libraryCounts[entry.name.lowercased()] ?? 0
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.name.capitalized)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(tracks > 0
                                         ? "\(tracks) tracks · \(Int((share * 100).rounded()))%"
                                         : "\(Int((share * 100).rounded()))%")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                bar(fraction: entry.weight / topWeight, color: Theme.Colors.pastel(index))
                            }
                        }
                    }
                }

                if !discovered.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        caption("DISCOVERED BY GENRE")
                        FlowLayout(spacing: 8) {
                            ForEach(Array(discovered.enumerated()), id: \.offset) { index, entry in
                                pill("\(entry.genre) · \(entry.count)", color: Theme.Colors.pastel(index))
                            }
                        }
                    }
                }

                if sorted.count > 8 {
                    VStack(alignment: .leading, spacing: 8) {
                        caption("ALSO EXPLORED")
                        FlowLayout(spacing: 8) {
                            ForEach(sorted.dropFirst(8).map { $0.name }, id: \.self) { name in
                                Text(name.capitalized)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Theme.Colors.chipFill))
                            }
                        }
                    }
                }
            }
        }
    }

    private struct GenreShare {
        let name: String
        let weight: Double
    }

    /// Library tracks per genre name (lowercased), from the genre tags on
    /// each analyzed track (Apple Music tracks carry these).
    private func libraryGenreCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for track in profileAnalyzer.libraryTracks {
            for name in Set(track.genreNames.map { $0.lowercased() }) {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func header(_ title: String, icon: String) -> some View {
        if only == nil {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(Theme.Colors.textPrimary)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.Colors.textSecondary)
            .tracking(0.5)
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(Theme.Colors.textOnPastel)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.Colors.textOnPastelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .fill(color)
        )
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .surfaceCard()
    }

    private func countRow(_ label: String, _ count: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            bar(fraction: Double(count) / Double(max(total, 1)), color: color)
        }
    }

    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.textPrimary.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.Colors.textOnPastel)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(color))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func eventRow(_ event: ListeningStatsStore.Event, detail: String) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: event.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.chipFill)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary))
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(event.artist)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
    }
}

/// Soft glow ring around a section right after a Home pill opens it.
private struct StatHighlight: ViewModifier {
    let on: Bool
    let color: Color

    func body(content: Content) -> some View {
        content
            .padding(on ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                    .stroke(color.opacity(on ? 0.9 : 0), lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.35), value: on)
    }
}
