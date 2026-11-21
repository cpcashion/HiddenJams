//
//  MusicFactsService.swift
//  HiddenJams
//
//  Supplies the music facts shown while we dig. Build 88 feedback: facts
//  only, no quiz questions. The Open Trivia Database feed (which produced
//  "Which of these songs…? ✓ Answer" items) is gone; every fact now comes
//  from the curated, source-checked MusicFactsDatabase.
//

import Foundation
import Combine

class MusicFactsService: ObservableObject {
    @Published var facts: [String] = []

    /// Keys used by earlier builds to cache the trivia feed. Cleared so no
    /// cached quiz item can ever be shown again.
    private static let legacyCacheKeys = ["cachedMusicFacts", "cachedMusicFactsTimestamp"]

    init() {
        facts = MusicFactsDatabase.getShuffledFacts()
    }

    /// Kept for the app's launch task: drops the old trivia cache and
    /// reloads the curated facts.
    func fetchMusicFacts() async {
        for key in Self.legacyCacheKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let curated = MusicFactsDatabase.getShuffledFacts()
        await MainActor.run {
            facts = curated
        }
    }
}
