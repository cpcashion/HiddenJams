//
//  QuotaLimitCrossingTests.swift
//  HiddenJamsTests
//
//  Build 93 regression: the free counter crossing the 50 limit.
//  Chris on TF 92: "At play 49 the app loops: Discover, a new track pops up
//  still at 49, Next, Discover again, back to 49." Root cause: the counter
//  was idempotent per track id, and the one-track batch at 49 could re-serve
//  an already-counted track. Now each card appearance counts, the paywall is
//  required at the limit, and on TestFlight "Remind me later" snoozes the
//  limit so the count carries on 50, 51, 52 (never back to 49).
//

import Foundation
import Testing
@testable import HiddenJams

nonisolated struct QuotaLimitCrossingTests {

    private static let tz = TimeZone(secondsFromGMT: 0)!
    private static let now: Date = {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.year = 2026; c.month = 11; c.day = 25
        return c.date!
    }()

    /// 49 cards shown in deck A (one per position).
    private func at49() -> DiscoveryQuotaState {
        var s = DiscoveryQuotaState(month: "2026-11")
        for i in 0..<49 {
            let key = DiscoveryQuotaState.appearanceKey(trackId: "t\(i)", deckID: "A", index: i)
            #expect(s.consume(trackId: key, isUnlimited: false, now: Self.now, timeZone: Self.tz))
        }
        #expect(s.usedThisMonth == 49)
        return s
    }

    @Test func repeatTrackAt49NowCounts() {
        var s = at49()
        // The one-track batch at 49 re-serves t3 (repeats are allowed on the
        // Apple Music / Last.fm paths). Old per-id keying: never counted.
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 1)
        var legacy = DiscoveryQuotaState(month: "2026-11")
        for i in 0..<49 { legacy.consume(trackId: "t\(i)", isUnlimited: false, now: Self.now, timeZone: Self.tz) }
        #expect(!legacy.consume(trackId: "t3", isUnlimited: false, now: Self.now, timeZone: Self.tz))
        #expect(legacy.usedThisMonth == 49 && legacy.canDiscover(isUnlimited: false)) // ← the loop

        // New keying: the re-served card in deck B is a new card → 50.
        let key = DiscoveryQuotaState.appearanceKey(trackId: "t3", deckID: "B", index: 0)
        #expect(s.consume(trackId: key, isUnlimited: false, now: Self.now, timeZone: Self.tz))
        #expect(s.usedThisMonth == 50)
        // Same card firing again (replay / back) still counts once.
        #expect(!s.consume(trackId: key, isUnlimited: false, now: Self.now, timeZone: Self.tz))
        #expect(s.usedThisMonth == 50)
    }

    @Test func paywallRequiredAtLimitAndStaysUp() {
        var s = at49()
        #expect(!s.paywallRequired(isUnlimited: false))
        s.consume(trackId: "t49#A.49", isUnlimited: false, now: Self.now, timeZone: Self.tz)
        #expect(s.usedThisMonth == 50)
        #expect(s.paywallRequired(isUnlimited: false))
        #expect(!s.canDiscover(isUnlimited: false))
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 0)
        // Production: more cards never count, and the count never rolls back.
        for i in 0..<5 {
            #expect(!s.consume(trackId: "x\(i)#C.\(i)", isUnlimited: false, now: Self.now, timeZone: Self.tz))
            #expect(s.usedThisMonth == 50)
            #expect(s.paywallRequired(isUnlimited: false))
        }
        // Pro is never paywalled.
        #expect(!s.paywallRequired(isUnlimited: true))
    }

    @Test func snoozeOnlyAtTheLimit() {
        var s = at49()
        #expect(!s.snoozeLimit())
        #expect(!s.limitSnoozed)
    }

    @Test func testFlightRemindLaterCounts49to50to51to52() {
        var s = at49()
        var seen: [Int] = [s.usedThisMonth]
        s.consume(trackId: "t49#A.49", isUnlimited: false, now: Self.now, timeZone: Self.tz)
        seen.append(s.usedThisMonth)
        #expect(s.paywallRequired(isUnlimited: false))
        #expect(s.snoozeLimit())                      // "Remind me later"
        #expect(!s.paywallRequired(isUnlimited: false))
        #expect(s.canDiscover(isUnlimited: false))
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 50)
        for i in 50..<53 {
            #expect(s.consume(trackId: "t\(i)#B.\(i)", isUnlimited: false, now: Self.now, timeZone: Self.tz))
            seen.append(s.usedThisMonth)
        }
        #expect(seen == [49, 50, 51, 52, 53])
        // Monotonic: never back to 49.
        #expect(zip(seen, seen.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func newMonthClearsSnooze() {
        var s = at49()
        s.consume(trackId: "t49#A.49", isUnlimited: false, now: Self.now, timeZone: Self.tz)
        s.snoozeLimit()
        var c = DateComponents(); c.calendar = Calendar(identifier: .gregorian); c.timeZone = Self.tz
        c.year = 2026; c.month = 12; c.day = 1
        s.resetIfNewMonth(now: c.date!, timeZone: Self.tz)
        #expect(!s.limitSnoozed && s.usedThisMonth == 0)
    }

    @Test func legacyStoredQuotaDecodesWithoutSnooze() throws {
        let json = #"{"month":"2026-11","count":49,"trackIds":["a"]}"#.data(using: .utf8)!
        let q = try JSONDecoder().decode(DiscoveryQuotaManager.StoredQuota.self, from: json)
        #expect(q.count == 49 && q.snoozed == nil)
    }

    // MARK: Manager (production vs TestFlight)

    @MainActor
    private func manager(store: InMemoryDiscoveryQuotaStore, testFlight: Bool) -> (DiscoveryQuotaManager, UserDefaults) {
        let suite = "QuotaLimitCrossingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let q = DiscoveryQuotaManager(store: store, defaults: defaults, now: { Self.now },
                                      premiumCheck: { false }, entitlementResolved: { true },
                                      allowsLimitSnooze: { testFlight })
        return (q, defaults)
    }

    @Test @MainActor func productionManagerKeepsPaywallAtLimit() {
        let (q, _) = manager(store: InMemoryDiscoveryQuotaStore(), testFlight: false)
        for i in 0..<50 { q.consume(trackId: "t\(i)#A.\(i)") }
        #expect(q.usedThisMonth == 50)
        #expect(q.isPaywallRequired)
        #expect(!q.canSnoozeLimit)
        #expect(!q.snoozeLimit())
        #expect(!q.consume(trackId: "t50#A.50"))
        #expect(q.usedThisMonth == 50)
        #expect(q.isPaywallRequired)
    }

    @Test @MainActor func testFlightManagerCountsPastLimitAndPersists() {
        let store = InMemoryDiscoveryQuotaStore()
        let (q, _) = manager(store: store, testFlight: true)
        for i in 0..<49 { q.consume(trackId: "t\(i)#A.\(i)") }
        #expect(q.usedThisMonth == 49)
        #expect(q.consume(trackId: "t49#A.49"))
        #expect(q.usedThisMonth == 50 && q.isPaywallRequired)
        #expect(q.canSnoozeLimit)
        #expect(q.snoozeLimit())
        #expect(!q.isPaywallRequired && q.limitSnoozed)
        #expect(q.consume(trackId: "t50#B.0")); #expect(q.usedThisMonth == 51)
        #expect(q.consume(trackId: "t51#B.1")); #expect(q.usedThisMonth == 52)

        // Relaunch: still 52, still snoozed, never back to 49.
        let (q2, _) = manager(store: store, testFlight: true)
        #expect(q2.usedThisMonth == 52)
        #expect(q2.limitSnoozed && !q2.isPaywallRequired)
    }
}
