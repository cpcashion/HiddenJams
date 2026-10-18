//
//  GenreMatcherTests.swift
//  HiddenJamsTests
//
//  The genre gate behind Discover: a track only makes the deck when its
//  artist's genres match what the user picked. Regression for Chris's
//  2026-10-18 report: a Drum and Bass pick served "Bandshirt And A Cap" by
//  Side Effect, an indie rock band.
//

import Testing
import Foundation
@testable import HiddenJams

@MainActor
struct GenreMatcherTests {

    private func matches(_ selection: String, _ genres: [String]) -> Bool {
        GenreMatcher(selections: [selection]).match(genres) != nil
    }

    // MARK: - Canonical labels

    @Test func spellingVariantsCompareEqual() {
        #expect(GenreMatcher.tokens("Drum & Bass") == ["dnb"])
        #expect(GenreMatcher.tokens("drum-and-bass") == ["dnb"])
        #expect(GenreMatcher.tokens("Drum 'n' Bass") == ["dnb"])
        #expect(GenreMatcher.tokens("DnB") == ["dnb"])
        #expect(GenreMatcher.tokens("uk drum and bass") == ["uk", "dnb"])
        #expect(GenreMatcher.tokens("Hip-Hop") == ["hiphop"])
        #expect(GenreMatcher.tokens("R&B") == ["rnb"])
        #expect(GenreMatcher.tokens("r-n-b") == ["rnb"])
        #expect(GenreMatcher.tokens("K-Pop") == ["kpop"])
        #expect(GenreMatcher.tokens("synth-pop") == ["synthpop"])
        #expect(GenreMatcher.tokens("Lo-Fi Beats") == ["lofi", "beats"])
        #expect(GenreMatcher.tokens("Children's Music") == ["childrens", "music"])
    }

    @Test func matchingIsWholeWordsOnly() {
        #expect(GenreMatcher.label("deep house", contains: "house"))
        #expect(GenreMatcher.label("uk drum and bass", contains: "drum and bass"))
        #expect(!GenreMatcher.label("reggaeton", contains: "reggae"))
        #expect(!GenreMatcher.label("synthpop", contains: "pop"))
        #expect(!GenreMatcher.label("dubstep", contains: "dub"))
        #expect(!GenreMatcher.label("bass house", contains: "drum and bass"))
    }

    // MARK: - Drum and Bass (the reported bug)

    @Test func drumAndBassAcceptsItsSubgenres() {
        for genre in ["drum and bass", "Drum & Bass", "liquid funk", "neurofunk", "uk dnb",
                      "jump up", "deep liquid", "halftime dnb", "jungle", "dancefloor dnb"] {
            #expect(matches("Drum and Bass", [genre]), "\(genre) should count as drum and bass")
        }
    }

    @Test func drumAndBassRejectsEverythingElse() {
        // Side Effect's genres: indie rock. That track must never pass.
        for genre in ["indie rock", "garage rock", "rock", "electronic", "edm", "house",
                      "dubstep", "bass house", "funk", "jungle terror", "bass music"] {
            #expect(!matches("drum and bass", [genre]), "\(genre) must not count as drum and bass")
        }
        // No genres listed means unverified, not a pass.
        #expect(!matches("drum and bass", []))
    }

    // MARK: - Look-alike genres

    @Test func funkIsNotLiquidFunkOrGFunk() {
        #expect(matches("funk", ["funk"]))
        #expect(matches("funk", ["funk rock"]))
        #expect(matches("funk", ["p funk"]))
        #expect(!matches("funk", ["liquid funk"]))
        #expect(!matches("funk", ["g funk"]))
        #expect(!matches("funk", ["funk carioca"]))
        #expect(!matches("funk", ["brazilian funk"]))
    }

    @Test func reggaeIsNotReggaeton() {
        #expect(matches("reggae", ["roots reggae"]))
        #expect(matches("reggae", ["dub"]))
        #expect(!matches("reggae", ["reggaeton"]))
        #expect(!matches("reggae", ["dubstep"]))
        #expect(!matches("reggae", ["dub techno"]))
        #expect(!matches("reggaeton", ["reggae"]))
    }

    @Test func houseIsNotWitchHouse() {
        #expect(matches("house", ["deep house"]))
        #expect(matches("house", ["tech house"]))
        #expect(!matches("house", ["witch house"]))
    }

