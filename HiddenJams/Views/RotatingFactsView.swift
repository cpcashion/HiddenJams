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
                // Whole fact at once (no typewriter) with a quick
                // blur-slide spring; hold time scales with length.
                ZStack(alignment: .topLeading) {
                    Text(shuffledFacts[currentIndex])
                        .font(Theme.Typography.body2)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .id(key)
                        .transition(.factSwap)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 60, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .fill(Theme.Colors.textPrimary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.textPrimary.opacity(0.05), lineWidth: 1)
        )
        .onAppear {
            // Load and shuffle facts on each appearance
            loadAndShuffleFacts()
        }
        .task(id: key) {
            guard !shuffledFacts.isEmpty else { return }
            #if DEBUG
            if OnboardingParityFixtures.factsPinned { return }
            #endif
            let fact = shuffledFacts[currentIndex]
            try? await Task.sleep(nanoseconds: UInt64(Self.holdSeconds(for: fact) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            trackShownFact(fact)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                currentIndex = (currentIndex + 1) % shuffledFacts.count
                key = UUID().uuidString
            }
        }
    }

    /// Reading time: ~30 characters a second plus a beat, 2.2–4.8s.
    /// (Earlier builds typed each fact at 30ms/char and then held it 4s,
    /// about 6–8s per fact.)
    static func holdSeconds(for fact: String) -> Double {
        min(4.8, max(2.2, 0.8 + Double(fact.count) / 30))
    }

    /// Load facts from service and shuffle, excluding recently shown ones
    private func loadAndShuffleFacts() {
        #if DEBUG
        if let pinned = OnboardingParityFixtures.factsPin {
            shuffledFacts = pinned
            currentIndex = 0
            key = "pinned"
            return
        }
        #endif
        let allFacts = factsService.facts
        
        guard !allFacts.isEmpty else {
            // Fallback to local database if service hasn't loaded yet
            shuffledFacts = MusicFactsDatabase.getShuffledFacts()
            key = UUID().uuidString
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
        key = UUID().uuidString   // (re)starts the rotation task
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

private struct FactBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// New fact rises in from below out of a blur; the old one lifts away.
    static var factSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 14))
                .combined(with: .modifier(active: FactBlur(radius: 6), identity: FactBlur(radius: 0))),
            removal: .opacity
                .combined(with: .offset(y: -12))
                .combined(with: .modifier(active: FactBlur(radius: 4), identity: FactBlur(radius: 0)))
        )
    }
}
