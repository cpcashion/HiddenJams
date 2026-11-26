//
//  DiscoveryQuotaManager.swift
//  HiddenJams
//
//  Free tier: 50 discovered tracks per calendar month (resets on the 1st,
//  local time). Pro (active $1.99/mo subscription): unlimited.
//
//  The counter is ONE cumulative monthly count — "Track N of 50" — not a
//  per-batch size. Consume once per newly shown track id (idempotent).
//
//  Count + month + counted track ids live in the Keychain (this device only,
//  not synced) so deleting and reinstalling the app doesn't reset the quota.
//
//  Build 93 (the "stuck at 49" loop): the counter used to be idempotent per
//  *track id*. At 49 the next batch is capped to one track, and the Apple
//  Music / Last.fm / iTunes paths explicitly allow repeats, so that one
//  card was often a track already counted earlier in the month. It showed
//  but didn't count, the count stayed at 49, `canDiscover` stayed true, the
//  paywall never opened, and every Next / Discover fetched another one-track
//  batch: Discover → track at 49 → Next → Discover → 49 … The player now
//  counts each card *appearance* (`appearanceKey`: deck + position + id), so
//  any new card moves the count, and the paywall is required at the limit.
//
//  TestFlight / sandbox only: "Remind me later" snoozes the limit for the
//  month, the paywall closes, and counting carries on 50, 51, 52 … (never
//  back to 49). Production never snoozes.
//

import Foundation
import Combine
import Security

// MARK: - Pure logic (nonisolated — unit-tested without MainActor contention)

/// Calendar-month discovery allowance. Mutable value type so tests can drive
/// it with a fake clock and no actors.
nonisolated struct DiscoveryQuotaState: Equatable, Sendable {
    static let freeMonthlyLimit = 50

    var month: String
    var usedThisMonth: Int
    var countedTrackIds: Set<String>
    /// TestFlight / sandbox only: the tester tapped "Remind me later" at the
    /// limit, so discovery and counting continue past it this month.
    var limitSnoozed: Bool

    init(month: String, usedThisMonth: Int = 0, countedTrackIds: Set<String> = [], limitSnoozed: Bool = false) {
        self.month = month
        self.usedThisMonth = usedThisMonth
        self.countedTrackIds = countedTrackIds
        self.limitSnoozed = limitSnoozed
    }

    /// Dedupe key for one card shown in the player: the same card re-firing
    /// (replay, back/forward) counts once, but a track served again in a
    /// later deck or position is a new card and counts.
    static func appearanceKey(trackId: String, deckID: String, index: Int) -> String {
        "\(trackId)#\(deckID).\(index)"
    }

    static func monthString(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        f.timeZone = timeZone
        return f.string(from: date)
    }

    mutating func resetIfNewMonth(now: Date, timeZone: TimeZone = .current) {
        let current = Self.monthString(for: now, timeZone: timeZone)
        if month != current {
            month = current
            usedThisMonth = 0
            countedTrackIds = []
            limitSnoozed = false
        }
    }

    var isAtLimit: Bool { usedThisMonth >= Self.freeMonthlyLimit }

    func canDiscover(isUnlimited: Bool) -> Bool {
        if isUnlimited || limitSnoozed { return true }
        return usedThisMonth < Self.freeMonthlyLimit
    }

    /// The paywall must be up (and stay up): free user, at the limit, not snoozed.
    func paywallRequired(isUnlimited: Bool) -> Bool {
        !isUnlimited && !limitSnoozed && isAtLimit
    }

    /// TestFlight "Remind me later": only at the limit. Returns true if it snoozed.
    @discardableResult
    mutating func snoozeLimit() -> Bool {
        guard isAtLimit, !limitSnoozed else { return false }
        limitSnoozed = true
        return true
    }

    func remaining(isUnlimited: Bool) -> Int? {
        if isUnlimited { return nil }
        return max(0, Self.freeMonthlyLimit - usedThisMonth)
    }

    func batchRequestCount(defaultTarget: Int, isUnlimited: Bool) -> Int {
        if isUnlimited || limitSnoozed { return defaultTarget }
        return max(0, min(defaultTarget, Self.freeMonthlyLimit - usedThisMonth))
    }

    /// Count a track the first time it is shown this month. Idempotent per id.
    @discardableResult
    mutating func consume(trackId: String, isUnlimited: Bool, now: Date, timeZone: TimeZone = .current) -> Bool {
        if isUnlimited { return false }
        guard !trackId.isEmpty else { return false }
        resetIfNewMonth(now: now, timeZone: timeZone)
        guard !countedTrackIds.contains(trackId) else { return false }
        guard usedThisMonth < Self.freeMonthlyLimit || limitSnoozed else { return false }
        countedTrackIds.insert(trackId)
        usedThisMonth += 1
        return true
    }
}

