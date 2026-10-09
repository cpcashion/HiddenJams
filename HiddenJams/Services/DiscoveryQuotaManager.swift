//
//  DiscoveryQuotaManager.swift
//  HiddenJams
//
//  Free tier: 20 discovered tracks per day (resets at local midnight).
//  Pro (paid subscription): unlimited.
//

import Foundation
import Combine

@MainActor
final class DiscoveryQuotaManager: ObservableObject {
    static let shared = DiscoveryQuotaManager()

    /// Free tracks per day.
    static let freeDailyLimit = 20

    private let countKey = "hj.dailyDiscoveryCount"
    private let dateKey = "hj.dailyDiscoveryDate"

    @Published private(set) var usedToday: Int = 0

    /// Session-scoped snooze: "Not now" on the paywall lets the user keep
    /// discovering until the app restarts. Not persisted — the paywall
    /// returns on next launch.
    var paywallSnoozed = false

    private init() {
        resetIfNewDay()
        usedToday = UserDefaults.standard.integer(forKey: countKey)
    }

    // MARK: - Public

    /// True if the user may discover more tracks right now.
    var canDiscover: Bool {
        if UserProfileManager.shared.isPremium { return true }
        if paywallSnoozed { return true }
        resetIfNewDay()
        return usedToday < Self.freeDailyLimit
    }

    /// Tracks remaining for free users today. Nil for Pro (unlimited).
    var remainingToday: Int? {
        if UserProfileManager.shared.isPremium { return nil }
        resetIfNewDay()
        return max(0, Self.freeDailyLimit - usedToday)
    }

    /// Record tracks served. Call with the number of new tracks added to the queue.
    func recordDiscovered(count: Int) {
        guard count > 0 else { return }
        resetIfNewDay()
        usedToday += count
        UserDefaults.standard.set(usedToday, forKey: countKey)
        print("📊 Quota: \(usedToday)/\(Self.freeDailyLimit) used today")
    }

    // MARK: - Private

    private func resetIfNewDay() {
        let today = Self.dayString(for: Date())
        let stored = UserDefaults.standard.string(forKey: dateKey)
        if stored != today {
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(0, forKey: countKey)
            usedToday = 0
            print("📊 Quota: new day, counter reset")
        }
    }

    private static func dayString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}
