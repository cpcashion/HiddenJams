//
//  ConcertCrowdView.swift
//  HiddenJams
//
//  Animated concert crowd visualization that responds to popularity slider
//  Characters populate the screen like an audience at a concert
//

import SwiftUI

/// A single character in the concert crowd
struct CrowdCharacter: Identifiable {
    let id = UUID()
    let position: CGPoint      // Normalized 0-1 position
    let size: CGFloat          // Character size multiplier
    let delay: Double          // Animation delay
    let symbolIndex: Int       // Which character variant to use
    let hue: Double            // Color variation
}

/// Animated concert crowd that grows based on popularity level
struct ConcertCrowdView: View {
    @Binding var popularityLevel: Double
    
    // Pre-computed character positions for smooth animations
    @State private var characters: [CrowdCharacter] = []
    
    // Maximum characters we can show
    private let maxCharacters = 80
    
    // Character symbols to use (placeholders - will be replaced with custom art)
    private let characterSymbols = [
        "person.fill",
        "figure.arms.open",
        "figure.wave",
        "figure.stand",
        "person.crop.circle.fill"
    ]
    
    // Use screen bounds directly to avoid GeometryReader layout thrashing
    private var screenSize: CGSize {
        UIScreen.main.bounds.size
    }
    
    var body: some View {
        ZStack {
            // Stage area at bottom
            stageGradient
            
            // Crowd characters - use screen size directly (no GeometryReader!)
            ForEach(Array(visibleCharacters.enumerated()), id: \.element.id) { index, character in
                characterView(character, in: screenSize, index: index)
            }
        }
        .onAppear {
            generateCharacters()
        }
    }
    
    // MARK: - Stage Background
    
    private var stageGradient: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.purple.opacity(0.1),
                Color.purple.opacity(0.2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Visible Characters
    
    /// Characters that should be visible based on current popularity level
    private var visibleCharacters: [CrowdCharacter] {
        let count = crowdSize
        return Array(characters.prefix(count))
    }
    
    /// Number of visible characters based on popularity
    private var crowdSize: Int {
        let minCrowd = 5
        let maxCrowd = maxCharacters
        return minCrowd + Int(Double(maxCrowd - minCrowd) * popularityLevel)
    }
    
    // MARK: - Character View
    
    private func characterView(_ character: CrowdCharacter, in size: CGSize, index: Int) -> some View {
        let isVisible = index < crowdSize
        let x = character.position.x * size.width
        let y = characterY(for: character, in: size)
        
        return Image(systemName: characterSymbols[character.symbolIndex % characterSymbols.count])
            .font(.system(size: 24 * character.size))
            .foregroundStyle(characterColor(for: character))
            .position(x: x, y: y)
            .opacity(isVisible ? opacityForCharacter(character, in: size) : 0)
            .scaleEffect(isVisible ? 1.0 : 0.3)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.7)
                    .delay(character.delay * 0.05),
                value: isVisible
            )
    }
    
    /// Y position - characters crowd toward the bottom (stage front)
    private func characterY(for character: CrowdCharacter, in size: CGSize) -> CGFloat {
        // Characters positioned in bottom 40% of screen
        let stageTop = size.height * 0.6
        let stageBottom = size.height * 0.95
        return stageTop + (character.position.y * (stageBottom - stageTop))
    }
    
    /// Characters at front (bottom) are more visible
    private func opacityForCharacter(_ character: CrowdCharacter, in size: CGSize) -> Double {
        // Characters nearer the front (higher Y) are more visible
        let frontness = character.position.y
        return 0.4 + (frontness * 0.6)
    }
    
    /// Color based on character hue
    private func characterColor(for character: CrowdCharacter) -> Color {
        Color(
            hue: character.hue,
            saturation: 0.6,
            brightness: 0.9
        )
    }
    
    // MARK: - Character Generation
    
    /// Generate deterministic character positions
    private func generateCharacters() {
        var chars: [CrowdCharacter] = []
        
        for i in 0..<maxCharacters {
            // Use deterministic "random" positions based on index
            let seed = Double(i)
            
            let character = CrowdCharacter(
                position: CGPoint(
                    x: pseudoRandom(seed: seed * 1.1, min: 0.05, max: 0.95),
                    y: pseudoRandom(seed: seed * 2.3, min: 0.0, max: 1.0)
                ),
                size: CGFloat(pseudoRandom(seed: seed * 3.7, min: 0.6, max: 1.2)),
                delay: Double(i) * 0.02,
                symbolIndex: Int(seed) % characterSymbols.count,
                hue: pseudoRandom(seed: seed * 5.1, min: 0.7, max: 0.9) // Purple-ish range
            )
            chars.append(character)
        }
        
        // Sort by Y position so front characters render on top
        characters = chars.sorted { $0.position.y < $1.position.y }
    }
    
    /// Deterministic pseudo-random number generator
    private func pseudoRandom(seed: Double, min: Double, max: Double) -> Double {
        let x = sin(seed * 12.9898 + 78.233) * 43758.5453
        let normalized = x - floor(x) // 0-1 range
        return min + normalized * (max - min)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            ConcertCrowdView(popularityLevel: .constant(0.7))
            
            Slider(value: .constant(0.7), in: 0...1)
                .padding()
        }
    }
}
