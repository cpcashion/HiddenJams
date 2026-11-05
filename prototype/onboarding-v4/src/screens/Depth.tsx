import { AnimatePresence, animate, motion, useMotionValue, useTransform } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { bus, haptic } from '../bus'
import { APPICON, fmt } from '../data'
import { FitText, Pill, spring } from '../ui/bits'

const WORDS = ['Mainstream', 'Underground', 'Buried']
const playsAt = (v: number) => Math.pow(10, 7.6 - v * 5.0) // ~40M -> ~400
const nice = (n: number) => n > 1e6 ? (n / 1e6).toFixed(1).replace('.0', '') + 'M' : n > 1e4 ? Math.round(n / 1e3) + 'K' : fmt(n)

export default function Depth({ next }: { next: () => void }) {
  const [v, setV] = useState(0.5)
  const track = useRef<HTMLDivElement>(null)
  const dragging = useRef(false)
  const shown = useMotionValue(playsAt(0.5))
  const [num, setNum] = useState(nice(playsAt(0.5)))
  useEffect(() => shown.on('change', (n) => setNum(nice(n))), [shown])
  useEffect(() => { bus.depth = v; const a = animate(shown, playsAt(v), { duration: 0.35, ease: 'easeOut' }); return () => a.stop() }, [v, shown])
  const zone = v < 0.34 ? 0 : v < 0.7 ? 1 : 2
  const prevZone = useRef(zone)
  useEffect(() => { if (prevZone.current !== zone) { haptic(10); prevZone.current = zone } }, [zone])
  const deep = v > 0.86
  const set = (clientX: number) => {
    const r = track.current!.getBoundingClientRect()
    setV(Math.min(1, Math.max(0, (clientX - r.left) / r.width)))
  }
  const handX = useMotionValue(0)
  const glowS = useTransform(handX, [0, 1], [0.6, 1.25])
  useEffect(() => { animate(handX, Math.max(0, (v - 0.55) / 0.45), { type: 'spring', stiffness: 200, damping: 20 }) }, [v, handX])
  return (
    <div className="screen depth">
      <div className="top-copy">
        <h1 className="display l">How deep<br />do you <span className="hl">dig</span>?</h1>
      </div>
      <div className="depth-mid">
        <motion.div className="hand-wrap" animate={deep ? { y: -6, rotate: [0, -8, 8, -6, 0], scale: 1.08 } : { y: 22 - v * 22, rotate: 0, scale: 0.82 + v * 0.18 }} transition={deep ? { rotate: { duration: 0.6, repeat: Infinity, repeatDelay: 0.5 }, default: spring } : spring}>
          <motion.div className="hand-glow" style={{ scale: glowS, opacity: handX }} />
          <img src={APPICON} alt="" className="hand-icon" />
        </motion.div>
      </div>
      <div className="depth-word" data-testid="depth-word">
        <AnimatePresence mode="popLayout" initial={false}>
          <motion.div key={zone} initial={{ y: 60, opacity: 0, filter: 'blur(8px)' }} animate={{ y: 0, opacity: 1, filter: 'blur(0px)' }} exit={{ y: -60, opacity: 0, filter: 'blur(8px)' }} transition={{ type: 'spring', stiffness: 380, damping: 30, filter: { duration: 0.25, ease: 'easeOut' } }}>
            <FitText className={zone === 2 ? 'lime' : ''}>{WORDS[zone]}</FitText>
          </motion.div>
        </AnimatePresence>
      </div>
      <div className="plays-row">
        <span className="mono">Songs under</span>
        <span className="plays-num" data-testid="plays">{num}</span>
        <span className="mono">plays</span>
      </div>
      <div className="slider" ref={track} data-testid="depth-slider"
        onPointerDown={(e) => { dragging.current = true; (e.target as Element).setPointerCapture?.(e.pointerId); set(e.clientX) }}
        onPointerMove={(e) => dragging.current && set(e.clientX)}
        onPointerUp={() => { dragging.current = false }} onPointerCancel={() => { dragging.current = false }}>
        <div className="rail" />
        <div className="rail-fill" style={{ width: `${v * 100}%` }} />
        {[0, 0.5, 1].map((d) => <div key={d} className={`tick ${v >= d - 0.01 ? 'on' : ''}`} style={{ left: `${d * 100}%` }} />)}
        <motion.div className="knob" style={{ left: `${v * 100}%` }} animate={{ scale: dragging.current ? 1.15 : 1 }} />
      </div>
      <div className="slider-labels mono"><span>Hits</span><span>Deep cuts</span><span>Buried</span></div>
      <div className="actions"><Pill onClick={next} testId="depth-continue">Continue</Pill></div>
    </div>
  )
}
