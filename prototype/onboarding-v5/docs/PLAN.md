# Hidden Jams onboarding v5: research, plan, eng spec

Status: prototype + plan only. No Swift, no App Store Connect, no App Review. v4 is untouched.

- **Live v5:** https://cpcashion.github.io/hiddenjams-onboarding-v4/v5/ (phone-sized; on desktop it shows a phone frame + reviewer jump buttons)
- **Deep links:** `?s=1` … `?s=11`
  - Before sign-in: 1 "Most music never gets heard" · 2 Keep · 3 Rarity · 4 Mood (genres) · 5 Connect
  - After sign-in: 6 Analysis (loading) · 7 Genres · 8 Rarity score · 9 Signature artists · 10 Deepest cut + Start digging · 11 Empty-library variant
  - Extras: `?svc=apple` (Apple Music wording in the analysis) · `?empty=1` (empty library path from 6) · `?speed=2` (loading runs 2x)
- **v4 (unchanged):** https://cpcashion.github.io/hiddenjams-onboarding-v4/
- **Source:** `cpcashion/HiddenJams`, branch `design/onboarding-v4-prototype` (draft PR #16, not merged), folder `prototype/onboarding-v5/`. Built output deployed to `cpcashion/hiddenjams-onboarding-v4` under `/v5/` (Pages serves `main` root; v4 `index.html` byte-identical).
- **Screenshots:** `/workspace/hidden-jams/design-research/onboarding-v5/shots/` (live-URL headless run, 393×852 @2x).

---

## 1. Research findings (cited)

### Top 5, in plain words
1. **Show the value before you ask for anything.** Duolingo lets you finish a whole lesson before it asks for an account. Moving sign-up back a few steps gave "about a 20% increase in DAUs", and soft "Later" walls added another 8.2% ([First Round review](https://review.firstround.com/the-tenets-of-a-b-testing-from-duolingos-master-growth-hacker/), [teardown](https://useronboarding.academy/onboarding-teardowns/duolingo)). Calm is criticised for asking notifications/tracking/sign-up before any value ([Botsi on Calm](https://www.botsi.com/resources/flows/apps/calm)). v5 shows four value screens before the connect ask. They are *told and shown*, not *tried*, so this is still a gap (see Open Questions).
2. **Apple's own rule: fast, fun, optional, and learn by seeing/doing.** The HIG says design onboarding that is "fast, fun, and optional", "teach through interactivity", keep it "brief" and "focused on the experience you provide", "postpone nonessential setup", and if you need private data, put the permission request in onboarding where you can explain the benefit ([HIG: Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)). This agrees with Chris's "show, don't ask". It pushes against length: v5 is 5 + 4 screens.
3. **Let people pick, then pay the pick off right away.** Spotify's artist picker shows similar artists after each tap, which keeps people going and feeds the recommendations ([Anurag Bose](https://www.anuragbose.in/the-lab/onboarding-spotify)); critics ask for a "skip", a way to browse by genre and a stated reason for the ask ([UXologist](https://theuxologist.com/case-studies/how-spotify-eases-first-time-setup)). v5: genres are optional, and the picks are shown again on the taste-profile screens ("your pick", "Starting with…") and pre-applied in Discover.
4. **When there's a wait, show the work.** Buell & Norton's "labor illusion" experiments: people rated a service higher, and preferred it to an instant one, when they could see it doing real steps, even at 30–60 s waits ([Management Science](https://pubsonline.informs.org/doi/10.1287/mnsc.1110.1376)). v5's analysis shows staged lines with live counts, genre pills filling in their colors, album art flowing and a ring. Only real steps should be shown in production.
5. **Reveal a taste profile like chapters, with one big number and an identity label.** Wrapped works because it reveals card by card, uses bold simple numbers, plays with labels, and every card is built to be screenshotted ([UX Playbook](https://uxplaybook.org/articles/spotify-wrapped-ux-design-lessons), [ADMA interview](https://adma.com.au/resources/personal-shareable-no-strings-attached-the-winning-formula-behind-spotify-wrapped), [2020 design lead](https://hegeman.co/project/spotify-your-2020-wrapped/)). Obscurify proves the "how unusual is your taste" score is a hook of its own ([about](https://dev.obscurifymusic.com/about)). v5: 4 chapters (genres, rarity score with tier ladder, signature artists, deepest cut).

### The hook stat (citable)
**"88% of tracks had 1K streams or less"** in 2025. Luminate 2025 Year-End Music Report, "2025 Global Audio Track Streaming Pyramid": 253M tracks; 120.5M with 0–10 streams; 62.6M with 11–100; 40.7M with 101–1K (sum 223.8M = 88%). Primary: [Luminate PDF](https://luminatedata.com/wp-content/uploads/2026/01/2025-Year-End-Music-Report-1.14.26.pdf) (p.15; also saved at `/workspace/appstore-copy-research/luminate-2025.txt`), reported by [Music Business Worldwide](https://www.musicbusinessworldwide.com/data/how-many-tracks-were-streamed-less-than-1000-times-on-music-services-last-year-via-luminate/) and [Music Ally](https://musically.com/2026/01/15/5-1tn-annual-music-streams-but-120-5m-tracks-had-10-or-fewer/).
Caveats baked into the copy: it is **all audio streaming services worldwide, not Spotify only**, it is **tracks (ISRCs)**, and the wording is "1,000 plays or fewer" (Luminate's own phrase), not "fewer than 1,000". I did not use "zero streams": Luminate's pyramid bucket is 0–10, and the 55M zero figure is Music Ally's inference.
For P5's "big apps push trending and promoted music": the promoted half is sourced for **Spotify** ([Discovery Mode](https://artists.spotify.com/discovery-mode), [The Guardian](https://www.theguardian.com/music/2025/feb/19/spotify-discovery-mode-payola-playlist): labels/artists take a lower royalty for a recommendation boost). I found no equivalent source for Apple Music, so the copy says "Streaming pushes what's trending and promoted" (general, not naming a company).

### Other references checked (what each added)
| App / source | Take-away used | Link |
|---|---|---|
| Duolingo (6 one-tap questions, lesson first, soft sign-up wall "Later") | value before account; one-tap steps; progress framed as something to save | [Botsi](https://www.botsi.com/resources/flows/apps/duolingo-2024-12), [AppWinners](https://appwinners.eu/guides/duolingo-onboarding-teardown) |
| Calm (17 screens, goal quiz) | don't ask permissions before value; goal answers should echo later (we echo genres) | [Botsi](https://www.botsi.com/resources/flows/apps/calm) |
| Endel (pain first, then goal; 11 intro screens, called "a lot of telling before showing") | open on a problem/truth (our P1 stat); keep the intro short | [Botsi](https://www.botsi.com/resources/flows/apps/endel) |
| Shazam (home, then mic permission at the moment of use) | the permission lands where the need is | [PageFlows](https://pageflows.com/post/ios/onboarding/shazam/) |
| Spotify Wrapped / Obscurify | chapters, big numbers, identity labels, a "rarity" score | links above |
| Opal, Airbnb (delayed login) | only seen via search summaries, not opened. Treated as unverified, nothing relies on them | summaries only |
| Apple Music (genre → artist picker) | search result was a low-quality source, **not used** | n/a |
| Mobbin / ScreensDesign | login-walled, **not accessed**; used Botsi/PageFlows/teardowns instead | n/a |

### Where Chris's notes and the research agree / what research adds
| Chris's note | Research |
|---|---|
| Remove top nav; dots at bottom like the live app; one Next | Agrees (HIG: brief, focused). Live app uses `TabView(.page)` system dots + lime Next, so v5 copies that exactly. |
| Never make the user interact; show the interaction | Agrees on "show". HIG actually favors "teach through interactivity", so v5 keeps *optional* touch (genre pills; swipe between pages like the live TabView) but nothing is required. |
| Stat-led, stop-and-think P1 | Agrees (Endel pain-first; Wrapped bold number). Added a real citation and a visual (covers go grey, one stays lit). |
| Genres must carry into the app | Agrees (Spotify picker payoff). Added visible echo on later screens. |
| P5 reminds why they're here | Agrees (HIG: explain the benefit at the permission). Added "We only save songs you keep." as the trust line. |
| Taste profile after sign-in with great loading | Agrees (labor illusion, Wrapped). Added: staged real steps, min dwell time, timeout, empty-library variant, shareable-card idea (not built). |
| (not in notes) Length | HIG says brief; Duolingo's teardown flags screens that "tell" without "do". 5 + 4 is long. P3 is the first cut candidate. |
| (not in notes) Try before connect | Duolingo/Airbnb pattern. Chris removed "Look around". v5 follows him; flagged as an open question. |

---

## 2. Note-by-note: how each of Chris's notes was addressed

**All screens**
- Top page nav removed (no back arrow, no segment bar, no "03/06"). Dots are at the bottom, in the iOS `TabView(.page)` style with the translucent capsule, same as `OnboardingView.swift` today. Swiping left/right between pages works like the live TabView but is never required.
- One Next button in the same spot on every screen: lime capsule, 16 pt semibold, glass rim, tap (no slide). Measured in the live run: Next box is identical on screens 1-4 and 6-11 (x 22–371, y 770–826). P5 is the one exception by design: the Next slot holds the two connect buttons (see Open Questions). Last screen reads "Start digging".
- Nothing asks the user to do UI. P2 and P3 are auto-playing; P4 pills are real input but optional; the analysis and reveal run on their own.

**P1:** bottom slider removed. Rock-hand-in-pocket icon removed (no app icon on any pre-sign-in screen). Floating covers kept, but they live in their own zone above the title. Layout check (bounding boxes, every run): 0 cover/text collisions. Title is "Most music never gets heard." Covers go grey one by one while "88%" counts up, one cover stays lit. Styling kept (Cabinet Grotesk display, lime highlight, starburst, grain glow). Title font is smaller than v4's (21.5cqw → 15.4cqw) because the longer line has to fit one line per row.

**P2:** the instruction now lives in its own row *below* the card ("Swipe right to keep →" / "← Swipe left to skip"), so it can't be hidden. Nothing to swipe: a scripted finger drags the card, Keep/Skip stamps fade in, kept covers land in a "Hidden Jams · Playlist in your music app" chip with a live "N saved" counter. That chip is the added playlist clarity. Sequence: keep, skip, keep, keep, pause, loop.

**P3 (redesign):** no slider. "Fewer plays. Rarer finds." Five rows build top to bottom, from chart-topper to deepest cut. Play counts fall (41.8M → 412) while the Rarity score climbs (9 → 96) and tier tags use the app's own tiers and taglines (KNOWN, EMERGING, RARE, ULTRA RARE, MYTHIC). Song names/numbers are samples (labelled).

**P4:** full rewrite (copy below). Pills are `GenrePillContent`: graphite `#1E1E24` unselected, selected = the app's genre color with near-black/white text by luminance, glow, 1.02 scale. Color assignment is a port of `Theme.Colors.genreColors` (FNV-1a over the lowercased name, sorted, collision probing), so a genre gets the same color here and in the app. Uses the app's 31 genre strings (`GenreSelectionView.commonGenres`); a build-time assertion in the prototype fails if the lists drift. Next works with nothing chosen. Selection is written to `localStorage["selectedGenres"]` as a sorted JSON array of lowercase names: the same key and shape as the app's `UserDefaults` value. Verified: pick 3, reload → pills come back pre-selected.

**P5:** new copy, one lime capsule per service with the service's icon on a white tile (consistent with each other and with Next). "Look around" and "connect later" removed.

**P6:** removed. Replaced by the post-sign-in sequence.

**After sign-in:** screens 6-10 (+11). See §3 and the eng spec.

**The bar ("one of the best onboarding flows"):** §1. Honest take: v5 is strong on show-don't-tell and on the reveal; weakest on length and on "try before connect".

---

## 3. Final copy, every screen

**1 · Most music never gets heard**
- Title: **Most music never gets heard.** ("heard." highlighted)
- Body: **88%** of songs on streaming got 1,000 plays or fewer last year. Hidden Jams finds them.
- Source line: Source: Luminate 2025 Year-End Music Report
- Button: Next

**2 · Keep**
- Title: **Keep what moves you.**
- Body: Swipe right to save a song to your **Hidden Jams** playlist. Swipe left to skip.
- Hints (auto, alternating): Swipe right to keep → / ← Swipe left to skip
- Playlist chip: Hidden Jams · Playlist in your music app · N saved
- Button: Next

**3 · Rarity**
- Title: **Fewer plays. Rarer finds.**
- Body: Every song gets a Rarity score. The less it's been heard, the higher it climbs.
- Tier tags (app's own): KNOWN · EMERGING · RARE · ULTRA RARE · MYTHIC
- Footnote: Sample songs and numbers
- Button: Next

**4 · Mood**
- Title: **In the mood for…**
- Body: Pick a few and we'll dig there first. Change them any time.
- Helper: Skipping is fine · we'll mix it up / N picked · we'll start there
- Button: Next

**5 · Connect**
- Title: **Find what the big apps won't play.**
- Body: Streaming pushes what's trending and promoted. Connect your music and we'll dig up what you'd never hear otherwise.
- Trust line: We only save songs you keep.
- Buttons: Continue with Spotify · Continue with Apple Music

**6 · Analysis** (demo data; tag "Demo data · not a real library" is prototype-only)
- Title: **Digging through your library.**
- Lines (with live counts): Connected to Spotify ✓ · Pulling in your top artists (50) · Reading your saved songs (1,284) · Sorting your genres (pills fill in color) · Checking how rare it all is (68/100) · Finding your deepest cut
- Apple Music wording: Connected to Apple Music · Finding the artists you play most · Reading your library
- Button: Next (disabled while it runs, then auto-advances)

**7 · Genres:** **You dig soul and jazz.** Bars with % per genre, "your pick" tag on genres they chose. Body: That's most of your library. We'll still dig for the unexpected.

**8 · Rarity score:** **Your taste runs rare.** Score ring 68/100, tier ladder (RARE lit). Body: **A true hidden gem.** You already listen well off the charts. Let's go deeper.

**9 · Signature artists:** **Your signature artists.** Three covers with "N saved songs". Body: The ones you keep coming back to.

**10 · Deepest cut:** **Your deepest cut.** Cover + "412 plays" sticker, track/artist. Body: Hardly anyone has heard it. You have. "Starting with" + their genre pills (or "a bit of everything"). Button: **Start digging**

**11 · Empty library:** **Fresh start.** Nothing saved yet, so we'll start from what you picked. Keep a few songs and your taste profile fills in on its own. Button: Start digging

Voice rules used: short, concrete, second person, no "AI", "algorithm", "analyze", "personalized", "curated". (The old live copy, "Customize Your Discovery", "Analyze Your Library", "Tailored to your Unique Taste Profile", is what this replaces.)

---

## 4. Prototype notes & known gaps

- Real album art in the prototype is for illustration only. **Production can't use Spotify-provided artwork like this**: Spotify's guidelines say don't animate, blur, overlay text on, crop or place a logo on their artwork ([Spotify design guidelines](https://developer.spotify.com/documentation/design)). Use bundled/licensed art or generated pastel tiles on onboarding pages.
- "Plays" stickers and numbers are sample data. In the live app there are **no per-track play counts on cards**: `StreamCountService` is mock-only (random numbers from popularity buckets, real call is a TODO) and is not referenced anywhere else; rarity is artist-level (100 − popularity, followers, Last.fm playcount). So either show the real **Rarity badge** in the onboarding demo (recommended) or don't ship "N plays" claims.
- Brand icons are drawn placeholders on a white tile. Production: official unmodified Spotify icon (full-color only on black/white; monochrome otherwise) and Apple's Apple Music icon (colored note, never recolored, never the Apple logo; see [Apple Music identity guidelines](https://marketing.services.apple/apple-music-identity-guidelines)). The current live app uses `apple.logo` for Apple Music, which those guidelines disallow as a stand-in.
- Spotify's guidelines say not to pair its brand with another brand in co-branded comms; Apple says to put its badge first if other services appear. The app already shows both. Worth a deliberate decision (Open Questions).
- Headlines use Cabinet Grotesk (carried over from v4 as "keep the louder styling"). Controls (Next, pills, lines) use the SF/system font like the app. In SwiftUI the headline would need the font bundled or an SF Pro Rounded/Black substitute.
- Headless screenshots use software GL; the real thing is smoother.

---

## 5. ENG-SPEC (for Launch; SwiftUI; don't start before Chris OKs the plan)

### 5.1 Scope and structure
Replace the body of `OnboardingView` (three `OnboardingItem`s + text-only connect page) with 5 pages inside the existing `TabView(selection:)` + `.tabViewStyle(.page(indexDisplayMode: .always))` + `.indexViewStyle(.page(backgroundDisplayMode: .always))`. Keep that so the dots are literally the live app's dots. Next button below the TabView, one view for all pages. New `TasteProfileFlow` shown after connect succeeds. `OnboardingItem`/`OnboardingPage` can be deleted once replaced.

| # | New view | Reuse | New |
|---|---|---|---|
| 1 | `OnboardingStatPage` | `Theme.Colors.backgroundGradient` (`AmbientBackground`), `Theme.Colors.lime` | cover cloud (bundled art, Reduce-Motion aware), count-up, desaturate sequence, source line |
| 2 | `OnboardingKeepDemoPage` | the real swipe card view from Discovery if separable, else a light replica; `Theme` pastel/card styles | scripted offsets (`withAnimation` + `Task` loop), playlist chip with counter |
| 3 | `OnboardingRarityPage` | `RarityViews.swift` badge + `ArtistRarity.Tier` labels/taglines/colors | row stack that builds itself, count-up |
| 4 | `OnboardingMoodPage` | `GenrePillContent`, `FlowLayout`, `Theme.Colors.genreColors(for:)`, haptic from `toggleGenre` | persistence (5.2) |
| 5 | `OnboardingConnectPage` + 2 buttons | `LimeCTAButtonStyle`, `authManager.startAuth()`, existing `connectAppleMusic()` incl. error text | official brand icons (white tile), cover marquee |
| 6-10 | `TasteProfileFlow` (loading + 4 chapters) | `AIProfileAnalyzer`, `TasteProfileGenerator`, `ListeningProfile` | see 5.3 |

- Next = `LimeCTAButtonStyle` (16 pt semibold, `brandGlass(lime, in: Capsule())`), label "Next", full width, 22 pt side padding. Dots above it (system dots). Page 5 swaps the Next slot for two `LimeCTAButtonStyle` buttons. Final reveal page: "Start digging".
- Display headlines need a bundled font or SF Pro Rounded Heavy; decide before build (Open Question).
- Accessibility: Reduce Motion → static covers, no drift, loading shows lines + percent only; VoiceOver reads each loading line as it completes (`accessibilityAddTraits(.updatesFrequently)` on the ring); Dynamic Type up to xxxLarge on body/helper; all demos have an accessibility label describing what they show; pills keep `.isSelected` trait.

### 5.2 Genre selection persistence and pre-apply
- **Key:** `UserDefaults.standard` `"selectedGenres"` (the same key `GenreSelectionView`, `DashboardView`, `MainTabView` and `ListeningStatsStore` already read).
- **Value shape:** `JSONEncoder().encode(Set<String>)`, **lowercased** names exactly as in `GenreSelectionView.commonGenres` (e.g. `"hip hop"`, `"r&b"`, `"k-pop"`, `"drum and bass"`). Display with `.capitalized` like `GenrePillContent`.
- **Write:** from `OnboardingMoodPage` on every toggle (so a force-quit mid-onboarding keeps it) and on Next. If the user picks nothing, write nothing (leave the key as is). `GenreSelectionView.loadGenres()` treats empty/no data as "select all", which is the right default.
- **Pre-apply: no extra code in `GenreSelectionView`.** Because it reads the same key, it opens with those pills selected, and `DashboardView` shows "Discovering: soul, jazz" and `EnhancedHiddenGemsDiscovery` gets them as `selectedGenres` (strict filter) from `MainTabView`/`DashboardView`. The prototype proves the contract: it writes the key, reload re-selects them, and the end screen says "Genres pre-applied: …".
- **Refactor to prevent drift:** move `commonGenres` out of `GenreSelectionView` into `GenreCatalog.common` (+ an `onboardingOrder`) used by both views. The prototype has an assertion for this.
- **Colors:** `genreColors(for:)` is computed from the *selected set*, so a pill's color can change as the set changes (same in the live picker). Onboarding and the picker will agree for the same set.
- **Existing selection** (reinstall, "Disconnect all" then onboarding reappears): pre-select from the key instead of starting empty.
- **Strict-filter risk to check:** with 1-2 narrow genres, strict mode may starve the pool. Decide on a minimum (say 3) or a fallback that widens when the pool is thin. Not a prototype question, but picking "ambient" only should not yield an empty deck.
- **Optional:** after the taste profile, offer "Add your top genres too" (union of picks + analysis top 3). Open Question.

### 5.3 Taste-profile analysis flow and loading states
Trigger: first time `sourceManager.hasConnectedSource` becomes true while onboarding is incomplete (the hook `ContentView` already uses for `markOnboardingCompleted()`). Run `TasteProfileFlow` full screen over the app; Discover loads underneath. "Start digging" dismisses it.

**Pipeline (reuses `AIProfileAnalyzer.analyzeAllConnectedSources(spotifyToken:)`).** The analyzer already publishes `analysisProgress` and `currentStep`. Today `currentStep` is developer copy ("Starting quick analysis…"). Add a typed `@Published var stage: AnalysisStage` plus counts:

| Stage (enum) | User-facing line | Data source | Count shown |
|---|---|---|---|
| `.connected` | Connected to {Service} | auth success | none |
| `.artists` | Pulling in your top artists | Spotify `GET /me/top/artists?limit=50&time_range=long_term` (already `getTopArtists`) · Apple: aggregate artist from library songs by `playCount` | artist count |
| `.songs` | Reading your saved songs | Spotify `GET /me/tracks` paged (`getAllLikedTracks`) · Apple `MusicLibraryRequest<Song>` | running song count |
| `.genres` | Sorting your genres | Spotify: artist `genres` joined to tracks (as in `analyzeCompleteLibrary`) · Apple: `Song.genreNames` (needs a mapping from Apple's genre names, e.g. "R&B/Soul", "Hip-Hop/Rap", to the app's list) | pills fill |
| `.rarity` | Checking how rare it all is | `RarityService` per top artist (+ Last.fm) | score/100 |
| `.deepest` | Finding your deepest cut | lowest-rarity-percentile track in the user's top/saved tracks | none |

**Timing rules (so it feels good and stays honest):**
- Each stage line shows at least ~600 ms even if the work is instant; never fake counts, never show a stage that didn't run. Typical total target 6-9 s as in the prototype.
- Progress ring = completed weight / total weight (the prototype weights stages by their duration, roughly 5/16/20/26/15/11 %).
- Slow library: after 12 s on a stage show a quiet sub-line "Big library. Still reading…". Hard cap 45 s: dismiss to Discover and finish in the background, then surface the profile as a Dashboard card (the existing `analysisProgressCard` slot).
- Cancel/background: if the app is backgrounded, continue; on return show the current state.
- Reveal chapters (Next advances; none require touch): Genres (top 5 with % + "your pick" tags from `selectedGenres`) → Rarity score (ring + tier ladder) → Signature artists (top 3 by saved songs) → Deepest cut (+ "Starting with" chips from `selectedGenres`).

**Output model (maps onto existing `ListeningProfile` where possible):**
`TasteProfile { topGenres: [(genre: String, share: Double)], rarityScore: Int /*0-100*/, tier: ArtistRarity.Tier, signatureArtists: [Artist] /*3*/, deepestCut: Track, librarySize: Int, sources: [MusicSource], generatedAt: Date }`, persisted and reusable later in Profile (`ProfileView`/`ProfileStatsView` already show listening stats).
Proposed score: mean of per-track tier weights over the user's top ~100 tracks (known 0, emerging .35, rare .65, ultra .9, mythic 1) × 100, so it reads on the same ladder as the card badges. Tune with real libraries; the prototype's 68 is a mock.

**Data sources, what's realistic**
- **Spotify Web API (works today):** `GET /me/top/artists` and `/me/top/tracks` (still listed as available after Feb 2026; scope `user-top-read` already requested), `GET /me/tracks` (`user-library-read`), `GET /me/player/recently-played` (`user-read-recently-played`). Genres come from **artist** objects, not tracks. No per-track stream counts.
- **Spotify risks to confirm first:** Nov 27 2024: new apps lost audio features/analysis, recommendations and related artists ([blog](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api)). Feb 2026 changelog removed `popularity` (track/album/artist), artist `followers`, `GET /artists` and `GET /tracks` batch endpoints and reduced search `limit` to 10 ([changelog](https://developer.spotify.com/documentation/web-api/references/changes/february-2026)); the accompanying blog frames these as **Development Mode** changes with a 5-user cap and Premium requirement ([blog](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security)). **I could not tell which quota mode Hidden Jams is in.** If it's Extended Quota these may not apply; if it's Dev Mode the app can't have public users at all. Either way: `RarityService` (100 − popularity, followers) and `TasteProfileGenerator.calculateObscurityScore` (popularity < 30) depend on fields that may disappear, so the rarity score needs a non-Spotify backbone (Last.fm listeners/playcount, which `RarityViews` already shows as "Last.fm plays") and graceful nil handling. **Check this before building the rarity chapter.**
- **Apple MusicKit:** `MusicLibraryRequest<Song>` gives `genreNames`, `playCount`, `lastPlayedDate` (iOS 16+), artist, artwork ([docs mirror](https://apple-docs.everest.mt/docs/musickit/song/playcount/)). There is no "top artists" API: derive it from `playCount`. Heavy Rotation / Recently Played are REST-only (`/v1/me/history/heavy-rotation`, `/v1/me/recent/played`, ~10 items). No popularity or global play count at all, so rarity needs the catalog artist lookup + Last.fm. `LibraryTrack` already carries `genreNames`. `AppleMusicError.fetchFailed("No songs found…")` is the existing empty-library signal.
- **LLM use:** no model is needed for any number in this flow (all deterministic). The existing `OpenAIService.generateAIPersonality` could write one optional line later. If used, send only top genres/artist names (never the track list), add it to `docs/privacy.html`, and never say "AI" in UI copy (Chris's note).

### 5.4 Edge cases
| Case | Behavior |
|---|---|
| **No service connected / user doesn't want to connect** | v5 has no "look around" (per Chris). The app still can't discover without a source, so P5 stays until a service connects. If auth is cancelled or fails: stay on P5, inline error (reuse `appleMusicError` style), buttons re-enable. |
| **Spotify OAuth cancelled / 403 (account not allowed in Dev Mode)** | Inline: "Couldn't connect to Spotify. Try again?" with the system error on a "Details" line in debug builds only. |
| **Apple Music permission denied** | Existing copy: Settings → Privacy → Media & Apple Music. Add "Open Settings" button. **Not an Apple Music subscriber** (`MusicSubscription.canPlayCatalogContent == false`): explain preview-only; still run the profile from the local library. |
| **Empty or tiny library** (<10 songs / `calculateProfileStrength` low) | Skip chapters 7-10. Show screen 11 "Fresh start" (built in the prototype, `?s=11` or `?empty=1`): uses their genre picks; the profile card appears on Dashboard once they've saved ~20 songs. |
| **Both services connected** | Merge as `analyzeAllConnectedSources` does; stage line says "Connected to Spotify and Apple Music"; artist/song counts are de-duplicated with `LibraryTrack.dedupeKey`. |
| **Connect the second service later** | Re-run in the background and update the Dashboard card ("Your taste profile updated"); no full-screen sequence. |
| **Offline / timeout / HTTP 429** | Back off (honor `Retry-After`); after retries, keep partial results and skip to Discover with a Dashboard "Try again" card. Don't show a half-wrong profile. |
| **No genres on artists** (obscure/unknown) | Compute from the artists that have them; if <3 genres, skip chapter 7 and show the rarity chapter first. |
| **Skip** | Taste-profile screens aren't gated: a "Skip" is not shown (the user can just hit Next), but the sequence is dismissible with the system swipe-down; the profile is still generated in the background and saved. |
| **Onboarding replay** ("Disconnect all" brings it back) | Pre-fill genres from the existing key; never show the stat screens twice in a session. |
| **Dynamic Type / small phones (SE)** | Title scales down one step; covers cloud shrinks; the page content scrolls under the pinned Next + dots (the prototype does not do small-screen testing yet). |

### 5.5 Analytics (suggested events)
`onboarding_page_view{page}`, `onboarding_next_tap{page}`, `genres_selected{count, genres}`, `connect_tap{service}`, `connect_result{service, ok, error}`, `analysis_stage{stage, ms}`, `analysis_done{ms, songs, artists, empty}`, `profile_chapter_view{n}`, `start_digging_tap`. Compare completion and connect rate against the current 3-page flow before ripping the old one out.

---

## 6. Rollout

1. Chris reviews v5 (live link above) and the Open Questions. Prototype only; PR #16 stays draft, not merged.
2. Launch builds the SwiftUI flow behind the existing `OnboardingView` entry; TestFlight build. Real asset review (brand icons, art).
3. **App Store screenshots update only after that in-app build lands** and screenshots are captured from the real build (candidates: P1 stat, P2 keep demo with the playlist chip, P3 rarity descent, taste-profile genres, rarity score, deepest cut). Marketing's screenshot copy (separate task) should wait for that.
4. **Nothing goes to App Store Connect or App Review without Chris's explicit OK.** This work has not touched either.

## 7. Open questions for Chris
1. **P5 and "one Next on every screen":** I made the two connect buttons *the* forward action on that page (same lime capsule, same slot, dots stay). Keep, or add a separate Next? (A separate Next would have nothing to do before connecting.)
2. **Length:** 5 pre-sign-in + a 4-chapter reveal. HIG says brief. Want an A/B (e.g. drop P3, since the rarity chapter after sign-in explains it again)?
3. **"Try before connect"** (Duolingo/Airbnb pattern): the research favors a taste of the product before the connect ask. You removed "look around", so I followed that. A middle path is a bundled 3-song sample deck that needs no account. Not built.
4. **Hook stat OK?** "88% of songs on streaming got 1,000 plays or fewer last year" (Luminate 2025, all services worldwide, tracks). Alternative second line from the same report: "120.5M of 253M tracks got 10 plays or fewer."
5. **"Promoted"** is sourced for Spotify only. OK as a general statement, or name it?
6. **Which Spotify quota mode is HJ in?** It decides whether `popularity`/`followers` still exist and whether the rarity score needs a Last.fm backbone (§5.3).
7. **Brand pairing:** Spotify says don't pair brands; Apple says Apple Music first if others appear. Keep both side by side (as the live app does)?
8. **Fonts:** keep Cabinet Grotesk headlines (v4 look) or SF Pro Rounded to match `Theme.swift` exactly?
9. **Genres after analysis:** merge their onboarding picks with their analyzed top genres, or keep picks only?
10. **Share card** from the taste profile (Wrapped pattern; a ready-made marketing loop)? Not built.
11. **"plays" claims:** the live app has no per-track play counts (see §4). Show the Rarity badge in onboarding instead?
12. **LLM line:** any appetite for one generated sentence on the profile (needs a privacy-policy line), or keep it fully numeric?

## 8. Verification log (live URL, headless Chromium, 393×852 @2x)
See `VERIFY.md` in this folder for the machine output of the last run.
