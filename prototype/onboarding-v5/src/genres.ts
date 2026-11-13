// Mirrors HiddenJams/Utils/Theme.swift (genrePalette, genreColors, textOnGenreColor)
// and HiddenJams/Views/GenreSelectionView.swift (commonGenres, "selectedGenres" key).

export const GENRE_PALETTE = ['#FF8FC7', '#C9A0F0', '#C8E86B', '#FFB38A', '#F3E59A', '#8EE6B8', '#FF7A85', '#A78BFA', '#E879F9', '#7FE0C4']

/** The app's own genre strings (lowercased, exactly as persisted). */
export const COMMON_GENRES = [
  'pop', 'rock', 'hip hop', 'rap', 'country', 'r&b', 'electronic', 'dance', 'indie', 'alternative',
  'classical', 'jazz', 'blues', 'metal', 'punk', 'folk', 'reggae', 'soul', 'funk', 'latin',
  'reggaeton', 'k-pop', 'anime', 'gospel', 'christian', 'worship', 'drum and bass', 'jungle', 'house', 'techno', 'ambient',
]

/** Onboarding order: deep-cut friendly first, same strings as the app. */
export const ONBOARDING_ORDER = [
  'soul', 'jazz', 'indie', 'funk', 'ambient', 'folk', 'electronic', 'hip hop', 'r&b', 'alternative',
  'blues', 'latin', 'reggae', 'rock', 'classical', 'house', 'techno', 'punk', 'metal', 'country',
  'pop', 'dance', 'rap', 'drum and bass', 'jungle', 'k-pop', 'reggaeton', 'anime', 'gospel', 'christian', 'worship',
]

/** Swift `String.capitalized`: first letter of each word upper, rest lower. */
export const capitalized = (g: string) => g.replace(/(^|[\s-])(\p{L})/gu, (_, a, b) => a + b.toUpperCase())

/** FNV-1a 64-bit over the lowercased UTF-8 bytes (Theme.stableGenreHash). */
function hash(s: string): number {
  let h = 0xcbf29ce484222325n
  const mask = (1n << 64n) - 1n
  for (const b of new TextEncoder().encode(s.toLowerCase())) {
    h ^= BigInt(b)
    h = (h * 0x100000001b3n) & mask
  }
  return Number((h & 0x7fffffffffffffffn) % BigInt(GENRE_PALETTE.length))
}

/** Theme.Colors.genreColors(for:): deterministic, collision-probed, bounded. */
export function genreColors(genres: string[]): Record<string, string> {
  const sorted = Array.from(new Set(genres.map((g) => g.toLowerCase()))).sort()
  const used = new Set<number>()
  const out: Record<string, string> = {}
  for (const g of sorted) {
    let idx = hash(g), probes = 0
    while (used.has(idx) && probes < GENRE_PALETTE.length) { idx = (idx + 1) % GENRE_PALETTE.length; probes++ }
    used.add(idx)
    out[g] = GENRE_PALETTE[idx]
  }
  return out
}

/** Theme.Colors.textOnGenreColor: near-black on light neons, white on the rest. */
export function textOnGenre(hex: string): string {
  const n = parseInt(hex.slice(1), 16)
  const lum = 0.2126 * ((n >> 16) / 255) + 0.7152 * (((n >> 8) & 255) / 255) + 0.0722 * ((n & 255) / 255)
  return lum > 0.55 ? '#111827' : '#FFFFFF'
}

/* ---- persistence: same key/shape as the app's UserDefaults "selectedGenres" (JSON Set<String>, lowercased) ---- */
export const GENRE_KEY = 'selectedGenres'
export function loadGenres(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(GENRE_KEY) || '[]')
    return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []
  } catch { return [] }
}
export function saveGenres(g: string[]) {
  try { localStorage.setItem(GENRE_KEY, JSON.stringify(Array.from(new Set(g.map((x) => x.toLowerCase()))).sort())) } catch { /* private mode */ }
}
