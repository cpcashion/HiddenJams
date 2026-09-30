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
                                    .background(Theme.Colors.textPrimary.opacity(0.1))
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
                                    .background(Theme.Colors.textPrimary.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    
                    ScrollView {
                        FlowLayout(spacing: 8) {
                            // Combine top genres and common genres, removing case-insensitive duplicates
                            let allGenres = Array(Set((commonGenres + topGenres).map { $0.lowercased() })).sorted()
                            // Distinct neon color per selected genre — stable
                            // across launches (hash of the genre name), so the
                            // same genre always wears the same color.
                            let genreColorMap = Theme.Colors.genreColors(for: Array(selectedGenres))

                            ForEach(allGenres, id: \.self) { genre in
                                let isSelected = selectedGenres.contains(genre)

                                Button(action: {
                                    toggleGenre(genre)
                                }) {
                                    GenrePillContent(
                                        genre: genre,
                                        isSelected: isSelected,
                                        pillColor: genreColorMap[genre.lowercased()] ?? Theme.Colors.gemGold
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
                                .foregroundColor(Theme.Colors.buttonText)
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

// MARK: - Genre Pill with per-genre neon color

struct GenrePillContent: View {
    let genre: String
    let isSelected: Bool
    /// The genre's own neon color (from Theme.Colors.genreColors — distinct
    /// per selected genre, stable across launches).
    let pillColor: Color

    var body: some View {
        Text(genre.capitalized)
            .font(Theme.Typography.body2)
            .fontWeight(isSelected ? .semibold : .medium)
            .foregroundColor(isSelected ? Theme.Colors.textOnGenreColor(pillColor) : Theme.Colors.textSecondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(isSelected ? pillColor : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? pillColor : Theme.Colors.textPrimary.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .shadow(color: isSelected ? pillColor.opacity(0.45) : .clear, radius: 8, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

// FlowLayout is now in Views/Components/FlowLayout.swift
