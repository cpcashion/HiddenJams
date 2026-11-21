//
//  Build88FeedbackTests.swift
//  HiddenJamsTests
//
//  Build 88 feedback: the mini player is hidden only on Profile, and the
//  loading fun facts are verified statements (no quiz questions) with a
//  length-based hold time.
//

import XCTest
@testable import HiddenJams

@MainActor
final class Build88FeedbackTests: XCTestCase {

    func testMiniPlayerHiddenOnlyOnProfile() {
        XCTAssertTrue(ContentView.showsMiniPlayer(on: .home))
        XCTAssertTrue(ContentView.showsMiniPlayer(on: .player))
        XCTAssertFalse(ContentView.showsMiniPlayer(on: .profile))
    }

    func testFunFactsAreStatementsOnly() {
        let facts = MusicFactsDatabase.allFacts
        XCTAssertTrue((20...30).contains(facts.count), "\(facts.count) facts")
        XCTAssertEqual(Set(facts).count, facts.count, "duplicate fact")
        for f in facts {
            XCTAssertFalse(f.contains("?"), "question, not a fact: \(f)")
            XCTAssertFalse(f.contains("✓"), "quiz answer marker: \(f)")
        }
        for f in facts {
            let hold = RotatingFactsView.holdSeconds(for: f)
            XCTAssertTrue(hold >= 2.2 && hold <= 4.8, "hold \(hold)s for \(f)")
        }
        XCTAssertTrue(MusicFactsService().facts.allSatisfy { facts.contains($0) })
    }
}
