//
//  TestFlightTools.swift
//  HiddenJams
//
//  TestFlight / DEBUG-only helpers. Never shown in App Store builds
//  (receipt file is "receipt", not "sandboxReceipt").
//

import Foundation

enum TestFlightTools {
    /// True in DEBUG builds, or when the app was installed via TestFlight
    /// (sandbox receipt). False for App Store production builds.
    static var showsDebugTools: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// Resets discovery quota, onboarding-completed flag, and no-repeat /
    /// seen history. Does not touch StoreKit entitlements or music logins.
    @MainActor
    static func resetDiscoveryState(discovery: EnhancedHiddenGemsDiscovery? = nil) {
        DiscoveryQuotaManager.shared.resetQuotaForTesting()
        DiscoveryHistoryManager.shared.clearHistory()
        DiscoverySessionMemory.clear()
        discovery?.resetSessionMemoryForTesting()
    }
}
