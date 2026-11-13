import { motion } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { TRACKS, fmt, params, session } from '../data'
import { DEMO } from '../demo'
import { genreColors } from '../genres'
import { GenrePill, rise } from '../ui/bits'

const SPEED = Math.max(0.25, Number(params.get('speed')) || 1)
const T = { conn: 450, art: [450, 1900], songs: [1900, 3700], gen: [3700, 6000], rar: [6000, 7300], deep: [7300, 8300], end: 8900 }
const prog = (t: number, [a, b]: number[]) => Math.max(0, Math.min(1, (t - a) / (b - a)))

function useClock(on: boolean) {
  const [t, setT] = useState(0)
  useEffect(() => {
    if (!on) return
    let raf = 0, t0 = 0
    const f = (n: number) => { if (!t0) t0 = n; setT((n - t0) * SPEED); raf = requestAnimationFrame(f) }
    raf = requestAnimationFrame(f)
    return () => cancelAnimationFrame(raf)
  }, [on])
  return t
}

const R1 = TRACKS.slice(0, 9), R2 = TRACKS.slice(3).concat(TRACKS.slice(0, 3)), R3 = TRACKS.slice(6).concat(TRACKS.slice(0, 6))
function Flow({ items, dur, rev }: { items: typeof TRACKS; dur: number; rev?: boolean }) {
  const list = [...items, ...items]
  return <div className="mq small"><div className="mq-in" style={{ animationDuration: `${dur}s`, animationDirection: rev ? 'reverse' : 'normal' }}>{list.map((t, i) => <img key={i} src={t.cover} alt="" draggable={false} />)}</div></div>
}

export default function Analyze({ onDone, empty }: { onDone: (empty: boolean) => void; empty: boolean }) {
  const t = useClock(true)
  const done = useRef(false)
  useEffect(() => {
    if (done.current) return
    if (empty ? t > 4300 : t > T.end) { done.current = true; onDone(empty) }
  }, [t, empty, onDone])

  const overall = Math.min(1, t / (empty ? 4300 : T.end))
  const artP = prog(t, T.art), songP = prog(t, empty ? [1900, 3000] : T.songs), genP = prog(t, T.gen), rarP = prog(t, T.rar), deepP = prog(t, T.deep)
  const colors = genreColors(DEMO.loadingGenres)
  const filled = Math.floor(genP * (DEMO.loadingGenres.length + 0.4))
  const R = 70, C = 2 * Math.PI * R
  const SERVICE = session.svc
  const apple = SERVICE === 'Apple Music'

  type Line = { k: string; label: string; state: 'wait' | 'run' | 'done'; right?: string }
  const st = (a: number, b: number): Line['state'] => (t >= b ? 'done' : t >= a ? 'run' : 'wait')
  const lines: Line[] = [
    { k: 'conn', label: `Connected to ${SERVICE}`, state: t >= T.conn ? 'done' : 'run' },
    { k: 'art', label: apple ? 'Finding the artists you play most' : 'Pulling in your top artists', state: st(T.art[0], T.art[1]), right: t >= T.art[0] ? `${Math.round(artP * DEMO.artists)}` : '' },
    { k: 'songs', label: apple ? 'Reading your library' : 'Reading your saved songs', state: empty ? (t >= 3000 ? 'done' : st(1900, 3000)) : st(T.songs[0], T.songs[1]), right: t >= T.songs[0] ? fmt(empty ? 0 : songP * DEMO.songs) : '' },
    ...(empty ? [] : [
      { k: 'gen', label: 'Sorting your genres', state: st(T.gen[0], T.gen[1]) },
      { k: 'rar', label: 'Checking how rare it all is', state: st(T.rar[0], T.rar[1]), right: t >= T.rar[0] ? `${Math.round(rarP * DEMO.rarity.score)}/100` : '' },
      { k: 'deep', label: 'Finding your deepest cut', state: st(T.deep[0], T.deep[1]) },
    ] as Line[]),
  ]
  return (
    <div className="screen analyze">
      <div className="demotag mono">Demo data · not a real library</div>
      <motion.h1 className="display m" data-title {...rise(0.05)}>{empty ? <>Looking<br />around…</> : <>Digging through<br />your <span className="hl">library.</span></>}</motion.h1>

      <div className="flowzone" data-zone="flow">
        <Flow items={R1} dur={30} /><Flow items={R2} dur={38} rev /><Flow items={R3} dur={26} />
        <div className="ring" data-testid="ring">
          <svg viewBox="0 0 180 180">
            <circle cx="90" cy="90" r={R} className="ring-bg" />
            <circle cx="90" cy="90" r={R} className="ring-fg" strokeDasharray={C} strokeDashoffset={C * (1 - overall)} transform="rotate(-90 90 90)" />
          </svg>
          <div className="ring-n"><b>{Math.round(overall * 100)}</b><span>%</span></div>
        </div>
      </div>

      <div className="stages" data-text>
        {lines.map((l) => (
          <div key={l.k} className={`ln ${l.state}`} data-state={l.state}>
            <span className="st-i">{l.state === 'done' ? <svg viewBox="0 0 16 16"><path d="M3.5 8.4l3 3 6-6.6" /></svg> : l.state === 'run' ? <i className="spin" /> : <i className="dot" />}</span>
            <span className="st-l">{l.label}</span><span className="st-r">{l.right}</span>
          </div>
        ))}
      </div>

      {empty ? (
        <motion.p className="sub tight quiet" initial={{ opacity: 0 }} animate={{ opacity: t > 3000 ? 1 : 0 }}>Your library’s quiet, so we’ll start fresh from your picks.</motion.p>
      ) : (
        <div className="gcloud" data-zone="genres">
          {DEMO.loadingGenres.map((g, i) => <GenrePill key={g} genre={g} selected={false} filled={i < filled} color={colors[g]} />)}
        </div>
      )}
    </div>
  )
}
