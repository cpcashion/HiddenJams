import { motion } from 'framer-motion'
import { useState } from 'react'
import { bus, haptic } from '../bus'
import { GENRES } from '../data'
import { CTA, rise } from '../ui/bits'

export default function Genres({ next }: { next: () => void }) {
  const [sel, setSel] = useState<string[]>([])
  const toggle = (g: string) => {
    haptic(6); bus.pulse = 1
    setSel((s) => (s.includes(g) ? s.filter((x) => x !== g) : [...s, g]))
  }
  return (
    <div className="screen genres">
      <motion.div {...rise(0.05)}>
        <h1 className="title">What do you dig?</h1>
        <p className="sub">Pick a few genres. You can change them anytime in Settings.</p>
      </motion.div>
      <motion.div className="chips" {...rise(0.12)}>
        {GENRES.map((g) => {
          const on = sel.includes(g)
          return (
            <button key={g} data-testid={`genre-${g}`} aria-pressed={on} className={`glass chip ${on ? 'lime' : 'graphite'}`} onClick={() => toggle(g)}>{g}</button>
          )
        })}
      </motion.div>
      <div className="bottom g-foot">
        <div className="caption">{sel.length === 0 ? 'Pick at least one' : `${sel.length} selected`}</div>
        <CTA onClick={next} disabled={sel.length === 0} testId="genres-continue">Continue</CTA>
      </div>
    </div>
  )
}