    @Test func popIsNotKPopOrPopPunk() {
        #expect(matches("pop", ["indie pop"]))
        #expect(matches("pop", ["synthpop"]))
        #expect(matches("pop", ["synth pop"]))
        #expect(!matches("pop", ["k-pop"]))
        #expect(!matches("pop", ["pop punk"]))
        #expect(!matches("pop", ["pop rap"]))
    }

    @Test func hipHopSpellingsAndRap() {
        #expect(matches("hip hop", ["hip-hop"]))
        #expect(matches("hip hop", ["underground hip hop"]))
        #expect(matches("hip hop", ["uk drill"]))
        #expect(matches("rap", ["hip hop"]))
        #expect(!matches("hip hop", ["trip hop"]))
        #expect(!matches("hip hop", ["drill and bass"]))
        // "Hip Hop" and "Rap" are one genre, not two.
        #expect(GenreMatcher(selections: ["hip hop", "rap"]).families.count == 1)
    }

    @Test func rnbVariants() {
        #expect(matches("r&b", ["alternative r&b"]))
        #expect(matches("R&B", ["neo soul"]))
        #expect(!matches("r&b", ["blues"]))
    }

    // MARK: - Exclusions

    @Test func holidayAndKidsMusicStayOut() {
        let matcher = GenreMatcher(selections: ["indie"])
        #expect(matcher.isExcluded(["christmas", "indie pop"]))
        #expect(matcher.isExcluded(["children's music"]))
        #expect(!matcher.isExcluded(["indie pop"]))
    }

    @Test func pickingAGenreLiftsItsExclusion() {
        #expect(GenreMatcher(selections: ["indie"]).isExcluded(["christian indie"]))
        #expect(!GenreMatcher(selections: ["christian"]).isExcluded(["christian indie"]))
        #expect(GenreMatcher(selections: ["house"]).isExcluded(["latin house"]))
        #expect(!GenreMatcher(selections: ["latin"]).isExcluded(["latin house"]))
        // Tropical house is EDM, not Latin.
        #expect(!GenreMatcher(selections: ["house"]).isExcluded(["tropical house"]))
    }

    @Test func userExclusionsApply() {
        let matcher = GenreMatcher(selections: ["hip hop"], userExcluded: ["trap"])
        #expect(matcher.isExcluded(["trap"]))
        #expect(!matcher.isExcluded(["boom bap"]))
    }

    // MARK: - Profile genres

    @Test func profileGenreMatchesExactlyThenFallsBackToItsParent() {
        let matcher = GenreMatcher(selections: ["uk drum and bass"])
        #expect(matcher.match(["uk dnb"])?.tier == 0)
        #expect(matcher.match(["liquid funk"])?.tier == 1)
        #expect(matcher.match(["indie rock"]) == nil)
        // The fallback is Drum and Bass, not all of Electronic.
        #expect(matcher.match(["techno"]) == nil)
    }

    @Test func nonLatinTitlesOnlyForGenresThatExpectThem() {
        #expect(GenreMatcher(selections: ["k-pop"]).families.first?.allowsNonLatinScript == true)
        #expect(GenreMatcher(selections: ["anime"]).families.first?.allowsNonLatinScript == true)
        #expect(GenreMatcher(selections: ["russian dnb"]).families.first?.allowsNonLatinScript == true)
        #expect(GenreMatcher(selections: ["drum and bass"]).families.first?.allowsNonLatinScript == false)
    }

    @Test func everyPickerGenreHasSearchesItAccepts() throws {
        let picker = ["Pop", "Rock", "Hip Hop", "Rap", "Country", "R&B", "Electronic", "Dance",
                      "Indie", "Alternative", "Classical", "Jazz", "Blues", "Metal", "Punk",
                      "Folk", "Reggae", "Soul", "Funk", "Latin", "Reggaeton", "K-Pop", "Anime",
                      "Gospel", "Christian", "Worship", "Drum and Bass", "Jungle", "House",
                      "Techno", "Ambient"]
        for name in picker {
            let matcher = GenreMatcher(selections: [name.lowercased()])
            let family = try #require(matcher.families.first)
            #expect(!family.searches.isEmpty, "\(name) has no searches")
            #expect(family.broader.isEmpty, "\(name) should be a curated genre")
            for search in family.searches {
                #expect(matcher.match([search]) != nil, "\(name): searching '\(search)' would find tracks the genre rejects")
            }
        }
    }
}
