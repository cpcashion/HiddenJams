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

/// Persistence for the monthly discovery quota. Production uses the Keychain;
/// unit tests inject an in-memory store.
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

@MainActor
final class DiscoveryQuotaManager: ObservableObject {
    static let shared = DiscoveryQuotaManager()

    /// Free tracks per calendar month.
    static let freeMonthlyLimit = 50

    /// TestFlight / DEBUG: when true, discovery UI ignores StoreKit entitlement.
    static let simulateFreeTierKey = "hj.simulateFreeTier"
    /// Cleared by the TestFlight reset tool (onboarding is connection-gated today).
    static let onboardingCompletedKey = "hj.hasCompletedOnboarding"

    // Legacy UserDefaults keys (daily quota, builds ≤ 82) — migrated once.
    private let legacyCountKey = "hj.dailyDiscoveryCount"
    private let legacyDateKey = "hj.dailyDiscoveryDate"

    struct StoredQuota: Codable, Equatable {
        var month: String
        var count: Int
        var trackIds: [String]
    }

    @Published private(set) var usedThisMonth: Int = 0
    /// Track ids already counted this month (idempotent consume).
    @Published private(set) var countedTrackIds: Set<String> = []

    private var month: String = ""
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

    /// Test / custom injection seam.
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
        load()
        resetIfNewMonth()
    }

    // MARK: - Entitlement / TestFlight simulate-free

    /// Local TestFlight-only flag: discovery behaves as free even if StoreKit
    /// says the user is subscribed. Never revokes anything in StoreKit.
    var simulateFreeTier: Bool {
        get { defaults.bool(forKey: Self.simulateFreeTierKey) }
        set {
            defaults.set(newValue, forKey: Self.simulateFreeTierKey)
            objectWillChange.send()
        }
    }

    /// True when discovery is unlimited (active entitlement and not simulating free).
    var isUnlimited: Bool {
        if simulateFreeTier { return false }
        return premiumCheck()
    }

    // MARK: - Public

    /// True if the user may discover / be shown more tracks right now.
    var canDiscover: Bool {
        if isUnlimited { return true }
        resetIfNewMonth()
        return usedThisMonth < Self.freeMonthlyLimit
    }

    /// Tracks remaining for free users this month. Nil for unlimited.
    var remainingThisMonth: Int? {
        if isUnlimited { return nil }
        resetIfNewMonth()
        return max(0, Self.freeMonthlyLimit - usedThisMonth)
    }

    /// How many tracks a new Discover / prefetch batch may request.
    func batchRequestCount(defaultTarget: Int = 50) -> Int {
        if isUnlimited { return defaultTarget }
        resetIfNewMonth()
        return max(0, min(defaultTarget, Self.freeMonthlyLimit - usedThisMonth))
    }

    /// Count a track the first time it is shown this month. Idempotent per id.
    /// Returns true when this call newly consumed a slot.
    @discardableResult
    func consume(trackId: String) -> Bool {
        if isUnlimited { return false }
        guard !trackId.isEmpty else { return false }
        resetIfNewMonth()
        guard !countedTrackIds.contains(trackId) else { return false }
        guard usedThisMonth < Self.freeMonthlyLimit else { return false }
        countedTrackIds.insert(trackId)
        usedThisMonth += 1
        save()
        print("📊 Quota: \(usedThisMonth)/\(Self.freeMonthlyLimit) used this month (+\(trackId))")
        return true
    }

    /// TestFlight reset: wipe this month's quota only (Keychain). Does not
    /// touch StoreKit. Also clears the onboarding-completed flag.
    func resetQuotaForTesting() {
        store.clear()
        month = Self.monthString(for: now())
        usedThisMonth = 0
        countedTrackIds = []
        save()
        defaults.set(false, forKey: Self.onboardingCompletedKey)
        // Drop legacy daily keys if somehow still present.
        defaults.removeObject(forKey: legacyCountKey)
        defaults.removeObject(forKey: legacyDateKey)
        print("📊 Quota: TestFlight reset")
    }

    /// Mark onboarding completed (set when a music source first connects).
    func markOnboardingCompleted() {
        defaults.set(true, forKey: Self.onboardingCompletedKey)
    }

    // MARK: - Private

    private func resetIfNewMonth() {
        let current = Self.monthString(for: now())
        if month != current {
            month = current
            usedThisMonth = 0
            countedTrackIds = []
            save()
            print("📊 Quota: new month, counter reset")
        }
    }

    private func load() {
        if let stored = store.load() {
            month = stored.month
            usedThisMonth = stored.count
            countedTrackIds = Set(stored.trackIds)
            return
        }
        // One-time migration from the old daily UserDefaults counter.
        let legacyCount = defaults.integer(forKey: legacyCountKey)
        let current = Self.monthString(for: now())
        if let legacyDay = defaults.string(forKey: legacyDateKey),
           legacyDay.hasPrefix(current) {
            usedThisMonth = min(legacyCount, Self.freeMonthlyLimit)
        } else {
            usedThisMonth = 0
        }
        countedTrackIds = []
        month = current
        save()
        defaults.removeObject(forKey: legacyCountKey)
        defaults.removeObject(forKey: legacyDateKey)
    }

    private func save() {
        store.save(StoredQuota(
            month: month,
            count: usedThisMonth,
            trackIds: Array(countedTrackIds)
        ))
    }

    static func monthString(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        f.timeZone = .current
        return f.string(from: date)
    }
}
