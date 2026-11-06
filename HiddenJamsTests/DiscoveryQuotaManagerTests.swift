//
//  DiscoveryQuotaManagerTests.swift
//  HiddenJamsTests
//
//  Free-tier monthly quota: 50 cap, calendar-month rollover, entitlement
//  bypass, genre-switch doesn't reset, idempotent per-track consume.
//

import Foundation
import Testing
@testable import HiddenJams

@MainActor
struct DiscoveryQuotaManagerTests {

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private final class PremiumFlag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = year
        c.month = month
        c.day = day
        return c.date!
    }

    private func makeQuota(
        clock: Clock,
        premium: PremiumFlag,
        store: InMemoryDiscoveryQuotaStore = InMemoryDiscoveryQuotaStore(),
        defaults: UserDefaults
    ) -> DiscoveryQuotaManager {
        DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { clock.now },
            premiumCheck: { premium.value }
        )
    }

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "DiscoveryQuotaManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func fiftyCapAndPaywallGate() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let q = makeQuota(
            clock: Clock(Self.date(year: 2026, month: 11, day: 6)),
            premium: PremiumFlag(false),
            defaults: defaults
        )
        #expect(q.batchRequestCount() == 50)
        for i in 1...50 {
            #expect(q.consume(trackId: "t\(i)"))
            #expect(q.usedThisMonth == i)
        }
        #expect(!q.canDiscover)
        #expect(q.remainingThisMonth == 0)
        #expect(q.batchRequestCount() == 0)
        #expect(!q.consume(trackId: "t51"))
        #expect(q.usedThisMonth == 50)
    }

    @Test func idempotentConsumePerTrackId() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let q = makeQuota(
            clock: Clock(Self.date(year: 2026, month: 11, day: 6)),
            premium: PremiumFlag(false),
            defaults: defaults
        )
        #expect(q.consume(trackId: "same"))
        #expect(!q.consume(trackId: "same"))
        #expect(!q.consume(trackId: "same"))
        #expect(q.usedThisMonth == 1)
        #expect(q.batchRequestCount() == 49)
    }

    @Test func genreSwitchDoesNotResetQuota() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let q = makeQuota(
            clock: Clock(Self.date(year: 2026, month: 11, day: 6)),
            premium: PremiumFlag(false),
            defaults: defaults
        )
        for i in 1...20 { _ = q.consume(trackId: "a\(i)") }
        #expect(q.usedThisMonth == 20)
        for i in 1...5 { _ = q.consume(trackId: "b\(i)") }
        #expect(q.usedThisMonth == 25)
        #expect(q.batchRequestCount() == 25)
        #expect(q.canDiscover)
    }

    @Test func monthRolloverResetsCountAndIds() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock(Self.date(year: 2026, month: 11, day: 6))
        let q = makeQuota(clock: clock, premium: PremiumFlag(false), defaults: defaults)
        for i in 1...10 { _ = q.consume(trackId: "t\(i)") }
        #expect(q.usedThisMonth == 10)

        clock.now = Self.date(year: 2026, month: 12, day: 1)
        #expect(q.canDiscover)
        #expect(q.usedThisMonth == 0)
        #expect(q.batchRequestCount() == 50)
        #expect(q.consume(trackId: "t1"))
        #expect(q.usedThisMonth == 1)
    }

    @Test func entitlementBypassIsUnlimited() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let q = makeQuota(
            clock: Clock(Self.date(year: 2026, month: 11, day: 6)),
            premium: PremiumFlag(true),
            defaults: defaults
        )
        #expect(q.isUnlimited)
        #expect(q.canDiscover)
        #expect(q.remainingThisMonth == nil)
        #expect(q.batchRequestCount() == 50)
        #expect(!q.consume(trackId: "p1"))
        #expect(q.usedThisMonth == 0)
    }

    @Test func simulateFreeTierIgnoresEntitlement() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let q = makeQuota(
            clock: Clock(Self.date(year: 2026, month: 11, day: 6)),
            premium: PremiumFlag(true),
            defaults: defaults
        )
        q.simulateFreeTier = true
        #expect(!q.isUnlimited)
        #expect(q.canDiscover)
        #expect(q.consume(trackId: "f1"))
        #expect(q.usedThisMonth == 1)
        q.simulateFreeTier = false
        #expect(q.isUnlimited)
    }

    @Test func persistenceAcrossRelaunch() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = InMemoryDiscoveryQuotaStore()
        let clock = Clock(Self.date(year: 2026, month: 11, day: 6))
        let premium = PremiumFlag(false)
        let q1 = makeQuota(clock: clock, premium: premium, store: store, defaults: defaults)
        for i in 1...7 { _ = q1.consume(trackId: "t\(i)") }

        let q2 = makeQuota(clock: clock, premium: premium, store: store, defaults: defaults)
        #expect(q2.usedThisMonth == 7)
        #expect(!q2.consume(trackId: "t3"))
        #expect(q2.consume(trackId: "t8"))
        #expect(q2.usedThisMonth == 8)
    }

    @Test func resetForTestingClearsQuotaAndOnboardingFlag() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let q = makeQuota(
            clock: Clock(Self.date(year: 2026, month: 11, day: 6)),
            premium: PremiumFlag(false),
            defaults: defaults
        )
        q.markOnboardingCompleted()
        for i in 1...12 { _ = q.consume(trackId: "t\(i)") }
        q.resetQuotaForTesting()
        #expect(q.usedThisMonth == 0)
        #expect(q.batchRequestCount() == 50)
        #expect(defaults.bool(forKey: DiscoveryQuotaManager.onboardingCompletedKey) == false)
    }

    @Test func batchRequestCountCapsToRemaining() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let q = makeQuota(
            clock: Clock(Self.date(year: 2026, month: 11, day: 6)),
            premium: PremiumFlag(false),
            defaults: defaults
        )
        for i in 1...47 { _ = q.consume(trackId: "t\(i)") }
        #expect(q.batchRequestCount(defaultTarget: 50) == 3)
        #expect(q.batchRequestCount(defaultTarget: 2) == 2)
    }
}
