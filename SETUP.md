# HiddenJams — Setup

## 1. Configure API keys

No keys are stored in this repository. The app resolves each key at runtime, in order:

1. `Secrets.plist` in the app bundle (git-ignored)
2. the app's `Info.plist` (handy for CI / xcconfig-driven builds)
3. an environment variable (handy for running from Xcode)

If a key is missing, the service that needs it throws a clear "not configured"
error rather than failing with an opaque HTTP 401.

### Recommended: `Secrets.plist`

```bash
cp Secrets.example.plist HiddenJams/Secrets.plist
```

Fill in your keys, then add the file to the app target in Xcode:
select `Secrets.plist` → File Inspector → check **HiddenJams** under *Target Membership*.

| Key            | Where to get it                                  | Required?                       |
| -------------- | ------------------------------------------------ | ------------------------------- |
| `LastFmAPIKey` | https://www.last.fm/api/account/create           | Yes — discovery depends on it   |
| `OpenAIAPIKey` | https://platform.openai.com/api-keys             | Optional — AI taste profiles    |

### Alternative: environment variables

In Xcode: *Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables*

```
LASTFM_API_KEY = ...
OPENAI_API_KEY = ...
RAPIDAPI_KEY   = ...   # optional; stream counts fall back to mock data without it
```

### Spotify

The Spotify client ID in `SpotifyAuthManager.swift` is a **public** identifier.
The app uses the OAuth 2.0 PKCE flow, which is built for clients that cannot keep
a secret — there is no client secret, and none should be added.

## 2. Run

Build and run, then:

- Tap **Analyze My Library** — scans all liked songs and playlists
- Tap **Discover Hidden Gems** — runs the multi-API discovery engine

## Before shipping to the App Store

⚠️ **Move OpenAI calls behind your own server.** Any key bundled into an iOS app can
be extracted from the IPA by anyone who downloads it, and spent against your account.
The usual fix: host a small endpoint that holds the key and forwards requests, and
point `OpenAIService` at that endpoint instead. The same applies to the Last.fm key,
though the blast radius there is much smaller.

Other pre-submission items are tracked in [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md).

## Discovery engine notes

Spotify deprecated the Related Artists API, so discovery uses:

- **Last.fm** — similar artists
- **MusicBrainz** — release verification
- **Spotify Search** — hipster tags and micro-genres

Discovery criteria: popularity < 30, fewer than 10k followers, released in the last 3 months.

## Troubleshooting

**"0 hidden gems found"**
Check that your Last.fm key is set — discovery depends on it for similar artists.

**Build errors**
Clean the build folder (⇧⌘K) and rebuild (⌘B).
