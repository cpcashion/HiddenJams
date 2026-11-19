//
//  OnboardingV5Tests.swift
//  HiddenJamsTests
//
//  Onboarding v5: genre carry-through contract, shared genre catalog, and
//  the taste-profile math (genre shares, Last.fm rarity mapping, score).
//

import Testing
import Foundation
@testable import HiddenJams

@MainActor
struct OnboardingV5Tests {

    private func freshDefaults() -> UserDefaults {
        let name = "OnboardingV5Tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: GenreCatalog

    @Test func catalogHas31GenresAndOnboardingOrderIsSameSet() {
        #expect(GenreCatalog.common.count == 31)
        #expect(Set(GenreCatalog.common.map { $0.lowercased() }) == Set(GenreCatalog.onboardingOrder))
        #expect(GenreCatalog.onboardingOrder.count == 31)
    }

    @Test func pickerStillUsesTheSharedList() {
        #expect(GenreSelectionView().commonGenres == GenreCatalog.common)
    }

    @Test func noPicksLeavesKeyUnset() {
        let d = freshDefaults()
        GenreCatalog.saveOnboardingPicks([], to: d)
        #expect(d.object(forKey: GenreCatalog.selectedGenresKey) == nil)
        #expect(GenreCatalog.loadSelected(from: d) == nil)
    }

    @Test func picksAreWrittenAsLowercasedSetTheAppCanRead() throws {
        let d = freshDefaults()
        GenreCatalog.saveOnboardingPicks(["Soul", "r&b", "Hip Hop"], to: d)
        let data = try #require(d.data(forKey: "selectedGenres"))
        // Same decode the picker, Dashboard and MainTabView use.
        let decoded = try JSONDecoder().decode(Set<String>.self, from: data)
        #expect(decoded == ["soul", "r&b", "hip hop"])
    }

    @Test func clearingAllPicksRemovesTheKey() {
        let d = freshDefaults()
        GenreCatalog.saveOnboardingPicks(["jazz"], to: d)
        GenreCatalog.saveOnboardingPicks([], to: d)
        #expect(d.object(forKey: GenreCatalog.selectedGenresKey) == nil)
    }

    // MARK: Taste profile math

    @Test func appleAndSpotifyLabelsMapToCatalogGenres() {
        #expect(TasteProfileBuilder.catalogGenres(forLabel: "Jazz").contains("jazz"))
        #expect(TasteProfileBuilder.catalogGenres(forLabel: "Hip-Hop/Rap").contains("hip hop"))
        #expect(TasteProfileBuilder.catalogGenres(forLabel: "Hip-Hop/Rap").contains("rap") == false) // same family, deduped
    }

    @Test func genreSharesSumToOneAndSortDescending() {
        let shares = TasteProfileBuilder.genreShares(weightedLabels: ["jazz": 6, "soul": 3, "funk": 1, "zzz-not-a-genre": 50])
        #expect(shares.first?.genre == "jazz")
        let total = shares.map(\.share).reduce(0, +)
        #expect(abs(total - 1) < 0.0001)
        #expect(shares.allSatisfy { GenreCatalog.onboardingOrder.contains($0.genre) })
    }

    @Test func listenerMappingIsMonotonicAndBounded() {
        #expect(TasteRarity.score(forListeners: 500) == 100)
        #expect(TasteRarity.score(forListeners: 10_000) > TasteRarity.score(forListeners: 1_000_000))
        #expect(TasteRarity.score(forListeners: 1_000_000_000) == 0)
        #expect(TasteRarity.tier(forScore: 96) == .mythic)
        #expect(TasteRarity.tier(forScore: 72) == .rare)
        #expect(TasteRarity.tier(forScore: 10) == .known)
    }

    @Test func profileScoreNeedsThreeRatedArtistsAndNeverFakes() {
        let r = { (s: Int) in TasteArtistRarity(score: s, listeners: 1, playcount: nil, source: .lastFm) }
        let two = TasteProfileBuilder.profileScore(artistWeights: [("a", 1), ("b", 1), ("c", 1)],
                                                   rarities: ["a": r(97), "b": r(97)])
        #expect(two == nil)
        let three = TasteProfileBuilder.profileScore(artistWeights: [("a", 1), ("b", 1), ("c", 1)],
                                                     rarities: ["a": r(97), "b": r(97), "c": r(10)])
        // (1 + 1 + 0) / 3 = 67
        #expect(three?.score == 67)
        #expect(three?.rated == 3)
    }

    @Test func emptyLibraryIsFreshStart() {
        #expect(TasteProfile(librarySize: 3).isEmptyLibrary)
        #expect(TasteProfile(librarySize: 300).isEmptyLibrary == false)
    }
}
