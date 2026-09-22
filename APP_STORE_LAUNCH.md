# HiddenJams — App Store Launch Checklist

Status: code is on GitHub, CI builds on every push, release pipeline is staged.
Apple-side steps below are owner-only (Apple ID + paid Developer Program).

## Already done (in this repo)

- [x] No hardcoded secrets — keys resolve from `Secrets.plist` (git-ignored), `Info.plist`, or env. See `SETUP.md`.
- [x] `PrivacyInfo.xcprivacy` — declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (required-reason API; App Store rejects without it).
- [x] App icon set — 1024×1024 light/dark/tinted variants in `AppIcon.appiconset`.
- [x] Spotify auth uses OAuth 2.0 PKCE (no client secret) with the `spotifyhiddengems://callback` URL scheme registered in `Info.plist`.
- [x] All network calls are HTTPS; no App Transport Security exceptions.
- [x] Shared `HiddenJams` Xcode scheme so CI and `xcodebuild` can build without opening Xcode.
- [x] `.github/workflows/ios.yml` — builds + unit-tests on a macOS runner for every push/PR.
- [x] `.github/workflows/release.yml` — manual workflow that archives and uploads to App Store Connect once secrets are configured.

## Before first upload (Apple Developer account)

1. **Bundle ID.** Currently `com.chris.GettingStarted.HiddenJams` (v1.6, build 6). Register it at
   developer.apple.com → Certificates, Identifiers & Profiles → Identifiers.
   Optional: rename to something cleaner (e.g. `com.cpcashion.hiddenjams`) — safe before first submission, just update the pbxproj + this doc.
2. **Distribution certificate.** On your Mac: Xcode → Settings → Accounts → Manage Certificates → add "Apple Distribution". Export the `.p12` for the `SIGNING_CERTIFICATE_BASE64` repo secret.
3. **App Store provisioning profile.** Create one for the bundle ID (Distribution → App Store Connect), download the `.mobileprovision` for the `PROVISIONING_PROFILE_BASE64` repo secret.
4. **App Store Connect API key.** App Store Connect → Users and Access → Integrations → App Store Connect API → create key, role **App Manager**. Download the `.p8` once. Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`. Also set a random `KEYCHAIN_PASSWORD` secret.
5. **App record.** App Store Connect → My Apps → + → New App. Name: **Hidden Jams**, bundle ID from step 1, SKU anything unique. Check name availability — "Hidden Jams" must not be taken.

## Metadata & assets (App Store Connect listing)

- **Screenshots:** 6.9" (1290×2796) and 6.5" (1242×2688) required; iPad optional. Capture from the simulator (File → Save Screen works at exact size).
- **App icon for the store:** 1024×1024, no alpha, no rounded corners (Apple masks it).
- **Description / keywords / support URL / privacy policy URL** — privacy policy URL is mandatory. Note in the policy: Spotify OAuth data stays on-device; Last.fm/OpenAI calls send only artist names.
- **Age rating** questionnaire; **pricing** (free with no IAP is simplest for v1).
- **Review notes:** give the reviewer a Spotify test account (or a demo mode path) — login-gated apps get rejected without one. If Last.fm/OpenAI keys are needed for core features, explain where to enter them or ship with them configured.

## Release run

1. Push this PR's branch, merge to `main`, confirm the `iOS Build & Test` workflow is green.
2. Actions → "Release to App Store Connect" → Run workflow.
3. In App Store Connect: select the uploaded build → fill metadata → Submit for Review.
4. Apple review typically takes 24–72h. First submissions are often rejected for metadata nits — fix and resubmit.

## Post-approval

- Monitor crash reports in Xcode Organizer / App Store Connect.
- Tag the release in git (`git tag v1.6`) and bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` for the next build.
