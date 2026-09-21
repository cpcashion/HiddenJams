import SwiftUI
import Combine

struct RotatingFactsView: View {
    @EnvironmentObject var factsService: MusicFactsService
    
    @State private var shuffledFacts: [String] = []
    @State private var currentIndex = 0
    @State private var key: String = UUID().uuidString
    
    private let shownFactsKey = "shownMusicFactsHistory"
    private let maxShownFactsHistory = 50 // Remember last 50 shown facts
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if !shuffledFacts.isEmpty {
                TypewriterText(text: shuffledFacts[currentIndex], key: key) {
                    // Wait 4 seconds then advance
                    Task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        await MainActor.run {
                            withAnimation {
                                // Track this fact as shown
                                trackShownFact(shuffledFacts[currentIndex])
                                
                                currentIndex = (currentIndex + 1) % shuffledFacts.count
                                key = UUID().uuidString
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 60, alignment: .topLeading)
                .id(key)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .onAppear {
            // Load and shuffle facts on each appearance
            loadAndShuffleFacts()
        }
    }
    
    /// Load facts from service and shuffle, excluding recently shown ones
    private func loadAndShuffleFacts() {
        let allFacts = factsService.facts
        
        guard !allFacts.isEmpty else {
            // Fallback to local database if service hasn't loaded yet
            shuffledFacts = MusicFactsDatabase.getShuffledFacts()
            return
        }
        
        // Get recently shown facts
        let shownFacts = getShownFacts()
        
        // Filter out recently shown facts (if we have enough unseen facts)
        var availableFacts = allFacts.filter { !shownFacts.contains($0) }
        
        // If we've shown all facts, reset and use all facts again
        if availableFacts.count < 10 {
            print("🔄 All facts shown, resetting history")
            clearShownFacts()
            availableFacts = allFacts
        }
        
        // Shuffle the available facts
        shuffledFacts = availableFacts.shuffled()
        currentIndex = 0
    }
    
    // MARK: - Persistent Tracking
    
    /// Track a fact as shown
    private func trackShownFact(_ fact: String) {
        var shown = getShownFacts()
        shown.append(fact)
        
        // Keep only the last N shown facts
        if shown.count > maxShownFactsHistory {
            shown = Array(shown.suffix(maxShownFactsHistory))
        }
        
        UserDefaults.standard.set(shown, forKey: shownFactsKey)
    }
    
    /// Get the list of recently shown facts
    private func getShownFacts() -> [String] {
        return UserDefaults.standard.stringArray(forKey: shownFactsKey) ?? []
    }
    
    /// Clear the shown facts history
    private func clearShownFacts() {
        UserDefaults.standard.removeObject(forKey: shownFactsKey)
    }
}

struct TypewriterText: View {
    let text: String
    let key: String
    let onComplete: () -> Void
    
    @State private var displayedText = ""
    
    var body: some View {
        Text(displayedText) // Cursor removed
            .font(Theme.Typography.body2)
            .foregroundColor(Theme.Colors.textSecondary)
            .onAppear {
                displayedText = ""
                animateText()
            }
            .onChange(of: key) { _ in
                displayedText = ""
                animateText()
            }
    }
    
    private func animateText() {
        Task {
            for char in text {
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms per char
                await MainActor.run {
                    displayedText.append(char)
                }
            }
            // Trigger completion
            await MainActor.run {
                onComplete()
            }
        }
    }
}
