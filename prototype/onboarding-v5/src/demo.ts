// CLEARLY FAKE demo data for the taste-profile sequence. Real build: see PLAN.md ENG-SPEC.
export const DEMO = {
  artists: 50, songs: 1284,
  genres: [
    { g: 'soul', pct: 34 }, { g: 'jazz', pct: 22 }, { g: 'funk', pct: 14 }, { g: 'indie', pct: 11 }, { g: 'ambient', pct: 8 },
  ],
  loadingGenres: ['soul', 'jazz', 'funk', 'indie', 'ambient', 'folk', 'electronic', 'blues', 'latin', 'alternative'],
  rarity: { score: 68, tier: 'RARE', tag: 'a true hidden gem' },
  signature: [{ f: 'khruangbin.jpg', n: 31 }, { f: 'cleo.jpg', n: 24 }, { f: 'nala.jpg', n: 19 }],
  deepest: { f: 'yazmin.jpg', plays: 412 },
}