// MARK: - Persistence

nonisolated protocol DiscoveryQuotaStore: AnyObject {
    func load() -> DiscoveryQuotaManager.StoredQuota?
    func save(_ quota: DiscoveryQuotaManager.StoredQuota)
    func clear()
}

nonisolated final class KeychainDiscoveryQuotaStore: DiscoveryQuotaStore {
    private let service = "com.chris.GettingStarted.HiddenJams.quota"
    private let account = "monthlyDiscovery"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    func load() -> DiscoveryQuotaManager.StoredQuota? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(DiscoveryQuotaManager.StoredQuota.self, from: data)
    }

    func save(_ quota: DiscoveryQuotaManager.StoredQuota) {
        guard let data = try? JSONEncoder().encode(quota) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            attrs.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                print("⚠️ Quota keychain add failed: \(addStatus)")
            }
        } else if status != errSecSuccess {
            print("⚠️ Quota keychain update failed: \(status)")
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

nonisolated final class InMemoryDiscoveryQuotaStore: DiscoveryQuotaStore {
    var stored: DiscoveryQuotaManager.StoredQuota?
    func load() -> DiscoveryQuotaManager.StoredQuota? { stored }
    func save(_ quota: DiscoveryQuotaManager.StoredQuota) { stored = quota }
    func clear() { stored = nil }
}

// MARK: - Observable wrapper

@MainActor
final class DiscoveryQuotaManager: ObservableObject {
    static let shared = DiscoveryQuotaManager()

    static let freeMonthlyLimit = DiscoveryQuotaState.freeMonthlyLimit
    static let simulateFreeTierKey = "hj.simulateFreeTier"
    static let onboardingCompletedKey = "hj.hasCompletedOnboarding"

    private let legacyCountKey = "hj.dailyDiscoveryCount"
    private let legacyDateKey = "hj.dailyDiscoveryDate"

    struct StoredQuota: Codable, Equatable {
        var month: String
        var count: Int
        var trackIds: [String]
        /// Build 93; absent in older stored values (decodes as nil = false).
        var snoozed: Bool? = nil
    }

    @Published private(set) var usedThisMonth: Int = 0
    @Published private(set) var countedTrackIds: Set<String> = []
    @Published private(set) var limitSnoozed = false

    private var state: DiscoveryQuotaState
    private let store: DiscoveryQuotaStore
    private let now: () -> Date
    private let premiumCheck: () -> Bool
    /// False until StoreKit has answered once — consume is a no-op until then
    /// so a subscriber is not billed for cold-start tracks.
    private let entitlementResolved: () -> Bool
    /// True only on TestFlight / sandbox (and DEBUG) builds.
    private let allowsLimitSnooze: () -> Bool
    private let defaults: UserDefaults

    convenience init() {
        self.init(
            store: KeychainDiscoveryQuotaStore(),
            defaults: .standard,
            now: Date.init,
            premiumCheck: { UserProfileManager.shared.isPremium },
            entitlementResolved: { SubscriptionManager.shared.hasResolvedEntitlement },
            allowsLimitSnooze: { TestFlightTools.showsDebugTools }
        )
    }

    init(
        store: DiscoveryQuotaStore,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        premiumCheck: @escaping () -> Bool = { false },
        entitlementResolved: @escaping () -> Bool = { true },
        allowsLimitSnooze: @escaping () -> Bool = { false }
    ) {
        self.store = store
        self.defaults = defaults
        self.now = now
        self.premiumCheck = premiumCheck
        self.entitlementResolved = entitlementResolved
        self.allowsLimitSnooze = allowsLimitSnooze
        self.state = DiscoveryQuotaState(month: DiscoveryQuotaState.monthString(for: now()))
        load()
        syncPublished()
    }

    var simulateFreeTier: Bool {
        get { defaults.bool(forKey: Self.simulateFreeTierKey) }
        set {
            defaults.set(newValue, forKey: Self.simulateFreeTierKey)
            objectWillChange.send()
        }
    }

    var isUnlimited: Bool {
        if simulateFreeTier { return false }
        return premiumCheck()
    }

    var canDiscover: Bool {
        mutateState { $0.resetIfNewMonth(now: now()) }
        return state.canDiscover(isUnlimited: isUnlimited)
    }

    var remainingThisMonth: Int? {
        mutateState { $0.resetIfNewMonth(now: now()) }
        return state.remaining(isUnlimited: isUnlimited)
    }

    /// Free user at the limit (not snoozed): the paywall must be showing.
    var isPaywallRequired: Bool {
        mutateState { $0.resetIfNewMonth(now: now()) }
        return state.paywallRequired(isUnlimited: isUnlimited)
    }

    /// The paywall offers "Remind me later" (TestFlight / sandbox builds only).
    var canSnoozeLimit: Bool { allowsLimitSnooze() }

    /// TestFlight / sandbox "Remind me later": counting continues past the
    /// limit (50, 51, 52 …) for the rest of the month. No-op in production.
    @discardableResult
    func snoozeLimit() -> Bool {
        guard allowsLimitSnooze() else { return false }
        let snoozed = mutateState { $0.snoozeLimit() }
        if snoozed { print("📊 Quota: limit snoozed (TestFlight) at \(usedThisMonth)") }
        return snoozed
    }

    func batchRequestCount(defaultTarget: Int = 50) -> Int {
        mutateState { $0.resetIfNewMonth(now: now()) }
        return state.batchRequestCount(defaultTarget: defaultTarget, isUnlimited: isUnlimited)
    }

    @discardableResult
    func consume(trackId: String) -> Bool {
        // Finding 7: wait for the first StoreKit entitlement pass so Pro users
        // are not charged while isPremium is still the cold-start default.
        guard entitlementResolved() else {
            print("📊 Quota: defer consume until entitlement resolves (\(trackId))")
            return false
        }
        let changed = mutateState {
            $0.consume(trackId: trackId, isUnlimited: isUnlimited, now: now())
        }
        if changed {
            print("📊 Quota: \(usedThisMonth)/\(Self.freeMonthlyLimit) used this month (+\(trackId))")
        }
        return changed
    }

    func resetQuotaForTesting() {
        store.clear()
        state = DiscoveryQuotaState(month: DiscoveryQuotaState.monthString(for: now()))
        save()
        syncPublished()
        defaults.set(false, forKey: Self.onboardingCompletedKey)
        // Finding 3: Reset must clear Simulate free tier so Pro entitlement applies again.
        defaults.set(false, forKey: Self.simulateFreeTierKey)
        defaults.removeObject(forKey: legacyCountKey)
        defaults.removeObject(forKey: legacyDateKey)
        objectWillChange.send()
        print("📊 Quota: TestFlight reset")
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: Self.onboardingCompletedKey)
    }

    // MARK: - Private

    @discardableResult
    private func mutateState<T>(_ body: (inout DiscoveryQuotaState) -> T) -> T {
        let before = state
        let result = body(&state)
        if state != before {
            save()
            syncPublished()
        }
        return result
    }

    private func syncPublished() {
        usedThisMonth = state.usedThisMonth
        countedTrackIds = state.countedTrackIds
        limitSnoozed = state.limitSnoozed
    }

    private func load() {
        if let stored = store.load() {
            state = DiscoveryQuotaState(
                month: stored.month,
                usedThisMonth: stored.count,
                countedTrackIds: Set(stored.trackIds),
                limitSnoozed: stored.snoozed ?? false
            )
            mutateState { $0.resetIfNewMonth(now: now()) }
            return
        }
        let legacyCount = defaults.integer(forKey: legacyCountKey)
        let current = DiscoveryQuotaState.monthString(for: now())
        var used = 0
        if let legacyDay = defaults.string(forKey: legacyDateKey),
           legacyDay.hasPrefix(current) {
            used = min(legacyCount, Self.freeMonthlyLimit)
        }
        state = DiscoveryQuotaState(month: current, usedThisMonth: used)
        save()
        defaults.removeObject(forKey: legacyCountKey)
        defaults.removeObject(forKey: legacyDateKey)
    }

    private func save() {
        store.save(StoredQuota(
            month: state.month,
            count: state.usedThisMonth,
            trackIds: Array(state.countedTrackIds),
            snoozed: state.limitSnoozed ? true : nil
        ))
    }
}

#if DEBUG
extension DiscoveryQuotaManager {
    /// Capture fixtures only (parity snapshots): shows "Track N of 50" in the
    /// player header without touching the stored quota.
    func setUsedThisMonthForCapture(_ n: Int) {
        usedThisMonth = n
    }
}
#endif
