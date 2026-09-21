# How discovery works

The product promise: pick genres, set a slider, get artists almost nobody has
heard. This describes how that is actually implemented, and what Spotify does
and does not let us do.

## The honest constraint: there are no play counts

The Spotify Web API exposes **no stream or play count** for any track or artist.
It never has. There is no endpoint for it, and no paid tier that adds one.

What it does give us, on every artist object:

| Field             | Meaning                                        |
| ----------------- | ---------------------------------------------- |
| `followers.total` | Exact count of people following the artist     |
| `popularity`      | 0–100 score derived from recent play volume    |

So "artists with under 500 plays" is not something the app can truthfully
offer. "Artists with under 500 **followers**" is — and it selects for
substantially the same thing. The slider is built on followers plus popularity,
and the UI says "followers" rather than implying a play count we cannot source.

`ObscurityWindow` owns this mapping. The slider position is the only input;
every threshold derives from it, so the number on screen and the number the
engine filters on cannot drift apart.

The curve is exponential — 100 followers at the far left, 1,000,000 at the far
right. Linear scaling would spend most of the slider's travel in a range nobody
wants; everything interesting lives under ~50k followers.

## Artist-first, not track-first

The original engine searched *tracks* by genre and judged each track's
popularity. That had two problems:

1. A track's popularity says nothing about whether the artist is undiscovered.
   A famous artist's deep cut scores low, so the engine surfaced album filler by
   well-known acts — the opposite of the point.
2. Track objects carry no follower count, so judging the artist meant another
   request per track.

`ArtistFirstDiscovery` searches artists directly. Artist objects already carry
followers and popularity, so the slider filters them with no extra round-trip,
and "obscure" means what a user expects: an artist hardly anyone follows.

Track search still runs as a secondary branch to widen the pool.

## What Spotify removed, and what replaced it

On 27 November 2024 Spotify retired several endpoints for every app without
prior extended access. This app was affected. All three it depended on are gone:

| Removed endpoint                | Replacement                                            |
| ------------------------------- | ------------------------------------------------------ |
| `/artists/{id}/related-artists` | Last.fm `artist.getsimilar`, resolved back to Spotify   |
| `/recommendations`              | Artist search with `genre:` + `tag:hipster`             |
| `/audio-features`               | None — the data no longer exists for us                 |

Also removed in the same round: `preview_url` on most track objects, which is
why previews now come from iTunes and Deezer.

### Audio features are simply gone

Energy, danceability, valence and tempo have no replacement in the Web API.
Taste profiling now runs on genre and artist signals.

`AudioFeatureProfile.isAvailable` reports whether the numbers are real. It is
`false` on current builds, and the UI should hide those dimensions rather than
render placeholder midpoints as though they were measurements. Previously these
calls failed inside a `do/catch` and profiles came back with every value at 0.5
with nothing indicating why.

## The four discovery branches

1. **Artist-first** (primary) — artists in the window, then their top tracks.
   Widens the window once if a narrow genre returns fewer than 10 artists.
2. **Genre track search** — broadens the candidate pool.
3. **Similarity** — Last.fm similar artists, seeded from the user's *own* top
   artists in the selected genres.
4. **Micro-genres** — deep dive into adjacent sub-genres.

Results are then filtered, scored and ranked.

## Two fixes worth knowing about

**Previews no longer gate results.** The enrichment step used to discard every
track without a playable preview. Since Spotify stopped supplying previews, they
come from iTunes or Deezer — and the more obscure an artist is, the less likely
either service carries them. The filter was therefore throwing away precisely
the undiscovered artists the app exists to find. Tracks are now kept either way;
playable ones sort first, and the rest open in Spotify, which plays them in full.

**Genre names use spaces.** Spotify artist genres are `"drum and bass"`, not
`"drum-and-bass"`. The hyphenated spellings were seed names for the retired
`/recommendations` endpoint and match nothing in search. Searching the
hyphenated form returned zero artists, which is what the old "DnB mode"
workaround was compensating for — it forced a genre list and switched genre
filtering off for the whole run, which is why unrelated tracks appeared in DnB
results. Fixing the spelling removed the need for the special case.

## Known constraints

- **Search offset caps at 1000.** Paging past that returns an error, so
  `searchArtists` clamps. Variety within a genre comes from rotating offsets and
  the session exclusion set rather than from deep paging.
- **`tag:hipster` only helps at the obscure end.** It restricts to the lowest
  popularity decile, so it is applied below slider position 0.35 and dropped
  above it, where it would fight the window.
- **Non-Latin-script filtering is on.** `applyFastFilters` rejects tracks whose
  title or artist is not Latin script, plus a Spanish-language exclusion. This
  is a deliberate-looking product decision inherited from the previous build,
  but it does mean the app cannot surface, say, a Japanese or Korean underground
  artist. Worth revisiting if the audience is not English-only.
