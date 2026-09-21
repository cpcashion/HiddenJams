//
//  DiscoveryLoadingView.swift
//  HiddenJams
//
//  Minimalist loading experience for discovery
//

import SwiftUI

struct DiscoveryLoadingView: View {
    let progressMessage: String
    
    // Animation states
    @State private var messageIndex = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var iconOpacity: Double = 0.6
    
    private let searchMessages = [
        "Scanning underground catalogs...",
        "Finding hidden tracks...",
        "Matching your taste profile...",
        "Discovering rare gems...",
        "Searching the depths...",
        "Uncovering musical treasures...",
        "Curating your playlist..."
    ]
    
    var body: some View {
        ZStack {
            // Clean dark background
            Color.black.ignoresSafeArea()
            
            // Subtle ambient glow
            RadialGradient(
                colors: [
                    Theme.Colors.gemGold.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 250
            )
            .scaleEffect(pulseScale)
            
            // Main content
            VStack(spacing: 32) {
                Spacer()
                
                // Simple pulsing icon
                Image(systemName: "sparkle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Theme.Colors.gemGold.opacity(iconOpacity))
                    .scaleEffect(pulseScale)
                
                // Status text
                VStack(spacing: 12) {
                    Text("Discovering")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(searchMessages[messageIndex])
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .animation(.easeInOut(duration: 0.4), value: messageIndex)
                }
                
                Spacer()
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Message rotation
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                messageIndex = (messageIndex + 1) % searchMessages.count
            }
        }
        
        // Subtle breathing pulse
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.08
            iconOpacity = 0.9
        }
    }
}

#Preview {
    DiscoveryLoadingView(progressMessage: "Searching Micro-Genres...")
}
