# App Store Release Checklist

Items found by auditing the current source. Ordered by what blocks submission first.

## Blockers

- [ ] **Privacy manifest (`PrivacyInfo.xcprivacy`)** — missing. Apple requires one for apps
      using "required reason" APIs. This app reads and writes `UserDefaults` in nine files,
      which falls under `NSPrivacyAccessedAPICategoryUserDefaults` (reason code `CA92.1`
      for access limited to the app itself). Add the manifest to the `HiddenJams` target.

- [ ] **Move the OpenAI key off the device.** Keys bundled into an IPA can be extracted by
      anyone who downloads the app and spent against your account. Host a small endpoint
      that holds the key and forwards requests, and point `OpenAIService` at it.

- [ ] **App Privacy questionnaire** in App Store Connect. The app reads Spotify account
      details (email, profile, library, listening history) and sends listening statistics
      to OpenAI. Both need to be declared, including the third-party sharing.

- [ ] **Deployment target is iOS 26.1** (`IPHONEOS_DEPLOYMENT_TARGET`). That excludes every
      device below it. Lower it unless the exclusion is deliberate.

## Should fix before shipping

- [ ] **Spotify tokens are stored in `UserDefaults`** (`SpotifyAuthManager.swift`), which is
      not encrypted at rest. Move the access and refresh tokens to the Keychain.

- [ ] **Rotate any key that was previously committed or shared** — see the repository
      history note in `README.md`.

- [ ] **`musicBrainzUserAgent` still reads `your-email@example.com`**
      (`APIConfiguration.swift`). MusicBrainz asks for a real contact address and may
      throttle or block generic agents.

- [ ] **Bundle identifier is `com.chris.GettingStarted.HiddenJams`**, which still carries the
      Xcode template name. Rename before creating the App Store Connect record — the
      identifier cannot be changed after the first submission.

- [ ] **Third-party attribution.** Spotify, Last.fm, MusicBrainz and Deezer each have
      branding and API terms governing how their data is displayed. Confirm the UI complies
      and that required attribution is present.

## Store listing

- [ ] Screenshots for each required device size
- [ ] App description, keywords, subtitle, support URL, marketing URL
- [ ] Privacy policy URL — required, since the app collects account data
- [ ] Age rating questionnaire
- [ ] Export compliance (the app uses HTTPS only; usually the standard exemption applies)

## Already in good shape

- App icon set is complete — 1024×1024 light, dark and tinted variants
- `MARKETING_VERSION` 1.6 / `CURRENT_PROJECT_VERSION` 6 are set
- Signing is automatic with a development team configured
- Launch screen, supported orientations and URL scheme are declared in `Info.plist`
