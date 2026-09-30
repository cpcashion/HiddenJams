//
//  GenreColorTests.swift
//  HiddenJamsTests
//
//  Regression tests for the build-22 freeze: Theme.Colors.genreColors used an
//  UNBOUNDED collision probe over a 10-color palette, so selecting an 11th
//  genre spun the main thread forever (freeze -> watchdog kill -> "crash").
//  The probe is now bounded by the palette size; these tests pin that.
//

import Testing
import Foundation
import SwiftUI
@testable import HiddenJams

struct GenreColorTests {

    /// Color -> comparable key (RGBA rounded), since SwiftUI.Color is not Equatable.
    private func rgbaKey(_ color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f,%.3f,%.3f,%.3f", r, g, b, a)
    }

    private func colorMap(_ genres: [String]) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: Theme.Colors.genreColors(for: genres).map {
                ($0.key, rgbaKey($0.value))
            }
        )
    }

    // MARK: - The build-22 freeze

    @Test("genreColors terminates with more genres than palette colors")
    func terminatesBeyondPaletteSize() {
        // 50 distinct genres — build 22 hung forever on the 11th.
        // If the probe is unbounded again, this test never finishes (CI times out).
        let genres = (0..<50).map { "test genre \($0)" }
        let assigned = Theme.Colors.genreColors(for: genres)
        #expect(assigned.count == 50)
    }

    @Test("genreColors terminates when every genre hashes alike")
    func terminatesUnderHashCollisionStorm() {
        // Adversarial: many genres, tiny effective space — the probe must
        // still give up after one full cycle, not spin.
        let genres = (0..<100).map { "genre-\($0)-collision" }
        let assigned = Theme.Colors.genreColors(for: genres)
        #expect(assigned.count == 100)
    }

    // MARK: - Distinctness where possible

    @Test("up to 10 genres get all-different colors")
    func distinctUpToPaletteSize() {
        let genres = ["drum and bass", "hip-hop", "reggae", "jazz", "rock",
                      "classical", "ambient", "funk", "soul", "techno"]
        let keys = Set(colorMap(genres).values)
        #expect(keys.count == 10)
    }

    // MARK: - Stability

    @Test("same genre keeps its color regardless of selection order")
    func stableAcrossSelectionOrder() {
        let a = colorMap(["jazz", "rock", "hip-hop"])
        let b = colorMap(["hip-hop", "jazz", "rock"])
        #expect(a == b)
    }

    @Test("same genre keeps its color across separate calls")
    func stableAcrossCalls() {
        let first = colorMap(["drum and bass", "reggae"])
        let second = colorMap(["drum and bass", "reggae"])
        #expect(first == second)
    }

    @Test("duplicate and mixed-case genres dedupe to one entry")
    func dedupesCaseAndDuplicates() {
        let assigned = Theme.Colors.genreColors(for: ["Jazz", "jazz", "JAZZ", "rock"])
        #expect(assigned.count == 2)
        #expect(assigned["jazz"] != nil)
    }
}
