# Spotify Hidden Gems - iOS App

A beautiful SwiftUI app that uses AI to analyze your complete Spotify listening history and discovers hidden gems (songs with <1,000 streams) from across Spotify's global catalog.

## 🎯 Features

- **AI-Powered Profile Analysis**: Analyzes ALL your liked songs and playlist tracks
- **Complete Library Scan**: Processes thousands of songs with progress tracking
- **Global Discovery**: Finds hidden gems from Spotify's entire catalog
- **Smart Matching**: AI scoring algorithm matches songs to your taste
- **Beautiful UI**: Premium design with glassmorphism and smooth animations
- **Detailed Insights**: Visualize your audio features, genres, artists, and moods

## 📋 Setup Instructions

### 1. Spotify Developer Credentials

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Create a new app
3. Note your **Client ID**
4. Add redirect URI: `spotifyhiddengems://callback`
5. Open `SpotifyAuthManager.swift` and replace:
   ```swift
   private let clientId = "YOUR_CLIENT_ID_HERE"
   ```

### 2. Open in Xcode

```bash
cd SpotifyHiddenGems
open -a Xcode .
```

### 3. Configure Project

1. In Xcode, select the project in the navigator
2. Under "Signing & Capabilities", select your team
3. Build and run on your device or simulator

## 🏗️ Architecture

</ File Structure
```
SpotifyHiddenGems/
├── Models/
│   ├── SpotifyModels.swift       # API response models
│   └── ListeningProfile.swift    # AI profile data structures
├── Services/
│   ├── SpotifyAuthManager.swift  # OAuth 2.0 PKCE flow
│   ├── SpotifyAPIService.swift   # Spotify Web API client
│   ├── AIProfileAnalyzer.swift   # Complete library analyzer
│   └── HiddenGemsDiscovery.swift # Global discovery engine
├── Views/
│   ├── ContentView.swift         # Root coordinator
│   ├── LoginView.swift           # Authentication screen
│   ├── DashboardView.swift       # Main hub
│   ├── DiscoveryView.swift       # Hidden gems feed
│   └── ProfileView.swift         # Listening profile viz
└── Utils/
    └── Theme.swift               # Design system
```

### Key Components

**SpotifyAPIService**: Handles paginated fetching of ALL liked songs and playlist tracks

**AIProfileAnalyzer**: 
- Analyzes complete music library (can handle thousands of tracks)
- Calculates audio feature averages and ranges
- Builds genre weights from top artists
- Creates artist influence profiles
- Analyzes mood patterns (happy, sad, energetic, calm, party, focused)
- Tracks decade distribution

**HiddenGemsDiscovery**:
- Generates diverse seed combinations from profile
- Queries Spotify's global catalog with `max_popularity=20`
- Scores tracks using AI similarity algorithm
- Filters out tracks user already knows
- Generates "Why this?" explanations

## 🎨 Design System

- **Theme**: Spotify-inspired dark mode with vibrant accents
- **Colors**: Spotify green (#1DB954), premium gradients
- **Effects**: Glassmorphism, smooth animations, glow shadows
- **Typography**: Rounded San Francisco font system

## 🚀 Future Enhancements

### Planned Features
- [ ] HuggingFace MIRFLEX integration for deep musical analysis
- [ ] Wav2Vec2 embeddings for audio similarity
- [ ] Third-party stream count API (SpotScraper/Apify)
- [ ] Spotify preview player integration
- [ ] Save discovered gems to playlists
- [ ] Share hidden gems with friends
- [ ] Weekly discovery notifications

## 📝 Notes

- **Privacy**: All analysis happens on-device (except Spotify API calls)
- **Performance**: Handles large libraries with batched processing
- **Stream Counts**: Currently uses popularity score (<20). Can integrate third-party API for precise counts
- **AI Models**: Currently uses statistical analysis. HuggingFace models planned for v2

## 🐛 Known Limitations

1. Spotify API doesn't provide actual stream counts (using popularity as proxy)
2. HuggingFace model integration pending (using audio features for now)
3. Preview player not yet implemented
4. Rate limiting on large libraries (Spotify API limits)

## 📄 License

MIT License - feel free to use and modify!

## 🙏 Credits

Built with:
- SwiftUI
- Spotify Web API
- Love for underground music 🎵
