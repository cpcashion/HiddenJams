//
//  GenreDiscoveryRegressionTests.swift
//  HiddenJamsTests
//
//  Regression tests for two user-reported bugs (2026-09-29):
//  1. Connecting a second music source (Apple Music after Spotify) wiped the
//     learned genre list instead of adding to it — the genre picker shrank.
//  2. "Select All" genres collapsed discovery into Drum & Bass mode (the DnB
//     override fired on mere INTERSECTION with DnB genres), so every result
//     was an electronic track literally titled "Bassline".

import Testing
import Foundation
@testable import HiddenJams

struct GenreDiscoveryRegressionTests {

    // MARK: - Genre weight merging (AIProfileAnalyzer)

    @Test func genreMergeAddsNewGenresWithoutDroppingOld() {
        let existing = ["pop": 0.5, "rock": 0.3]
        let new = ["jazz": 0.4, "electronic": 0.2]

        let merged = AIProfileAnalyzer.mergedGenreWeights(existing: existing, new: new)

        #expect(merged.count == 4)
        #expect(merged["pop"] == 0.5)
        #expect(merged["rock"] == 0.3)
        #expect(merged["jazz"] == 0.4)
        #expect(merged["electronic"] == 0.2)
    }

    @Test func genreMergeKeepsStrongestWeightPerGenre() {
        let existing = ["pop": 0.5]
        let new = ["pop": 0.9, "rock": 0.1]

        let merged = AIProfileAnalyzer.mergedGenreWeights(existing: existing, new: new)

        #expect(merged["pop"] == 0.9)
        #expect(merged["rock"] == 0.1)
    }

    @Test func genreMergeWithEmptyExistingKeepsNew() {
        let new = ["jazz": 0.4]
        let merged = AIProfileAnalyzer.mergedGenreWeights(existing: [:], new: new)
        #expect(merged == new)
    }

    @Test func genreMergeWithEmptyNewPreservesExisting() {
        // A source with no genre tags (e.g. untagged Apple Music tracks) must
        // never wipe the genres learned from another source.
        let existing = ["pop": 0.5, "rock": 0.3]
        let merged = AIProfileAnalyzer.mergedGenreWeights(existing: existing, new: [:])
        #expect(merged == existing)
    }

    // MARK: - DnB mode gating (EnhancedHiddenGemsDiscovery)

    @Test func dnbModeTriggersForDnBOnlySelection() {
        #expect(EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection(["drum and bass"]))
        #expect(EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection(["Drum and Bass", "JUNGLE"]))
        #expect(EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection(["dnb", "neurofunk", "liquid funk"]))
    }

    @Test func dnbModeDoesNotTriggerForSelectAll() {
        // Reproduces the "all baseline tracks" bug: "Select All" includes
        // "Drum and Bass" among dozens of genres and must stay in normal mode.
        let selectAll: Set<String> = [
            "pop", "rock", "hip hop", "country", "r&b", "electronic", "dance",
            "indie", "alternative", "classical", "jazz", "blues", "metal", "punk",
            "folk", "reggae", "soul", "funk", "latin", "drum and bass", "jungle",
            "house", "techno", "ambient"
        ]
        #expect(!EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection(selectAll))
    }

    @Test func dnbModeDoesNotTriggerForMixedSelection() {
        #expect(!EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection(["drum and bass", "house"]))
        #expect(!EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection(["pop"]))
        #expect(!EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection([]))
        #expect(!EnhancedHiddenGemsDiscovery.isDnBExclusiveSelection(nil))
    }
}
