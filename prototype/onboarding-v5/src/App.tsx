import { AnimatePresence, motion } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { bus } from './bus'
import { params, session } from './data'
import { loadGenres, saveGenres } from './genres'
import Glow from './Glow'
import Intro from './screens/Intro'
import Keep from './screens/Keep'
import Rarity from './screens/Rarity'
import Mood from './screens/Mood'
import Connect from './screens/Connect'
import Analyze from './screens/Analyze'
import { Deepest, Fresh, Genres, RarityScore, Signature } from './screens/Reveal'
import { AppleMusicIcon, CTA, PageDots, SpotifyIcon } from './ui/dock'

// 0-4 pre-sign-in · 5 analysis · 6-9 taste profile · 10 empty-library variant
const NAMES = ['Most music', 'Keep', 'Rarity', 'Mood', 'Connect', 'Analyzing', 'Genres', 'Rarity score', 'Artists', 'Deepest cut', 'Empty library']
const N = NAMES.length
const startAt = () => { const s = Number(params.get('s')); return s >= 1 && s <= N ? s - 1 : 0 }
const EMPTY = params.get('empty') === '1'

function useFramed() {
  const q = () => window.innerWidth > 540 && window.innerHeight > 700
  const [f, setF] = useState(q)
  useEffect(() => { const r = () => setF(q()); window.addEventListener('resize', r); return () => window.removeEventListener('resize', r) }, [])
  return f
}

export default function App() {
  const [i, setI] = useState(startAt)
  const [dir, setDir] = useState(1)
  const [run, setRun] = useState(0)
  const [picked, setPicked] = useState<string[]>(() => loadGenres())
  const [connecting, setConnecting] = useState<string | null>(null)
  const [ended, setEnded] = useState(false)
  const [empty, setEmpty] = useState(EMPTY || startAt() === 10)
  const framed = useFramed()
  const drag = useRef<{ x: number; y: number } | null>(null)
  bus.screen = i

  useEffect(() => { saveGenres(picked) }, [picked])
  const go = (n: number) => { setDir(n > i ? 1 : -1); setI(Math.max(0, Math.min(N - 1, n))); setEnded(false) }
  const connect = (svc: 'Spotify' | 'Apple Music') => {
    session.svc = svc; setConnecting(svc)
    setTimeout(() => { setConnecting(null); setDir(1); setI(5) }, 1100)
  }
  const afterAnalysis = (isEmpty: boolean) => { setEmpty(isEmpty); setDir(1); setI(isEmpty ? 10 : 6) }
  const replay = () => { setDir(-1); setRun((r) => r + 1); setEnded(false); setI(0) }

  const last = i === 9 || i === 10
  const dots = i <= 4 ? { n: 5, k: i } : i >= 6 && i <= 9 ? { n: 4, k: i - 6 } : null
  const next = () => { if (last) setEnded(true); else go(i + 1) }

  // swipe between pages like the live app's TabView(.page); never required, Next always works
  const canSwipeFwd = i <= 3 || (i >= 6 && i <= 8)
  const canSwipeBack = (i >= 1 && i <= 4) || (i >= 7 && i <= 9)
  const onDown = (e: React.PointerEvent) => { drag.current = { x: e.clientX, y: e.clientY } }
  const onUp = (e: React.PointerEvent) => {
    const d = drag.current; drag.current = null; if (!d) return
    const dx = e.clientX - d.x, dy = e.clientY - d.y
    if (Math.abs(dx) < 70 || Math.abs(dy) > 50) return
    if (dx < 0 && canSwipeFwd) go(i + 1); else if (dx > 0 && canSwipeBack) go(i - 1)
  }

  const screens = [
    <Intro />, <Keep />, <Rarity />, <Mood picked={picked} setPicked={setPicked} />, <Connect />,
    <Analyze onDone={afterAnalysis} empty={empty} />,
    <Genres picked={picked} />, <RarityScore />, <Signature />, <Deepest picked={picked} />, <Fresh picked={picked} />,
  ]
  return (
    <div className={`stage ${framed ? 'framed' : 'full'}`}>
      {framed && (
        <aside className="caption">
          <div className="cap-k mono">Hidden Jams · Onboarding v5</div>
          <div className="cap-t">Interactive prototype</div>
          <p>Pre-sign-in: 5 screens. After sign-in: the taste-profile sequence. Everything plays on its own; Next always works. Open on an iPhone for full screen.</p>
          <div className="cap-grp mono">Before sign-in</div>
          <div className="cap-nav">{[0, 1, 2, 3, 4].map((k) => <button key={k} className={k === i ? 'on' : ''} onClick={() => go(k)} title={NAMES[k]}>{String(k + 1).padStart(2, '0')}</button>)}</div>
          <div className="cap-grp mono">After sign-in</div>
          <div className="cap-nav">{[5, 6, 7, 8, 9, 10].map((k) => <button key={k} className={k === i ? 'on' : ''} onClick={() => { setEmpty(k === 10); go(k) }} title={NAMES[k]}>{String(k + 1).padStart(2, '0')}</button>)}</div>
          <p className="cap-s mono">Reviewer jump links (not part of the app). 11 = empty-library variant.</p>
        </aside>
      )}
      <div className="phone" data-step={i + 1}>
        <Glow />
        {framed && <div className="statusbar"><span>9:41</span><span className="sb-r"><i className="sig" /><i className="wifi" /><i className="bat" /></span></div>}
        <AnimatePresence mode="popLayout" custom={dir} initial={false}>
          <motion.div key={`${run}-${i}-${empty}`} className="screen-host" custom={dir} onPointerDown={onDown} onPointerUp={onUp}
            variants={{ enter: (d: number) => ({ x: d * 60, opacity: 0 }), center: { x: 0, opacity: 1 }, exit: (d: number) => ({ x: d * -60, opacity: 0 }) }}
            initial="enter" animate="center" exit="exit" transition={{ type: 'spring', stiffness: 300, damping: 34 }}>
            {screens[i]}
          </motion.div>
        </AnimatePresence>

        <div className={`dock ${i === 4 ? 'two' : ''}`} data-testid="dock">
          {dots ? <PageDots n={dots.n} i={dots.k} /> : <div className="dots-spacer" />}
          {i === 4 ? (
            <>
              <CTA testId="btn-spotify" className="brand" onClick={() => connect('Spotify')}><SpotifyIcon /> Continue with Spotify</CTA>
              <CTA testId="btn-apple" className="brand" onClick={() => connect('Apple Music')}><AppleMusicIcon /> Continue with Apple Music</CTA>
            </>
          ) : (
            <CTA onClick={next} disabled={i === 5}>{last ? 'Start digging' : 'Next'}</CTA>
          )}
        </div>

        <AnimatePresence>
          {connecting && (
            <motion.div className="sheet" key="c" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} data-testid="connecting">
              <div className="sheet-in"><i className="spin big" /><b>Connecting to {connecting}…</b><span className="mono">Prototype: pretend sign-in</span></div>
            </motion.div>
          )}
          {ended && (
            <motion.div className="sheet" key="e" initial={{ opacity: 0 }} animate={{ opacity: 1 }} data-testid="ended">
              <div className="sheet-in">
                <b>Opening Discover…</b>
                <span className="end-p">{picked.length ? <>Genres pre-applied: {picked.slice(0, 4).join(', ')}{picked.length > 4 ? ` +${picked.length - 4}` : ''}</> : 'Genres: all (nothing picked)'}</span>
                <button className="replay" onClick={replay}>Replay onboarding</button>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
        {framed && <div className="home-ind" />}
      </div>
    </div>
  )
}
