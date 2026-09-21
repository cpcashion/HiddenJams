import SwiftUI

struct GenreSelectionView: View {
    @Environment(\.dismiss) var dismiss
    // CHANGED: "selectedGenres" (Positive Selection) instead of "excluded"
    // If empty, we treat it as "No Filter" (All genres allowed)
    @AppStorage("selectedGenres") private var selectedGenresData: Data = Data()
    
    @State private var selectedGenres: Set<String> = []
    
    // Optional: Pass in user's top genres to make it dynamic
    var topGenres: [String] = []
    
    // Common genres to allow filtering
    let commonGenres = [
        "Pop", "Rock", "Hip Hop", "Rap", "Country",
        "R&B", "Electronic", "Dance", "Indie", "Alternative",
        "Classical", "Jazz", "Blues", "Metal", "Punk",
        "Folk", "Reggae", "Soul", "Funk", "Latin", 
        "Reggaeton", "K-Pop", "Anime", "Gospel", "Christian", "Worship",
        "Drum and Bass", "Jungle", "House", "Techno", "Ambient"  // Added electronic sub-genres
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Status
                    VStack(spacing: Theme.Spacing.md) {
                        Text("Customize Your Discovery")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                        
                        Text(statusText)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Control Buttons
                        HStack(spacing: Theme.Spacing.lg) {
                            Button(action: {
                                // Select All (Union of common + top), normalized to lowercase
                                let all = Set((commonGenres + topGenres).map { $0.lowercased() })
                                selectedGenres = all
                            }) {
                                Text("Select All")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                selectedGenres.removeAll()
                            }) {
                                Text("Deselect All")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    
                    ScrollView {
                        FlowLayout(spacing: 8) {
                            // Combine top genres and common genres, removing case-insensitive duplicates
                            let allGenres = Array(Set((commonGenres + topGenres).map { $0.lowercased() })).sorted()
                            let totalCount = allGenres.count
                            
                            ForEach(Array(allGenres.enumerated()), id: \.element) { index, genre in
                                let isSelected = selectedGenres.contains(genre)
                                // Calculate gradient position (0.0 = top-left, 1.0 = bottom-right)
                                let gradientPosition = CGFloat(index) / CGFloat(max(totalCount - 1, 1))
                                
                                Button(action: {
                                    toggleGenre(genre)
                                }) {
                                    GenrePillContent(
                                        genre: genre,
                                        isSelected: isSelected,
                                        gradientPosition: gradientPosition
                                    )
                                }
                            }
                        }
                        .padding(Theme.Spacing.lg)
                        .padding(.bottom, 100) // Space for floating button + glass bar
                    }
                }
                
                // Floating Discover button with gradient fade background
                VStack(spacing: 0) {
                    Spacer()
                    
                    ZStack(alignment: .bottom) {
                        // Gradient fade from transparent to dark (no hard line)
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Theme.Colors.spotifyBlack.opacity(0.3),
                                Theme.Colors.spotifyBlack.opacity(0.7),
                                Theme.Colors.spotifyBlack.opacity(0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        
                        // Apply button
                        Button(action: {
                            saveGenres()
                            dismiss()
                        }) {
                            Text("Apply")
                                .font(Theme.Typography.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 60)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.Colors.spotifyGreen)
                                        .shadow(color: Theme.Colors.spotifyGreen.opacity(0.4), radius: 12, x: 0, y: 6)
                                )
                        }
                        .padding(.bottom, 30)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarHidden(true)
            .onAppear {
                loadGenres()
            }
        }
    }
    
    private var statusText: String {
        if selectedGenres.isEmpty {
            return "No genres selected. Please select at least one."
        } else if selectedGenres.count == Set((commonGenres + topGenres).map { $0.lowercased() }).count {
            return "All genres selected. Maximum variety!"
        } else {
            return "Discovery focused on \(selectedGenres.count) genres."
        }
    }
    
    private func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func loadGenres() {
        if let decoded = try? JSONDecoder().decode(Set<String>.self, from: selectedGenresData) {
            if decoded.isEmpty {
                 // First run or empty: Default to ALL
                 selectAll()
            } else {
                selectedGenres = decoded
            }
        } else {
            // No data: Default to ALL
            selectAll()
        }
    }
    
    private func selectAll() {
        let all = Set((commonGenres + topGenres).map { $0.lowercased() })
        selectedGenres = all
    }
    
    private func saveGenres() {
        if let encoded = try? JSONEncoder().encode(selectedGenres) {
            selectedGenresData = encoded
        }
    }
}

// MARK: - Genre Pill with Position-Based Gradient

struct GenrePillContent: View {
    let genre: String
    let isSelected: Bool
    let gradientPosition: CGFloat
    
    // Gold gradient colors (dark → medium → light)
    private let gradientColors: [Color] = [
        Color(hex: "B45309"),  // Dark amber
        Color(hex: "D97706"),  // Amber
        Color(hex: "F59E0B"),  // Gold
        Color(hex: "FBBF24"),  // Light gold
    ]
    
    private var pillColor: Color {
        // Interpolate through the gradient based on position
        let segments = gradientColors.count - 1
        let scaledPosition = gradientPosition * CGFloat(segments)
        let lowerIndex = Int(scaledPosition)
        let upperIndex = min(lowerIndex + 1, segments)
        let fraction = scaledPosition - CGFloat(lowerIndex)
        
        return interpolateColor(
            from: gradientColors[lowerIndex],
            to: gradientColors[upperIndex],
            fraction: fraction
        )
    }
    
    var body: some View {
        Text(genre.capitalized)
            .font(Theme.Typography.body2)
            .fontWeight(isSelected ? .semibold : .medium)
            .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(isSelected ? pillColor.opacity(0.6) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? pillColor : Color.white.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
    
    private func interpolateColor(from: Color, to: Color, fraction: CGFloat) -> Color {
        let fromComponents = UIColor(from).cgColor.components ?? [0, 0, 0, 1]
        let toComponents = UIColor(to).cgColor.components ?? [0, 0, 0, 1]
        
        let r = fromComponents[0] + (toComponents[0] - fromComponents[0]) * fraction
        let g = fromComponents[1] + (toComponents[1] - fromComponents[1]) * fraction
        let b = fromComponents[2] + (toComponents[2] - fromComponents[2]) * fraction
        
        return Color(red: r, green: g, blue: b)
    }
}

// FlowLayout is now in Views/Components/FlowLayout.swift
