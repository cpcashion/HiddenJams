import { AnimatePresence, motion } from 'framer-motion'
import { useState } from 'react'
import { bus, haptic } from '../bus'
import { GENRES } from '../data'
import { Pill, spring } from '../ui/bits'

function Pop() {
  return (
    <span className="pop" aria-hidden>
      {Array.from({ length: 6 }, (_, k) => {
        const a = (k / 6) * Math.PI * 2
        return <motion.i key={k} initial={{ x: 0, y: 0, scale: 1, opacity: 1 }} animate={{ x: Math.cos(a) * 26, y: Math.sin(a) * 20, scale: 0, opacity: 0 }} transition={{ duration: 0.5, ease: 'easeOut' }} />
      })}
    </span>
  )
}

export default function Genres({ next }: { next: () => void }) {
  const [sel, setSel] = useState<string[]>([])
  const [last, setLast] = useState<{ g: string; n: number } | null>(null)
  const toggle = (g: string) => {
    haptic(10); bus.pulse = 1
    setSel((s) => s.includes(g) ? s.filter((x) => x !== g) : [...s, g])
    setLast({ g, n: Date.now() })
  }
  return (
    <div className="screen genres">
      <div className="top-copy">
        <h1 className="display l">What do<br />you <span className="hl">dig</span> for?</h1>
        <p className="sub">Pick a few. You can change these anytime.</p>
      </div>
      <div className="genre-wrap">
        {GENRES.map((g, k) => {
          const on = sel.includes(g)
          return (
            <motion.button key={g} data-testid={`genre-${g}`} className={`gpill ${on ? 'on' : 'glass'}`} onClick={() => toggle(g)}
              initial={{ opacity: 0, y: 24 }} animate={{ opacity: 1, y: 0, scale: on ? 1.04 : 1, rotate: on ? (k % 2 ? 2 : -2) : 0 }}
              transition={{ ...spring, delay: 0 }} whileTap={{ scale: 0.9 }}>
              <span className="num">{String(k + 1).padStart(2, '0')}</span>{g}
              {on && last?.g === g && <Pop key={last.n} />}
            </motion.button>
          )
        })}
      </div>
      <div className="actions">
        <Pill onClick={next} disabled={sel.length === 0} testId="genres-continue">
          Continue
          <AnimatePresence>{sel.length > 0 && <motion.span className="badge" initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0 }} key={sel.length}>{sel.length}</motion.span>}</AnimatePresence>
        </Pill>
      </div>
    </div>
  )
}
