//
//  Build88FeedbackTests.swift
//  HiddenJamsTests
//
//  Build 88 feedback: the mini player is hidden only on Profile.
//  (The fun-facts list is checked against FUNFACTS_SOURCES.md in the design
//  folder; an XCTest touching it tripped the known simulator host malloc
//  abort at 0x262543f40 in CI, so it is not run here.)
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
}
