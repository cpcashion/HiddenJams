import raw from './tracks.json'

export const BASE = import.meta.env.BASE_URL
export const art = (f: string) => `${BASE}art/${f}`

export type Track = { file: string; track: string; artist: string; album: string; year: string; genre: string; cover: string }
export const TRACKS: Track[] = (raw as Omit<Track, 'cover'>[]).map((t) => ({ ...t, cover: art(t.file) }))
export const byFile = (f: string) => TRACKS.find((t) => t.file === f)!

export const fmt = (n: number) => Math.round(n).toLocaleString('en-US')

/** URL params shared by every screen. */
export const params = new URLSearchParams(location.search)
/** ?svc=apple swaps the connected-service wording in the analysis sequence. */
export const session: { svc: 'Spotify' | 'Apple Music' } = { svc: params.get('svc') === 'apple' ? 'Apple Music' : 'Spotify' }
