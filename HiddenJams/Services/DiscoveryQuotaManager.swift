//
//  DiscoveryQuotaManager.swift
//  HiddenJams
//
//  Free tier: 50 discovered tracks per calendar month (resets on the 1st,
//  local time). Pro (active $1.99/mo subscription): unlimited.
//
//  The count + month are stored in the Keychain (this device only, not
//  synced) so deleting and reinstalling the app doesn't reset the quota.
//

import Foundation
import Combine
import Security

@MainActor
final class DiscoveryQuotaManager: ObservableObject {
    static let shared = DiscoveryQuotaManager()

    /// Free tracks per calendar month.
    static let freeMonthlyLimit = 50

    // Keychain item
    private let keychainService = "com.chris.GettingStarted.HiddenJams.quota"
    private let keychainAccount = "monthlyDiscovery"

    // Legacy UserDefaults keys (daily quota, builds ≤ 82) — migrated once.
    private let legacyCountKey = "hj.dailyDiscoveryCount"
    private let legacyDateKey = "hj.dailyDiscoveryDate"

    @Published private(set) var usedThisMonth: Int = 0
    private var month: String = ""

    private init() {
        load()
        resetIfNewMonth()
    }

    // MARK: - Public

    /// True if the user may discover more tracks right now.
    var canDiscover: Bool {
        if UserProfileManager.shared.isPremium { return true }
        resetIfNewMonth()
        return usedThisMonth < Self.freeMonthlyLimit
    }

    /// Tracks remaining for free users this month. Nil for Pro (unlimited).
    var remainingThisMonth: Int? {
        if UserProfileManager.shared.isPremium { return nil }
        resetIfNewMonth()
        return max(0, Self.freeMonthlyLimit - usedThisMonth)
    }

    /// Record tracks served. Call with the number of new tracks added to the queue.
    func recordDiscovered(count: Int) {
        guard count > 0 else { return }
        resetIfNewMonth()
        usedThisMonth += count
        save()
        print("📊 Quota: \(usedThisMonth)/\(Self.freeMonthlyLimit) used this month")
    }

    // MARK: - Private

    private func resetIfNewMonth() {
        let current = Self.monthString(for: Date())
        if month != current {
            month = current
            usedThisMonth = 0
            save()
            print("📊 Quota: new month, counter reset")
        }
    }

    private func load() {
        if let data = keychainRead(),
           let stored = try? JSONDecoder().decode(StoredQuota.self, from: data) {
            month = stored.month
            usedThisMonth = stored.count
            return
        }
        // One-time migration from the old daily UserDefaults counter.
        let defaults = UserDefaults.standard
        let legacyCount = defaults.integer(forKey: legacyCountKey)
        let current = Self.monthString(for: Date())
        if let legacyDay = defaults.string(forKey: legacyDateKey),
           legacyDay.hasPrefix(current) {
            usedThisMonth = legacyCount
        } else {
            usedThisMonth = 0
        }
        month = current
        save()
        defaults.removeObject(forKey: legacyCountKey)
        defaults.removeObject(forKey: legacyDateKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(StoredQuota(month: month, count: usedThisMonth)) else { return }
        keychainWrite(data)
    }

    private struct StoredQuota: Codable {
        let month: String
        let count: Int
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private func keychainRead() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func keychainWrite(_ data: Data) {
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            attrs.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { print("⚠️ Quota keychain add failed: \(addStatus)") }
        } else if status != errSecSuccess {
            print("⚠️ Quota keychain update failed: \(status)")
        }
    }

    private static func monthString(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        f.timeZone = .current
        return f.string(from: date)
    }
}
