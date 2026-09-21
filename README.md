# HiddenJams

Discover music that hasn't been heard yet.

HiddenJams is a SwiftUI app for iOS that analyzes your Spotify library and surfaces
genuinely obscure artists — low popularity, small followings, recent releases — instead
of the well-known names recommendation engines usually converge on.

## How it works

Spotify deprecated its Related Artists API, so discovery is assembled from several sources:

| Source           | Role                                       |
| ---------------- | ------------------------------------------ |
| Spotify          | Library analysis, search, playlist creation |
| Last.fm          | Similar artists                             |
| MusicBrainz      | Release verification                        |
| Deezer / iTunes  | Audio previews                              |
| OpenAI           | Taste profiles and match explanations (optional) |

An artist qualifies as a "hidden gem" at popularity < 30, fewer than 10k followers, and a
release within the last 3 months. These thresholds live in `APIConfiguration.Discovery`.

## Project layout

```
HiddenJams/
├── Models/       Data models for Spotify and external APIs
├── Services/     API clients, auth, discovery engine, audio playback
├── Views/        SwiftUI screens and components
├── Utils/        Theme and shared helpers
└── Data/         Static content (music facts)
```

## Getting started

Requires Xcode and an Apple developer account. See [`SETUP.md`](SETUP.md) for API key
configuration — no keys are stored in this repository, and the app reads them at runtime
from a git-ignored `Secrets.plist`, `Info.plist`, or environment variables.

```bash
git clone https://github.com/cpcashion/HiddenJams.git
cd HiddenJams
cp Secrets.example.plist HiddenJams/Secrets.plist   # then fill in your keys
open HiddenJams.xcodeproj
```

## Shipping

[`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) tracks what remains before App Store
submission, including a missing privacy manifest and moving the OpenAI key server-side.

## A note on credentials

An earlier local copy of this project had a live OpenAI key and a Last.fm key written
directly into the source. They were removed before the first push, so they are not in this
repository's history — but any key that has lived in a working copy or been shared in a
zip should be treated as exposed and rotated.

The Spotify client ID in `SpotifyAuthManager.swift` is intentionally public: the app uses
the OAuth 2.0 PKCE flow, which is designed for clients that cannot hold a secret.
