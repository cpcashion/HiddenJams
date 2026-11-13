import { motion } from 'framer-motion'
import { byFile, fmt } from '../data'
import { rise, useCountUp } from '../ui/bits'

// Tier names + taglines are the app's own (RarityService.Tier). Plays/scores are sample numbers.
const TIERS = {
  known: { label: 'KNOWN', tag: 'gaining traction', c: '#9C98A6' },
  emerging: { label: 'EMERGING', tag: 'on the rise', c: '#8EE6B8' },
  rare: { label: 'RARE', tag: 'a true hidden gem', c: '#C9A0F0' },
  ultra: { label: 'ULTRA RARE', tag: 'deeper than deep cuts', c: '#FF8FC7' },
  mythic: { label: 'MYTHIC', tag: 'virtually undiscovered', c: '#C8E86B' },
} as const
const ROWS = [
  { f: 'men.jpg', plays: 41800000, score: 9, tier: TIERS.known },
  { f: 'khruangbin.jpg', plays: 6200000, score: 27, tier: TIERS.emerging },
  { f: 'cleo.jpg', plays: 480000, score: 51, tier: TIERS.rare },
  { f: 'arooj.jpg', plays: 38000, score: 78, tier: TIERS.ultra },
  { f: 'yazmin.jpg', plays: 412, score: 96, tier: TIERS.mythic },
]

function Row({ r, k }: { r: (typeof ROWS)[number]; k: number }) {
  const t = byFile(r.f)
  const d = 0.55 + k * 0.7
  const score = useCountUp(r.score, d * 1000 + 150, 700)
  const last = k === ROWS.length - 1
  return (
    <motion.div className={`rrow ${last ? 'last' : ''}`} data-testid={`rarity-row-${k}`}
      initial={{ opacity: 0, x: -24, scale: 0.97 }} animate={{ opacity: 1, x: 0, scale: 1 }} transition={{ type: 'spring', stiffness: 220, damping: 22, delay: d }}>
      <img src={t.cover} alt="" />
      <div className="rr-t"><b>{t.track}</b><span>{t.artist}</span></div>
      <div className="rr-p"><b>{r.plays >= 1e6 ? `${(r.plays / 1e6).toFixed(1)}M` : fmt(r.plays)}</b><span>plays</span></div>
      <div className="rr-s" style={{ background: r.tier.c }}><b>{Math.round(score)}</b><span>{r.tier.label}</span></div>
    </motion.div>
  )
}

/** No interaction: the list builds itself top (charts) to bottom (deep cuts). */
export default function Rarity() {
  return (
    <div className="screen rarity">
      <motion.h1 className="display l" {...rise(0.1)}>Fewer plays.<br /><span className="hl">Rarer</span> finds.</motion.h1>
      <motion.p className="sub tight" {...rise(0.2)}>Every song gets a Rarity score. The less it’s been heard, the higher it climbs.</motion.p>
      <div className="descent" data-zone="rows">
        <div className="rail"><motion.i initial={{ scaleY: 0 }} animate={{ scaleY: 1 }} transition={{ duration: 3.4, delay: 0.5, ease: 'easeInOut' }} /></div>
        <div className="rows">{ROWS.map((r, k) => <Row key={r.f} r={r} k={k} />)}</div>
      </div>
      <motion.p className="mono src" initial={{ opacity: 0 }} animate={{ opacity: 0.55 }} transition={{ delay: 3.9 }}>Sample songs and numbers</motion.p>
    </div>
  )
}
