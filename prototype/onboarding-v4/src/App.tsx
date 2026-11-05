import { AnimatePresence, motion } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { bus } from './bus'
import Scene from './three/Scene'
import { Dots } from './ui/bits'
import Intro from './screens/Intro'
import Swipe from './screens/Swipe'
import Depth from './screens/Depth'
import Genres from './screens/Genres'
import Connect from './screens/Connect'
import Payoff from './screens/Payoff'

const N = 6
const startAt = () => { const s = Number(new URLSearchParams(location.search).get('s')); return s >= 1 && s <= N ? s - 1 : 0 }

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
  const framed = useFramed()
  const phone = useRef<HTMLDivElement>(null)
  bus.screen = i
  const go = (n: number) => { setDir(n > i ? 1 : -1); setI(Math.max(0, Math.min(N - 1, n))) }
  const next = () => go(i + 1)
  const replay = () => { setDir(-1); setRun((r) => r + 1); setI(0) }

  useEffect(() => {
    const el = phone.current!
    const mv = (e: PointerEvent) => {
      const r = el.getBoundingClientRect()
      bus.pointer.x = ((e.clientX - r.left) / r.width) * 2 - 1
      bus.pointer.y = ((e.clientY - r.top) / r.height) * 2 - 1
    }
    window.addEventListener('pointermove', mv)
    window.addEventListener('pointerdown', mv)
    const ori = (e: DeviceOrientationEvent) => {
      if (e.gamma == null || e.beta == null) return
      bus.tilt.x = Math.max(-1, Math.min(1, e.gamma / 35))
      bus.tilt.y = Math.max(-1, Math.min(1, (e.beta - 50) / 35))
    }
    // iOS needs a user gesture before motion access; ask once on first touch.
    const ask = () => {
      const D = DeviceOrientationEvent as unknown as { requestPermission?: () => Promise<string> }
      if (typeof D?.requestPermission === 'function') D.requestPermission().then((s) => s === 'granted' && window.addEventListener('deviceorientation', ori)).catch(() => {})
      else window.addEventListener('deviceorientation', ori)
    }
    window.addEventListener('pointerup', ask, { once: true })
    return () => { window.removeEventListener('pointermove', mv); window.removeEventListener('pointerdown', mv); window.removeEventListener('deviceorientation', ori) }
  }, [])

  const screens = [
    <Intro next={next} />, <Swipe next={next} />, <Depth next={next} />,
    <Genres next={next} />, <Connect next={next} />, <Payoff replay={replay} />,
  ]
  return (
    <div className={`stage ${framed ? 'framed' : 'full'}`}>
      {framed && (
        <aside className="aside">
          <div className="k">Hidden Jams · Onboarding v4</div>
          <div className="t">Interactive prototype</div>
          <p>Tap, swipe and drag like you would on the phone. Open the link on an iPhone for full screen and tilt.</p>
          <div className="aside-nav">{Array.from({ length: N }, (_, k) => <button key={k} className={`glass chip ${k === i ? 'lime' : 'graphite'}`} onClick={() => go(k)}>{k + 1}</button>)}</div>
        </aside>
      )}
      <div className="phone" ref={phone}>
        <Scene screen={i} />
        <div className="chrome">
          {framed && <div className="statusbar"><span>9:41</span><span className="sb-r"><i className="sig" /><i className="wifi" /><i className="bat" /></span></div>}
          <div className="topbar">
            {i > 0 && <button className="glass subtle back" onClick={() => go(i - 1)} aria-label="Back"><svg width="16" height="16" viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7" stroke="#fff" strokeWidth="2.4" fill="none" strokeLinecap="round" strokeLinejoin="round" /></svg></button>}
            <Dots i={i} n={N} />
          </div>
        </div>
        <AnimatePresence mode="popLayout" custom={dir} initial={false}>
          <motion.div key={`${run}-${i}`} className="screen-host" custom={dir}
            variants={{ enter: (d: number) => ({ x: d * 40, opacity: 0 }), center: { x: 0, opacity: 1 }, exit: (d: number) => ({ x: d * -40, opacity: 0 }) }}
            initial="enter" animate="center" exit="exit" transition={{ type: 'spring', stiffness: 280, damping: 36 }}>
            {screens[i]}
          </motion.div>
        </AnimatePresence>
        {framed && <div className="home-ind" />}
      </div>
    </div>
  )
}
