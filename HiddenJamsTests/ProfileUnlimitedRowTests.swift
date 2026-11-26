//
//  ProfileUnlimitedRowTests.swift
//  HiddenJamsTests
//
//  Build 94 (App Review 2.1(b), 1.6.1): the "Hidden Jams Unlimited" row is
//  always on Profile, for every user, and a tap presents the paywall.
//

import XCTest
@testable import HiddenJams

@MainActor
final class ProfileUnlimitedRowTests: XCTestCase {

    /// The reviewer's state: free user, 0 plays this month, no music
    /// service connected, App Store (non-TestFlight) build.
    func testRowVisibleForFreshFreeUserWithNoMusicService() {
        let quota = DiscoveryQuotaState(month: "2026-11", usedThisMonth: 0)
        XCTAssertEqual(quota.usedThisMonth, 0)

        let sections = ProfileView.sections(hasConnectedSource: false, showsDebugTools: false)
        XCTAssertEqual(Array(sections.prefix(2)), [.header, .unlimited],
                       "Hidden Jams Unlimited must sit right under the Profile header")

        let content = UnlimitedRowContent(isPremium: false, displayPrice: nil)
        XCTAssertEqual(content.title, "Hidden Jams Unlimited")
        XCTAssertEqual(content.subtitle, "$1.99/month · unlimited songs")
        XCTAssertFalse(content.isActive)
    }

    /// No gating: connected or not, TestFlight or App Store.
    func testRowVisibleInEveryProfileState() {
        for connected in [false, true] {
            for debugTools in [false, true] {
                let sections = ProfileView.sections(hasConnectedSource: connected, showsDebugTools: debugTools)
                XCTAssertEqual(sections.filter { $0 == .unlimited }.count, 1,
                               "connected=\(connected) debugTools=\(debugTools)")
                XCTAssertEqual(sections.firstIndex(of: .unlimited), 1)
            }
        }
    }

    func testTapAsFreeUserPresentsPaywall() {
        let model = UnlimitedRowModel()
        XCTAssertFalse(model.showsPaywall)
        model.tap(isPremium: false)
        XCTAssertTrue(model.showsPaywall)
        XCTAssertFalse(model.showsManageSubscriptions)
    }

    func testTapAsSubscriberOpensManageSubscriptions() {
        let model = UnlimitedRowModel()
        model.tap(isPremium: true)
        XCTAssertTrue(model.showsManageSubscriptions)
        XCTAssertFalse(model.showsPaywall)
    }

    func testUsesStoreKitDisplayPriceWhenLoaded() {
        XCTAssertEqual(UnlimitedRowContent(isPremium: false, displayPrice: "$1.99").subtitle,
                       "$1.99/month · unlimited songs")
        XCTAssertEqual(UnlimitedRowContent(isPremium: false, displayPrice: "CA$2.99").subtitle,
                       "CA$2.99/month · unlimited songs")
    }

    func testActiveSubscriberCopy() {
        let content = UnlimitedRowContent(isPremium: true, displayPrice: "$1.99")
        XCTAssertEqual(content.title, "Hidden Jams Unlimited · Active")
        XCTAssertTrue(content.isActive)
    }

    func testNameMatchesAppStoreConnectProduct() {
        XCTAssertEqual(UnlimitedRowContent.productName, "Hidden Jams Unlimited")
        XCTAssertEqual(SubscriptionProduct.monthly.rawValue,
                       "com.chris.GettingStarted.HiddenJams.unlimited.monthly")
    }
}
