//
//  OnboardingBuild93Tests.swift
//  HiddenJamsTests
//
//  Build 93 onboarding fixes: card swipes never page the pager, left = skip
//  / right = keep, and "Pick your genre's" stays on one line (SE to Pro Max).
//

import Foundation
import Testing
import UIKit
@testable import HiddenJams

@MainActor
struct OnboardingBuild93Tests {

    @Test func cardSwipeDirection() {
        let c = OBKeepScreen.commitDistance
        #expect(OBKeepSwipe.direction(translation: c + 1, predicted: c + 1, commit: c) == 1)
        #expect(OBKeepSwipe.direction(translation: -c - 1, predicted: -c - 1, commit: c) == -1)
        #expect(OBKeepSwipe.direction(translation: 30, predicted: 40, commit: c) == 0)
        // A fast fling commits even when the finger travelled less.
        #expect(OBKeepSwipe.direction(translation: 40, predicted: c * 3, commit: c) == 1)
        #expect(OBKeepSwipe.direction(translation: -40, predicted: -c * 3, commit: c) == -1)
    }

    @Test func cardDragHoldsThePager() {
        let lock = OBCardDragLock()
        let t0 = Date()
        #expect(!lock.isHeld(at: t0))
        lock.claim(at: t0)
        #expect(lock.isHeld(at: t0))
        #expect(lock.isHeld(at: t0.addingTimeInterval(0.2)))   // pager onEnded right after the card's
        #expect(!lock.isHeld(at: t0.addingTimeInterval(1.0)))  // a later swipe outside the cards pages
    }

    @Test func pagerSwipeRule() {
        // Swipe right on screen 2 (index 1) would go back to screen 1 — the
        // pager only does this when no card holds the drag lock.
        #expect(OBPagerSwipe.target(page: 1, pageCount: 5, dx: 120, dy: 5) == 0)
        #expect(OBPagerSwipe.target(page: 1, pageCount: 5, dx: -120, dy: 5) == 2)
        #expect(OBPagerSwipe.target(page: 4, pageCount: 5, dx: -120, dy: 5) == nil)
        #expect(OBPagerSwipe.target(page: 0, pageCount: 5, dx: 120, dy: 5) == nil)
        #expect(OBPagerSwipe.target(page: 2, pageCount: 5, dx: 40, dy: 5) == nil)
    }

    @Test func pickYourGenresFitsOneLine() {
        let text = OBCopy.moodTitleLead + OBCopy.moodTitleAccent
        #expect(text == "Pick your genre\u{2019}s")
        for screenWidth in [375.0, 393.0, 402.0, 430.0, 440.0] as [CGFloat] {
            let m = OBMetrics(width: screenWidth, height: 800)
            let size = OBOneLineTitle.fittedSize(text, maxSize: m.displayM, width: m.contentWidth)
            let w = OBFont.width(text, .black, size, kern: -0.045 * size)
            #expect(w <= m.contentWidth, "width \(screenWidth): \(w) > \(m.contentWidth)")
            #expect(size >= m.displayM * 0.6)
        }
    }

    @Test func headlineIsAboutThirtySecondClips() {
        #expect(OBCopy.connectHeadline.contains("30-second clips"))
    }
}
