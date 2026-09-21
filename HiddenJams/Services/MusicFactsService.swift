//
//  MusicFactsService.swift
//  HiddenJams
//
//  Service for fetching and caching music facts from Open Trivia Database
//

import Foundation
import Combine
import UIKit

class MusicFactsService: ObservableObject {
    @Published var facts: [String] = []
    
    private let cacheKey = "cachedMusicFacts"
    private let cacheTimestampKey = "cachedMusicFactsTimestamp"
    private let cacheExpirationDays = 7
    
    init() {
        // Load cached facts immediately
        facts = getCachedFacts()
    }
    
    /// Fetch music trivia from Open Trivia Database and combine with local facts
    func fetchMusicFacts() async {
        // Check if cache is still valid
        if isCacheValid() {
            print("📚 Using cached music facts")
            await MainActor.run {
                facts = getCachedFacts()
            }
            return
        }
        
        print("🌐 Fetching fresh music trivia from API...")
        
        // Fetch from API
        let apiFacts = await fetchFromAPI()
        
        // Combine API facts with local database
        let combinedFacts = combineAndShuffleFacts(apiFacts: apiFacts, localFacts: MusicFactsDatabase.allFacts)
        
        // Cache the combined facts
        saveCachedFacts(combinedFacts)
        
        await MainActor.run {
            facts = combinedFacts
        }
        
        print("✅ Loaded \(combinedFacts.count) total facts (\(apiFacts.count) from API, \(MusicFactsDatabase.allFacts.count) local)")
    }
    
    /// Fetch trivia from Open Trivia Database API
    private func fetchFromAPI() async -> [String] {
        let urlString = "https://opentdb.com/api.php?amount=50&category=12&type=multiple"
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid API URL")
            return []
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(TriviaResponse.self, from: data)
            
            // Format trivia questions as facts
            let formattedFacts = response.results.map { trivia in
                formatTriviaAsFact(trivia)
            }
            
            return formattedFacts
        } catch {
            print("❌ Failed to fetch trivia from API: \(error)")
            return []
        }
    }
    
    /// Format a trivia question and answer as a readable fact
    private func formatTriviaAsFact(_ trivia: TriviaQuestion) -> String {
        // Decode HTML entities
        let question = trivia.question.htmlDecoded
        let answer = trivia.correctAnswer.htmlDecoded
        
        // Format as: "Question? ✓ Answer"
        // Or if the question doesn't end with ?, add it
        if question.hasSuffix("?") {
            return "\(question)\n✓ \(answer)"
        } else {
            return "\(question)?\n✓ \(answer)"
        }
    }
    
    /// Combine API facts with local facts and shuffle
    private func combineAndShuffleFacts(apiFacts: [String], localFacts: [String]) -> [String] {
        var combined = apiFacts + localFacts
        combined.shuffle()
        return combined
    }
    
    // MARK: - Caching
    
    /// Check if cached facts are still valid (within expiration period)
    private func isCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date else {
            return false
        }
        
        let daysSinceCache = Calendar.current.dateComponents([.day], from: timestamp, to: Date()).day ?? 0
        return daysSinceCache < cacheExpirationDays
    }
    
    /// Get cached facts from UserDefaults
    func getCachedFacts() -> [String] {
        if let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let cachedFacts = try? JSONDecoder().decode([String].self, from: cachedData) {
            return cachedFacts
        }
        
        // Fallback to local database if no cache
        return MusicFactsDatabase.getShuffledFacts()
    }
    
    /// Save facts to cache with timestamp
    func saveCachedFacts(_ facts: [String]) {
        if let encoded = try? JSONEncoder().encode(facts) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
        }
    }
}

// MARK: - API Response Models

struct TriviaResponse: Codable {
    let responseCode: Int
    let results: [TriviaQuestion]
    
    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case results
    }
}

struct TriviaQuestion: Codable {
    let category: String
    let type: String
    let difficulty: String
    let question: String
    let correctAnswer: String
    let incorrectAnswers: [String]
    
    enum CodingKeys: String, CodingKey {
        case category, type, difficulty, question
        case correctAnswer = "correct_answer"
        case incorrectAnswers = "incorrect_answers"
    }
}

// MARK: - HTML Decoding Extension

extension String {
    var htmlDecoded: String {
        guard let data = self.data(using: .utf8) else { return self }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return self
        }
        
        return attributedString.string
    }
}
