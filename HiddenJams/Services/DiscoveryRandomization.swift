//
//  DiscoveryRandomization.swift
//  HiddenJams
//
//  The anti-determinism engine. Previously the pipeline ended with
//  `.sorted { $0.totalScore > $1.totalScore }` + `.prefix(n)`, which meant
//  every user who picked the same genre got the same songs in the same
//  order, every time. These helpers replace fixed ranking with weighted
//  random sampling: quality still matters (higher scores win more often)
//  but no session is ever a repeat.
//

import Foundation

enum DiscoveryRandomization {
    /// Weighted random sampling WITHOUT replacement (sequential lottery).
    /// Each pick selects an item with probability proportional to its
    /// weight; picked items are removed before the next draw.
    /// - Parameters:
    ///   - items: candidate pool
    ///   - count: how many to draw
    ///   - weight: non-negative weight per item (higher = more likely)
    /// - Returns: drawn items in draw order (already randomized)
    static func weightedSample<T>(
        _ items: [T],
        count: Int,
        weight: (T) -> Double
    ) -> [T] {
        guard !items.isEmpty, count > 0 else { return [] }
        var pool = items
        var result: [T] = []
        result.reserveCapacity(min(count, pool.count))

        for _ in 0..<min(count, pool.count) {
            let weights = pool.map { max(weight($0), 0.0001) }
            let total = weights.reduce(0, +)
            var roll = Double.random(in: 0..<total)
            var pickIndex = pool.count - 1
            for (i, w) in weights.enumerated() {
                roll -= w
                if roll <= 0 {
                    pickIndex = i
                    break
                }
            }
            result.append(pool.remove(at: pickIndex))
        }
        return result
    }

    /// Draws `count` items with probability proportional to each item's
    /// weight, emphasizing top weights with an exponent while guaranteeing
    /// every item a non-zero chance. Use for score-ranked pools where the
    /// best items should usually win but never always.
    static func weightedSampleByScore<T>(
        _ items: [T],
        count: Int,
        score: (T) -> Double,
        emphasis: Double = 2.0,
        floor: Double = 0.05
    ) -> [T] {
        weightedSample(items, count: count) {
            pow(max(score($0), floor), emphasis)
        }
    }
}
