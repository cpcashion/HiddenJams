//
//  DiscoveryQuotaManagerTests.swift
//  HiddenJamsTests
//
//  Free-tier monthly quota: 50 cap, calendar-month rollover, entitlement
//  bypass, genre-switch doesn't reset, idempotent per-track consume.
//  Most cases hit pure DiscoveryQuotaState (no MainActor). Two thin
//  @MainActor cases cover manager persistence / TestFlight reset.
//

import Foundation
import Testing
@testable import HiddenJams

struct DiscoveryQuotaManagerTests {

    private static let tz = TimeZone(secondsFromGMT: 0)!

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.year = year
        c.month = month
        c.day = day
        return c.date!
    }

    private func fresh(month: String = "2026-11") -> DiscoveryQuotaState {
        DiscoveryQuotaState(month: month)
    }

    @Test func fiftyCapAndPaywallGate() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 50)
        for i in 1...50 {
            let consumed = s.consume(trackId: "t\(i)", isUnlimited: false, now: now, timeZone: Self.tz)
            #expect(consumed)
            #expect(s.usedThisMonth == i)
        }
        #expect(!s.canDiscover(isUnlimited: false))
        #expect(s.remaining(isUnlimited: false) == 0)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 0)
        let overflow = s.consume(trackId: "t51", isUnlimited: false, now: now, timeZone: Self.tz)
        #expect(!overflow)
        #expect(s.usedThisMonth == 50)
    }

    @Test func idempotentConsumePerTrackId() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        let first = s.consume(trackId: "same", isUnlimited: false, now: now, timeZone: Self.tz)
        let second = s.consume(trackId: "same", isUnlimited: false, now: now, timeZone: Self.tz)
        let third = s.consume(trackId: "same", isUnlimited: false, now: now, timeZone: Self.tz)
        #expect(first)
        #expect(!second)
        #expect(!third)
        #expect(s.usedThisMonth == 1)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 49)
    }

    @Test func genreSwitchDoesNotResetQuota() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        for i in 1...20 {
            _ = s.consume(trackId: "a\(i)", isUnlimited: false, now: now, timeZone: Self.tz)
        }
        #expect(s.usedThisMonth == 20)
        for i in 1...5 {
            _ = s.consume(trackId: "b\(i)", isUnlimited: false, now: now, timeZone: Self.tz)
        }
        #expect(s.usedThisMonth == 25)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 25)
        #expect(s.canDiscover(isUnlimited: false))
    }

    @Test func monthRolloverResetsCountAndIds() {
        var s = fresh()
        let nov = Self.date(year: 2026, month: 11, day: 6)
        for i in 1...10 {
            _ = s.consume(trackId: "t\(i)", isUnlimited: false, now: nov, timeZone: Self.tz)
        }
        #expect(s.usedThisMonth == 10)

        let dec = Self.date(year: 2026, month: 12, day: 1)
        s.resetIfNewMonth(now: dec, timeZone: Self.tz)
        #expect(s.usedThisMonth == 0)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 50)
        let again = s.consume(trackId: "t1", isUnlimited: false, now: dec, timeZone: Self.tz)
        #expect(again)
        #expect(s.usedThisMonth == 1)
    }

    @Test func entitlementBypassIsUnlimited() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        #expect(s.canDiscover(isUnlimited: true))
        #expect(s.remaining(isUnlimited: true) == nil)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: true) == 50)
        let consumed = s.consume(trackId: "p1", isUnlimited: true, now: now, timeZone: Self.tz)
        #expect(!consumed)
        #expect(s.usedThisMonth == 0)
    }

    @Test func simulateFreeTierIgnoresEntitlement() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        let storeKitPremium = true
        let simulatingFree = true
        let unlimited = storeKitPremium && !simulatingFree
        #expect(!unlimited)
        let consumed = s.consume(trackId: "f1", isUnlimited: unlimited, now: now, timeZone: Self.tz)
        #expect(consumed)
        #expect(s.usedThisMonth == 1)
    }

    @Test func batchRequestCountCapsToRemaining() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        for i in 1...47 {
            _ = s.consume(trackId: "t\(i)", isUnlimited: false, now: now, timeZone: Self.tz)
        }
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 3)
        #expect(s.batchRequestCount(defaultTarget: 2, isUnlimited: false) == 2)
    }

    @Test @MainActor func managerPersistsAcrossRelaunch() {
        let store = InMemoryDiscoveryQuotaStore()
        let suite = "DiscoveryQuotaManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Self.date(year: 2026, month: 11, day: 6)
        let q1 = DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { now },
            premiumCheck: { false }
        )
        for i in 1...7 { _ = q1.consume(trackId: "t\(i)") }

        let q2 = DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { now },
            premiumCheck: { false }
        )
        #expect(q2.usedThisMonth == 7)
        let again = q2.consume(trackId: "t3")
        let next = q2.consume(trackId: "t8")
        #expect(!again)
        #expect(next)
        #expect(q2.usedThisMonth == 8)
    }

    @Test @MainActor func managerResetClearsOnboardingFlag() {
        let store = InMemoryDiscoveryQuotaStore()
        let suite = "DiscoveryQuotaManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Self.date(year: 2026, month: 11, day: 6)
        let q = DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { now },
            premiumCheck: { false }
        )
        q.markOnboardingCompleted()
        for i in 1...12 { _ = q.consume(trackId: "t\(i)") }
        q.resetQuotaForTesting()
        #expect(q.usedThisMonth == 0)
        #expect(q.batchRequestCount() == 50)
        #expect(defaults.bool(forKey: DiscoveryQuotaManager.onboardingCompletedKey) == false)
    }
}
