//
//  DiscoveryQuotaManagerTests.swift
//  HiddenJamsTests
//
//  Free-tier monthly quota: 50 cap, calendar-month rollover, entitlement
//  bypass, genre-switch doesn't reset, idempotent per-track consume.
//

import XCTest
@testable import HiddenJams

@MainActor
final class DiscoveryQuotaManagerTests: XCTestCase {

    private var store: InMemoryDiscoveryQuotaStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var now: Date!
    private var isPremium: Bool!

    override func setUp() {
        super.setUp()
        store = InMemoryDiscoveryQuotaStore()
        suiteName = "DiscoveryQuotaManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        now = Self.date(year: 2026, month: 11, day: 6)
        isPremium = false
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeQuota() -> DiscoveryQuotaManager {
        DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { [unowned self] in self.now },
            premiumCheck: { [unowned self] in self.isPremium }
        )
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.year = year
        c.month = month
        c.day = day
        return c.date!
    }

    func testFiftyCapAndPaywallGate() {
        let q = makeQuota()
        XCTAssertEqual(q.batchRequestCount(), 50)
        for i in 1...50 {
            XCTAssertTrue(q.consume(trackId: "t\(i)"), "consume #\(i)")
            XCTAssertEqual(q.usedThisMonth, i)
        }
        XCTAssertFalse(q.canDiscover)
        XCTAssertEqual(q.remainingThisMonth, 0)
        XCTAssertEqual(q.batchRequestCount(), 0)
        XCTAssertFalse(q.consume(trackId: "t51"), "no 51st free track")
        XCTAssertEqual(q.usedThisMonth, 50)
    }

    func testIdempotentConsumePerTrackId() {
        let q = makeQuota()
        XCTAssertTrue(q.consume(trackId: "same"))
        XCTAssertFalse(q.consume(trackId: "same"))
        XCTAssertFalse(q.consume(trackId: "same"))
        XCTAssertEqual(q.usedThisMonth, 1)
        XCTAssertEqual(q.batchRequestCount(), 49)
    }

    func testGenreSwitchDoesNotResetQuota() {
        // Genre switches rebuild the deck but must not replenish the allowance.
        let q = makeQuota()
        for i in 1...20 { _ = q.consume(trackId: "a\(i)") }
        XCTAssertEqual(q.usedThisMonth, 20)
        // Simulate a genre-switch session: new track ids, same month.
        for i in 1...5 { _ = q.consume(trackId: "b\(i)") }
        XCTAssertEqual(q.usedThisMonth, 25)
        XCTAssertEqual(q.batchRequestCount(), 25)
        XCTAssertTrue(q.canDiscover)
    }

    func testMonthRolloverResetsCountAndIds() {
        let q = makeQuota()
        for i in 1...10 { _ = q.consume(trackId: "t\(i)") }
        XCTAssertEqual(q.usedThisMonth, 10)

        now = Self.date(year: 2026, month: 12, day: 1)
        // Next public call triggers rollover.
        XCTAssertTrue(q.canDiscover)
        XCTAssertEqual(q.usedThisMonth, 0)
        XCTAssertEqual(q.batchRequestCount(), 50)
        // Old ids do not block the new month.
        XCTAssertTrue(q.consume(trackId: "t1"))
        XCTAssertEqual(q.usedThisMonth, 1)
    }

    func testEntitlementBypassIsUnlimited() {
        isPremium = true
        let q = makeQuota()
        XCTAssertTrue(q.isUnlimited)
        XCTAssertTrue(q.canDiscover)
        XCTAssertNil(q.remainingThisMonth)
        XCTAssertEqual(q.batchRequestCount(), 50)
        XCTAssertFalse(q.consume(trackId: "p1"), "unlimited does not consume")
        XCTAssertEqual(q.usedThisMonth, 0)
    }

    func testSimulateFreeTierIgnoresEntitlement() {
        isPremium = true
        let q = makeQuota()
        q.simulateFreeTier = true
        XCTAssertFalse(q.isUnlimited)
        XCTAssertTrue(q.canDiscover)
        XCTAssertTrue(q.consume(trackId: "f1"))
        XCTAssertEqual(q.usedThisMonth, 1)
        q.simulateFreeTier = false
        XCTAssertTrue(q.isUnlimited)
    }

    func testPersistenceAcrossRelaunch() {
        let q1 = makeQuota()
        for i in 1...7 { _ = q1.consume(trackId: "t\(i)") }
        // Relaunch: new manager, same store.
        let q2 = makeQuota()
        XCTAssertEqual(q2.usedThisMonth, 7)
        XCTAssertFalse(q2.consume(trackId: "t3"), "already counted")
        XCTAssertTrue(q2.consume(trackId: "t8"))
        XCTAssertEqual(q2.usedThisMonth, 8)
    }

    func testResetForTestingClearsQuotaAndOnboardingFlag() {
        let q = makeQuota()
        q.markOnboardingCompleted()
        for i in 1...12 { _ = q.consume(trackId: "t\(i)") }
        q.resetQuotaForTesting()
        XCTAssertEqual(q.usedThisMonth, 0)
        XCTAssertEqual(q.batchRequestCount(), 50)
        XCTAssertFalse(defaults.bool(forKey: DiscoveryQuotaManager.onboardingCompletedKey))
    }

    func testBatchRequestCountCapsToRemaining() {
        let q = makeQuota()
        for i in 1...47 { _ = q.consume(trackId: "t\(i)") }
        XCTAssertEqual(q.batchRequestCount(defaultTarget: 50), 3)
        XCTAssertEqual(q.batchRequestCount(defaultTarget: 2), 2)
    }
}
