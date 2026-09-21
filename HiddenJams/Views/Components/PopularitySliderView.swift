//
//  PopularitySliderView.swift
//  HiddenJams
//
//  Custom slider for controlling music discovery popularity threshold
//

import SwiftUI

/// Custom slider with haptic feedback and styled endpoints
struct PopularitySliderView: View {
    @Binding var popularityLevel: Double
    @ObservedObject var settings: PopularitySliderSettings
    
    // Haptic feedback generator
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    
    // Track last haptic position to avoid too many feedbacks
    @State private var lastHapticValue: Double = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // Level indicator
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.levelDescription)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.gemGold)

                    Text(settings.levelSubtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.gray)
                }

                Spacer()

                // Followers, not "plays" — Spotify exposes no play counts, so
                // this is the real quantity being filtered on.
                Text("under \(settings.thresholdDescription)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            // Slider with endpoints
            HStack(spacing: 16) {
                // Left endpoint - Deep cuts
                VStack(spacing: 4) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 16))
                        .foregroundColor(popularityLevel < 0.3 ? Theme.Colors.gemGold : .gray.opacity(0.5))
                    Text("Deep")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .frame(width: 40)
                
                // Custom styled slider
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track background
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 8)
                        
                        // Filled track
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Theme.Colors.gemGold.opacity(0.5),
                                        Theme.Colors.gemGold
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * popularityLevel, height: 8)
                        
                        // Thumb
                        Circle()
                            .fill(Theme.Colors.gemGold)
                            .frame(width: 24, height: 24)
                            .shadow(color: Theme.Colors.gemGold.opacity(0.5), radius: 4, x: 0, y: 2)
                            .offset(x: (geometry.size.width - 24) * popularityLevel)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let newValue = min(max(value.location.x / geometry.size.width, 0), 1)
                                        popularityLevel = newValue
                                        settings.popularityLevel = newValue
                                        
                                        // Haptic at intervals
                                        if abs(newValue - lastHapticValue) > 0.1 {
                                            hapticFeedback.impactOccurred()
                                            lastHapticValue = newValue
                                        }
                                    }
                            )
                    }
                }
                .frame(height: 24)
                
                // Right endpoint - Popular
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                        .foregroundColor(popularityLevel > 0.7 ? .orange : .gray.opacity(0.5))
                    Text("Hot")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                }
                .frame(width: 40)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        PopularitySliderView(
            popularityLevel: .constant(0.3),
            settings: PopularitySliderSettings()
        )
        .padding()
    }
}
