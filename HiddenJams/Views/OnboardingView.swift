import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    
    let items: [OnboardingItem] = [
        OnboardingItem(
            title: "Uncover Hidden Gems",
            description: "Dig deep for unheard tracks or stay mainstream. You control the crowd to find your perfect sound.",
            systemImage: "sparkles"
        ),
        OnboardingItem(
            title: "Swipe to Playlist",
            description: "Swipe right to save. We automatically build a \"Hidden Gems\" playlist in your Spotify library with every like.",
            systemImage: "hand.draw.fill"
        ),
        OnboardingItem(
            title: "Connect Spotify",
            description: "Link your account to start discovering and saving music instantly.",
            systemImage: "music.note" // "Spotify-like" generic
        )
    ]
    
    var body: some View {
        ZStack {
            // Background
            Theme.Colors.backgroundGradient
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                TabView(selection: $currentPage) {
                    ForEach(0..<items.count, id: \.self) { index in
                        OnboardingPage(item: items[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 520) 
                .padding(.bottom, 40) // Move dots lower
                
                Spacer()
                
                Button(action: {
                    if currentPage < items.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        // Connect with Spotify
                        authManager.startAuth()
                    }
                }) {
                    HStack {
                        if currentPage == items.count - 1 {
                            // Since we don't have a Spotify logo asset, we'll use a generic icon or the one from LoginView if compatible
                            Image(systemName: "music.note") 
                        }
                        Text(currentPage < items.count - 1 ? "Next" : "Connect with Spotify")
                            .font(.headline)
                    }
                    .foregroundStyle(Theme.Colors.buttonText) // Dark grey text
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            currentPage < items.count - 1 ? 
                            AnyShapeStyle(Theme.Colors.gemGold) : 
                            AnyShapeStyle(Theme.Colors.primaryGradient)
                        )
                        .cornerRadius(12)
                        .shadow(color: Theme.Colors.gemGold.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
    }
    
    private func completeOnboarding() {
        withAnimation {
            isPresented = false
        }
    }
}
