import { animate, motion, useMotionValue, useMotionValueEvent, useTransform } from 'framer-motion'
import { useLayoutEffect, useRef, useState } from 'react'
import { bus, haptic } from '../bus'

const KNOB = 60, PAD = 6

/** Signature control: drag the white knob to the end. Springs back if released early. */
export default function SlideToGo({ label, onDone, testId }: { label: string; onDone: () => void; testId?: string }) {
  const track = useRef<HTMLDivElement>(null)
  const [max, setMax] = useState(260)
  const [done, setDone] = useState(false)
  const x = useMotionValue(0)
  useLayoutEffect(() => {
    const m = () => track.current && setMax(track.current.offsetWidth - KNOB - PAD * 2)
    m(); window.addEventListener('resize', m); return () => window.removeEventListener('resize', m)
  }, [])
  const p = useTransform(x, (v) => Math.min(1, Math.max(0, v / max)))
  const labelOpacity = useTransform(p, [0, 0.55], [1, 0])
  const fillW = useTransform(x, (v) => v + KNOB + PAD * 2)
  const knobRot = useTransform(p, [0, 1], [0, 0])
  const fillO = useTransform(p, [0, 0.08], [0, 1])
  const crossed = useRef(false)
  useMotionValueEvent(p, 'change', (v) => {
    bus.slide = v
    if (v > 0.86 && !crossed.current) { crossed.current = true; haptic(12) }
    if (v < 0.8) crossed.current = false
  })
  const finish = () => {
    setDone(true); haptic(20)
    animate(x, max, { type: 'spring', stiffness: 600, damping: 40 })
    setTimeout(() => { onDone(); bus.slide = 0 }, 260)
  }
  return (
    <div className="slide glass" ref={track} data-testid={testId}>
      <motion.div className="slide-fill" style={{ width: fillW, opacity: fillO }} />
      <motion.div className="slide-label" style={{ opacity: labelOpacity }}>
        <span>{label}</span>
        <span className="chev" aria-hidden><i>›</i><i>›</i><i>›</i></span>
      </motion.div>
      <motion.div
        className="slide-knob"
        data-testid={testId ? testId + '-knob' : undefined}
        drag={done ? false : 'x'}
        dragConstraints={{ left: 0, right: max }}
        dragElastic={{ left: 0.08, right: 0.04 }}
        dragMomentum={false}
        style={{ x }}
        whileTap={{ scale: 0.94 }}
        onDragEnd={() => { if (p.get() > 0.86) finish(); else animate(x, 0, { type: 'spring', stiffness: 520, damping: 26 }) }}
        role="button" tabIndex={0} aria-label={label}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') finish() }}
      >
        <motion.svg width="26" height="26" viewBox="0 0 24 24" style={{ rotate: knobRot }}>
          <path d="M5 12h13M12 5l7 7-7 7" fill="none" stroke="#0B0B0F" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
        </motion.svg>
      </motion.div>
    </div>
  )
}
