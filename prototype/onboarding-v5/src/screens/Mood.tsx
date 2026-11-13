import { motion } from 'framer-motion'
import { COMMON_GENRES, ONBOARDING_ORDER, genreColors } from '../genres'
import { bus, haptic } from '../bus'
import { GenrePill, rise } from '../ui/bits'

if (ONBOARDING_ORDER.length !== COMMON_GENRES.length || ONBOARDING_ORDER.some((g) => !COMMON_GENRES.includes(g))) throw new Error('onboarding genre list drifted from the app list')

export default function Mood({ picked, setPicked }: { picked: string[]; setPicked: (g: string[]) => void }) {
  const colors = genreColors(picked) // same hashing + collision probing as the app, so colors match after sign-in
  const toggle = (g: string) => {
    haptic(10); bus.pulse = 1
    setPicked(picked.includes(g) ? picked.filter((x) => x !== g) : [...picked, g])
  }
  return (
    <div className="screen mood">
      <motion.h1 className="display m" {...rise(0.1)}>In the <span className="hl">mood</span><br />for…</motion.h1>
      <motion.p className="sub tight" {...rise(0.2)}>Pick a few and we’ll dig there first. Change them any time.</motion.p>
      <motion.div className="pillscroll" data-zone="pills" {...rise(0.3)}>
        <div className="pillwrap">
          {ONBOARDING_ORDER.map((g, k) => (
            <motion.div key={g} initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 + k * 0.012 }}>
              <GenrePill genre={g} selected={picked.includes(g)} color={colors[g] ?? '#C8E86B'} onClick={() => toggle(g)} testId={`genre-${g}`} />
            </motion.div>
          ))}
        </div>
      </motion.div>
      <p className="mono helper" data-testid="genre-helper">{picked.length ? `${picked.length} picked · we’ll start there` : 'Skipping is fine · we’ll mix it up'}</p>
    </div>
  )
}
