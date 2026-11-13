import { motion } from 'framer-motion'
import { byFile } from '../data'
import { DEMO } from '../demo'
import { genreColors } from '../genres'
import { GenrePill, Sticker, rise, useCountUp } from '../ui/bits'

const TIERS = [['KNOWN', '#9C98A6'], ['EMERGING', '#8EE6B8'], ['RARE', '#C9A0F0'], ['ULTRA RARE', '#FF8FC7'], ['MYTHIC', '#C8E86B']]

export function Genres({ picked }: { picked: string[] }) {
  const colors = genreColors(DEMO.genres.map((x) => x.g))
  return (
    <div className="screen reveal">
      <div className="eyebrow mono">Your sound · demo data</div>
      <motion.h1 className="display l" {...rise(0.05)}>You dig<br /><span className="hl">soul</span> and jazz.</motion.h1>
      <div className="gbars" data-zone="bars">
        {DEMO.genres.map((x, k) => (
          <motion.div className="gbar" key={x.g} initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.35 + k * 0.14, type: 'spring', stiffness: 220, damping: 24 }}>
            <GenrePill genre={x.g} selected filled color={colors[x.g]} />
            <div className="track"><motion.i style={{ background: colors[x.g] }} initial={{ width: 0 }} animate={{ width: `${x.pct * 2.6}%` }} transition={{ delay: 0.5 + k * 0.14, duration: 0.9, ease: 'easeOut' }} /></div>
            <span className="pc mono">{x.pct}%</span>
            {picked.includes(x.g) && <span className="pick mono">your pick</span>}
          </motion.div>
        ))}
      </div>
      <motion.p className="sub tight" {...rise(0.6)}>That’s most of your library. We’ll still dig for the unexpected.</motion.p>
    </div>
  )
}

export function RarityScore() {
  const n = useCountUp(DEMO.rarity.score, 500, 1500)
  const R = 78, C = 2 * Math.PI * R
  return (
    <div className="screen reveal">
      <div className="eyebrow mono">Your rarity · demo data</div>
      <motion.h1 className="display l" {...rise(0.05)}>Your taste<br />runs <span className="hl">rare.</span></motion.h1>
      <div className="score" data-zone="score">
        <svg viewBox="0 0 200 200">
          <circle cx="100" cy="100" r={R} className="ring-bg" />
          <motion.circle cx="100" cy="100" r={R} className="ring-fg" strokeDasharray={C} initial={{ strokeDashoffset: C }} animate={{ strokeDashoffset: C * (1 - DEMO.rarity.score / 100) }} transition={{ delay: 0.5, duration: 1.5, ease: 'easeOut' }} transform="rotate(-90 100 100)" />
        </svg>
        <div className="score-n"><b data-testid="rarity-score">{Math.round(n)}</b><span>/ 100</span></div>
      </div>
      <motion.div className="ladder" {...rise(0.4)}>
        {TIERS.map(([l, c]) => <div key={l} className={l === DEMO.rarity.tier ? 'on' : ''}><i style={{ background: c }} /><span className="mono">{l}</span></div>)}
      </motion.div>
      <motion.p className="sub tight c" {...rise(0.55)}><b>{DEMO.rarity.tag[0].toUpperCase() + DEMO.rarity.tag.slice(1)}.</b> You already listen well off the charts. Let’s go deeper.</motion.p>
    </div>
  )
}

export function Signature() {
  return (
    <div className="screen reveal">
      <div className="eyebrow mono">Your artists · demo data</div>
      <motion.h1 className="display l" {...rise(0.05)}>Your<br /><span className="hl">signature</span><br />artists.</motion.h1>
      <div className="sigs" data-zone="artists">
        {DEMO.signature.map((a, k) => {
          const t = byFile(a.f)
          return (
            <motion.div key={a.f} className={`sg sg${k}`} initial={{ opacity: 0, y: 40, rotate: 0 }} animate={{ opacity: 1, y: 0, rotate: [-5, 0, 4][k] }} transition={{ delay: 0.3 + k * 0.2, type: 'spring', stiffness: 160, damping: 16 }}>
              <img src={t.cover} alt="" />
              <b>{t.artist}</b><span className="mono">{a.n} saved songs</span>
            </motion.div>
          )
        })}
      </div>
      <motion.p className="sub tight c" {...rise(0.9)}>The ones you keep coming back to.</motion.p>
    </div>
  )
}

export function Deepest({ picked }: { picked: string[] }) {
  const t = byFile(DEMO.deepest.f)
  const colors = genreColors(picked)
  return (
    <div className="screen reveal">
      <div className="eyebrow mono">Your deepest cut · demo data</div>
      <motion.h1 className="display l" {...rise(0.05)}>Your <span className="hl">deepest</span><br />cut.</motion.h1>
      <motion.div className="deep" data-zone="deep" initial={{ opacity: 0, scale: 0.8, rotate: -6 }} animate={{ opacity: 1, scale: 1, rotate: -2 }} transition={{ delay: 0.3, type: 'spring', stiffness: 150, damping: 16 }}>
        <img src={t.cover} alt="" />
        <Sticker tone="lime" rot={5} className="c-plays">{DEMO.deepest.plays} plays</Sticker>
      </motion.div>
      <motion.p className="deep-t" {...rise(0.7)}><b>{t.track}</b><span>{t.artist}</span></motion.p>
      <motion.p className="sub tight c" {...rise(0.8)}>Hardly anyone has heard it. You have.</motion.p>
      <motion.div className="starts" data-testid="starting-with" {...rise(0.9)}>
        <span className="mono">Starting with</span>
        {picked.length ? picked.slice(0, 5).map((g) => <GenrePill key={g} genre={g} selected filled color={colors[g] ?? '#C8E86B'} />) : <em>a bit of everything</em>}
      </motion.div>
    </div>
  )
}

export function Fresh({ picked }: { picked: string[] }) {
  const colors = genreColors(picked)
  return (
    <div className="screen reveal">
      <div className="eyebrow mono">Empty library</div>
      <motion.h1 className="display l" {...rise(0.05)}>Fresh<br /><span className="hl">start.</span></motion.h1>
      <motion.p className="sub" {...rise(0.2)}>Nothing saved yet, so we’ll start from what you picked. Keep a few songs and your taste profile fills in on its own.</motion.p>
      <motion.div className="starts left" {...rise(0.35)}>
        <span className="mono">Starting with</span>
        {picked.length ? picked.slice(0, 8).map((g) => <GenrePill key={g} genre={g} selected filled color={colors[g] ?? '#C8E86B'} />) : <em>a bit of everything</em>}
      </motion.div>
    </div>
  )
}
