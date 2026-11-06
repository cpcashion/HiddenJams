//
//  DiscoveryQuotaManagerTests.swift
//  HiddenJamsTests
//
//  Free-tier monthly quota: 50 cap, calendar-month rollover, entitlement
//  bypass, genre-switch doesn't reset, idempotent per-track consume.
//  Tests the pure DiscoveryQuotaState (+ a thin manager persistence check)
//  so they don't contend for the MainActor with GenreDeckBuilderTests.
//

import Foundation
import Testing
@testable import HiddenJams

struct DiscoveryQuotaManagerTests {

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
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
            #expect(s.consume(trackId: "t\(i)", isUnlimited: false, now: now, timeZone: TimeZone(secondsFromGMT: 0)!))
            #expect(s.usedThisMonth == i)
        }
        #expect(!s.canDiscover(isUnlimited: false))
        #expect(s.remaining(isUnlimited: false) == 0)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 0)
        #expect(!s.consume(trackId: "t51", isUnlimited: false, now: now, timeZone: TimeZone(secondsFromGMT: 0)!))
        #expect(s.usedThisMonth == 50)
    }

    @Test func idempotentConsumePerTrackId() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        let tz = TimeZone(secondsFromGMT: 0)!
        #expect(s.consume(trackId: "same", isUnlimited: false, now: now, timeZone: tz))
        #expect(!s.consume(trackId: "same", isUnlimited: false, now: now, timeZone: tz))
        #expect(!s.consume(trackId: "same", isUnlimited: false, now: now, timeZone: tz))
        #expect(s.usedThisMonth == 1)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 49)
    }

    @Test func genreSwitchDoesNotResetQuota() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        let tz = TimeZone(secondsFromGMT: 0)!
        for i in 1...20 { _ = s.consume(trackId: "a\(i)", isUnlimited: false, now: now, timeZone: tz) }
        #expect(s.usedThisMonth == 20)
        for i in 1...5 { _ = s.consume(trackId: "b\(i)", isUnlimited: false, now: now, timeZone: tz) }
        #expect(s.usedThisMonth == 25)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 25)
        #expect(s.canDiscover(isUnlimited: false))
    }

    @Test func monthRolloverResetsCountAndIds() {
        var s = fresh()
        let tz = TimeZone(secondsFromGMT: 0)!
        let nov = Self.date(year: 2026, month: 11, day: 6)
        for i in 1...10 { _ = s.consume(trackId: "t\(i)", isUnlimited: false, now: nov, timeZone: tz) }
        #expect(s.usedThisMonth == 10)

        let dec = Self.date(year: 2026, month: 12, day: 1)
        s.resetIfNewMonth(now: dec, timeZone: tz)
        #expect(s.usedThisMonth == 0)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: false) == 50)
        #expect(s.consume(trackId: "t1", isUnlimited: false, now: dec, timeZone: tz))
        #expect(s.usedThisMonth == 1)
    }

    @Test func entitlementBypassIsUnlimited() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        let tz = TimeZone(secondsFromGMT: 0)!
        #expect(s.canDiscover(isUnlimited: true))
        #expect(s.remaining(isUnlimited: true) == nil)
        #expect(s.batchRequestCount(defaultTarget: 50, isUnlimited: true) == 50)
        #expect(!s.consume(trackId: "p1", isUnlimited: true, now: now, timeZone: tz))
        #expect(s.usedThisMonth == 0)
    }

    @Test func simulateFreeTierIgnoresEntitlement() {
        // "Simulate free" is just isUnlimited == false even when StoreKit says premium.
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        let tz = TimeZone(secondsFromGMT: 0)!
        let simulatingFree = true
        let storeKitPremium = true
        let unlimited = storeKitPremium && !simulatingFree
        #expect(!unlimited)
        #expect(s.consume(trackId: "f1", isUnlimited: unlimited, now: now, timeZone: tz))
        #expect(s.usedThisMonth == 1)
    }

    @Test func batchRequestCountCapsToRemaining() {
        var s = fresh()
        let now = Self.date(year: 2026, month: 11, day: 6)
        let tz = TimeZone(secondsFromGMT: 0)!
        for i in 1...47 { _ = s.consume(trackId: "t\(i)", isUnlimited: false, now: now, timeZone: tz) }
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
        #expect(!q2.consume(trackId: "t3"))
        #expect(q2.consume(trackId: "t8"))
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
