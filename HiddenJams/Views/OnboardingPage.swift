import SwiftUI

struct OnboardingPage: View {
    let item: OnboardingItem
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: item.systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(Theme.Colors.gemGold)
                .padding(.bottom, 24)
            
            Text(item.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text(item.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}
