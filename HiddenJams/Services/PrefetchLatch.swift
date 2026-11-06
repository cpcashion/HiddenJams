//
//  PrefetchLatch.swift
//  HiddenJams
//
//  Pure gate for continuous discovery prefetch: held while a request is
//  in flight, released on any completion (append / empty / error /
//  exhausted) so an empty result cannot leave the queue permanently
//  stuck with monthly quota remaining.
//

import Foundation

nonisolated enum PrefetchOutcome: Equatable, Sendable {
    case appended(Int)
    case empty
    case exhausted
    case failed
}

nonisolated struct PrefetchLatch: Equatable, Sendable {
    /// Max automatic retries after empty/failed outcomes while quota remains.
    static let maxEmptyRetries = 2

    private(set) var isHeld = false
    private(set) var emptyOrFailedCount = 0

    /// Acquire the latch for a new prefetch. Returns false if already held.
    mutating func begin() -> Bool {
        guard !isHeld else { return false }
        isHeld = true
        return true
    }

    /// Release after a prefetch finishes. Returns true when the caller should
    /// schedule another attempt (empty/failed and under the retry budget).
    @discardableResult
    mutating func finish(_ outcome: PrefetchOutcome) -> Bool {
        isHeld = false
        switch outcome {
        case .appended(let n) where n > 0:
            emptyOrFailedCount = 0
            return false
        case .appended, .empty, .failed:
            emptyOrFailedCount += 1
            return emptyOrFailedCount <= Self.maxEmptyRetries
        case .exhausted:
            emptyOrFailedCount = Self.maxEmptyRetries + 1
            return false
        }
    }

    mutating func reset() {
        isHeld = false
        emptyOrFailedCount = 0
    }
}


/// Monotonic generation for discovery runs. Non-append (genre switch /
/// fresh Discover) bumps the token; append/prefetch reuses it. Completions
/// whose token no longer matches are dropped so a stale prefetch cannot
/// append the previous genre into a new deck.
nonisolated struct DiscoveryGenerationToken: Equatable, Sendable {
    private(set) var value: UInt64 = 0

    mutating func begin(appendResults: Bool) -> UInt64 {
        if !appendResults {
            value &+= 1
        }
        return value
    }

    func isStale(_ generation: UInt64) -> Bool {
        generation != value
    }
}


/// Call-site contract for monthly quota (findings 6 + 7): count a deck track
/// only when its preview is ready AND StoreKit entitlement has resolved once.
nonisolated enum DiscoveryTrackCountPolicy {
    static func allowsConsume(previewReady: Bool, entitlementResolved: Bool) -> Bool {
        previewReady && entitlementResolved
    }
}
