import raw from './tracks.json'

export const BASE = import.meta.env.BASE_URL
export const art = (f: string) => `${BASE}art/${f}`

// Prototype play counts (illustrative, not live Spotify data).
const PLAYS = [2418, 731, 5102, 1366, 864, 3290, 9840, 412, 1780, 6021, 2954, 1107]

export type Track = {
  file: string; track: string; artist: string; album: string; year: string; genre: string
  cover: string; plays: number; tag: string
}

const tagFor = (g: string) =>
  '#' + g.toLowerCase().replace('r&b/soul', 'soul').replace('indie pop', 'indie').replace('indie rock', 'psych').replace('worldwide', 'world').replace(' ', '')

export const TRACKS: Track[] = (raw as Omit<Track, 'cover' | 'plays' | 'tag'>[]).map((t, i) => ({
  ...t, cover: art(t.file), plays: PLAYS[i % PLAYS.length], tag: tagFor(t.genre),
}))

export const APPICON = art('appicon.png')
export const fmt = (n: number) => Math.round(n).toLocaleString('en-US')

export const GENRES = ['Soul', 'Jazz', 'Psych', 'Funk', 'Indie', 'Ambient', 'Hip-hop', 'Folk', 'Electronic', 'Afrobeat', 'Bossa nova', 'Lo-fi']
