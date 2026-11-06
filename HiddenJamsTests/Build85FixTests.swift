//
//  Build85FixTests.swift
//  HiddenJamsTests
//
//  Regression tests for TF build-85 diagnosis findings 3–7.
//  Each assertion encodes the post-fix contract (failed on main before this PR).
//

import Foundation
import Testing
@testable import HiddenJams

nonisolated struct Build85FixTests {

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

    // MARK: - Finding 3

    @Test @MainActor func resetClearsSimulateFreeTier() {
        let store = InMemoryDiscoveryQuotaStore()
        let suite = "Build85FixTests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Self.date(year: 2026, month: 11, day: 6)
        let q = DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { now },
            premiumCheck: { true },
            entitlementResolved: { true }
        )
        q.simulateFreeTier = true
        #expect(!q.isUnlimited)
        _ = q.consume(trackId: "burned")
        #expect(q.usedThisMonth == 1)

        q.resetQuotaForTesting()

        #expect(q.usedThisMonth == 0)
        #expect(q.simulateFreeTier == false)
        #expect(q.isUnlimited)
    }

    // MARK: - Finding 4

    @Test func prefetchLatchClearsOnEmptyAndRetries() {
        var latch = PrefetchLatch()
        #expect(latch.begin())
        #expect(!latch.begin()) // held
        let retry = latch.finish(.empty)
        #expect(!latch.isHeld)
        #expect(retry)
        #expect(latch.begin())
        #expect(latch.finish(.appended(3)) == false)
        #expect(latch.emptyOrFailedCount == 0)
    }

    @Test func prefetchLatchStopsAfterExhaustedOrMaxRetries() {
        var latch = PrefetchLatch()
        #expect(latch.begin())
        #expect(latch.finish(.exhausted) == false)

        latch.reset()
        for _ in 1...PrefetchLatch.maxEmptyRetries {
            #expect(latch.begin())
            #expect(latch.finish(.failed))
        }
        #expect(latch.begin())
        #expect(latch.finish(.failed) == false)
    }

    // MARK: - Finding 5

    @Test func discoveryGenerationDropsStaleAppendAfterReplace() {
        var token = DiscoveryGenerationToken()
        let prefetchGen = token.begin(appendResults: true)
        #expect(prefetchGen == 0)
        let replaceGen = token.begin(appendResults: false)
        #expect(replaceGen == 1)
        #expect(token.isStale(prefetchGen))
        #expect(!token.isStale(replaceGen))
        let appendAfter = token.begin(appendResults: true)
        #expect(appendAfter == 1)
        #expect(!token.isStale(appendAfter))
    }

    // MARK: - Finding 6

    @Test func onlyReadyPreviewsAllowConsume() {
        #expect(DiscoveryTrackCountPolicy.allowsConsume(previewReady: true, entitlementResolved: true))
        #expect(!DiscoveryTrackCountPolicy.allowsConsume(previewReady: false, entitlementResolved: true))
        #expect(!DiscoveryTrackCountPolicy.allowsConsume(previewReady: false, entitlementResolved: false))
    }

    // MARK: - Finding 7

    @Test @MainActor func consumeDeferredUntilEntitlementResolved() {
        let store = InMemoryDiscoveryQuotaStore()
        let suite = "Build85FixTests.entitlement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var resolved = false
        let now = Self.date(year: 2026, month: 11, day: 6)
        let q = DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { now },
            premiumCheck: { true },
            entitlementResolved: { resolved }
        )
        #expect(!q.consume(trackId: "cold-1"))
        #expect(q.usedThisMonth == 0)
        resolved = true
        // Premium → unlimited, still no count.
        #expect(!q.consume(trackId: "cold-1"))
        #expect(q.usedThisMonth == 0)
        #expect(q.isUnlimited)
    }

    @Test @MainActor func freeTierConsumesOnlyAfterEntitlementResolved() {
        let store = InMemoryDiscoveryQuotaStore()
        let suite = "Build85FixTests.freeEntitlement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var resolved = false
        let now = Self.date(year: 2026, month: 11, day: 6)
        let q = DiscoveryQuotaManager(
            store: store,
            defaults: defaults,
            now: { now },
            premiumCheck: { false },
            entitlementResolved: { resolved }
        )
        #expect(!q.consume(trackId: "f1"))
        #expect(q.usedThisMonth == 0)
        resolved = true
        #expect(q.consume(trackId: "f1"))
        #expect(q.usedThisMonth == 1)
        #expect(!q.consume(trackId: "f1")) // idempotent
        #expect(q.usedThisMonth == 1)
    }
}
