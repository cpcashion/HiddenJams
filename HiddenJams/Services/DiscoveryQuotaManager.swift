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

import Foundation
import Combine
import Security

// MARK: - Pure logic (nonisolated — unit-tested without MainActor contention)

/// Calendar-month discovery allowance. Mutable value type so tests can drive
/// it with a fake clock and no actors.
struct DiscoveryQuotaState: Equatable, Sendable {
    static let freeMonthlyLimit = 50

    var month: String
    var usedThisMonth: Int
    var countedTrackIds: Set<String>

    init(month: String, usedThisMonth: Int = 0, countedTrackIds: Set<String> = []) {
        self.month = month
        self.usedThisMonth = usedThisMonth
        self.countedTrackIds = countedTrackIds
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
        }
    }

    func canDiscover(isUnlimited: Bool) -> Bool {
        if isUnlimited { return true }
        return usedThisMonth < Self.freeMonthlyLimit
    }

    func remaining(isUnlimited: Bool) -> Int? {
        if isUnlimited { return nil }
        return max(0, Self.freeMonthlyLimit - usedThisMonth)
    }

    func batchRequestCount(defaultTarget: Int, isUnlimited: Bool) -> Int {
        if isUnlimited { return defaultTarget }
        return max(0, min(defaultTarget, Self.freeMonthlyLimit - usedThisMonth))
    }

    /// Count a track the first time it is shown this month. Idempotent per id.
    @discardableResult
    mutating func consume(trackId: String, isUnlimited: Bool, now: Date, timeZone: TimeZone = .current) -> Bool {
        if isUnlimited { return false }
        guard !trackId.isEmpty else { return false }
        resetIfNewMonth(now: now, timeZone: timeZone)
        guard !countedTrackIds.contains(trackId) else { return false }
        guard usedThisMonth < Self.freeMonthlyLimit else { return false }
        countedTrackIds.insert(trackId)
        usedThisMonth += 1
        return true
    }
}

// MARK: - Persistence

protocol DiscoveryQuotaStore: AnyObject {
    func load() -> DiscoveryQuotaManager.StoredQuota?
    func save(_ quota: DiscoveryQuotaManager.StoredQuota)
    func clear()
}

final class KeychainDiscoveryQuotaStore: DiscoveryQuotaStore {
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

final class InMemoryDiscoveryQuotaStore: DiscoveryQuotaStore {
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
    }

    @Published private(set) var usedThisMonth: Int = 0
    @Published private(set) var countedTrackIds: Set<String> = []

    private var state: DiscoveryQuotaState
    private let store: DiscoveryQuotaStore
    private let now: () -> Date
    private let premiumCheck: () -> Bool
    private let defaults: UserDefaults

    convenience init() {
        self.init(
            store: KeychainDiscoveryQuotaStore(),
            defaults: .standard,
            now: Date.init,
            premiumCheck: { UserProfileManager.shared.isPremium }
        )
    }

    init(
        store: DiscoveryQuotaStore,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        premiumCheck: @escaping () -> Bool = { false }
    ) {
        self.store = store
        self.defaults = defaults
        self.now = now
        self.premiumCheck = premiumCheck
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

    func batchRequestCount(defaultTarget: Int = 50) -> Int {
        mutateState { $0.resetIfNewMonth(now: now()) }
        return state.batchRequestCount(defaultTarget: defaultTarget, isUnlimited: isUnlimited)
    }

    @discardableResult
    func consume(trackId: String) -> Bool {
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
        defaults.removeObject(forKey: legacyCountKey)
        defaults.removeObject(forKey: legacyDateKey)
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
    }

    private func load() {
        if let stored = store.load() {
            state = DiscoveryQuotaState(
                month: stored.month,
                usedThisMonth: stored.count,
                countedTrackIds: Set(stored.trackIds)
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
            trackIds: Array(state.countedTrackIds)
        ))
    }
}
