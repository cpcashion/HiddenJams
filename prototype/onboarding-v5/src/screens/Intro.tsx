import { motion } from 'framer-motion'
import { useEffect, useState } from 'react'
import { TRACKS } from '../data'
import { Sparkle, Starburst, rise, useCountUp } from '../ui/bits'

// Cover cloud lives in its own zone ABOVE the title (never behind text). x/y are % of the zone.
const CLOUD = [
  { f: 'nala.jpg', x: 4, y: 8, s: 92, r: -7 }, { f: 'sault.jpg', x: 70, y: 4, s: 84, r: 6 },
  { f: 'cleo.jpg', x: 33, y: 2, s: 70, r: 3 }, { f: 'khruangbin.jpg', x: 44, y: 42, s: 96, r: -4 },
  { f: 'tirzah.jpg', x: 1, y: 56, s: 76, r: 5 }, { f: 'arooj.jpg', x: 76, y: 50, s: 80, r: -6 },
  { f: 'mndsgn.jpg', x: 22, y: 36, s: 58, r: 8 }, { f: 'men.jpg', x: 62, y: 28, s: 56, r: -3 },
]
const LIT = 'khruangbin.jpg' // the one that stays "heard"

export default function Intro() {
  const [dim, setDim] = useState(false)
  useEffect(() => { const t = setTimeout(() => setDim(true), 1500); return () => clearTimeout(t) }, [])
  const pct = useCountUp(88, 1500, 1500)
  return (
    <div className="screen intro">
      <div className="cloud" data-zone="covers">
        {CLOUD.map((c, i) => {
          const t = TRACKS.find((x) => x.file === c.f)!
          const lit = c.f === LIT
          return (
            <motion.img key={c.f} data-cover src={t.cover} alt="" draggable={false}
              className={`cv ${dim && !lit ? 'quiet' : ''} ${dim && lit ? 'lit' : ''}`}
              style={{ left: `${c.x}%`, top: `${c.y}%`, width: c.s * 1.14, height: c.s * 1.14, transitionDelay: dim ? `${i * 130}ms` : '0ms' }}
              initial={{ opacity: 0, scale: 0.6, rotate: c.r - 10 }} animate={{ opacity: 1, scale: 1, rotate: c.r }}
              transition={{ type: 'spring', stiffness: 160, damping: 18, delay: 0.1 + i * 0.07 }} />
          )
        })}
        <Sparkle className="d-spark" />
      </div>
      <div className="bottom">
        <motion.h1 className="display xl" data-title {...rise(0.2)}>
          Most music<br />never gets<br /><span className="hl">heard.</span>
          <Starburst className="d-star" />
        </motion.h1>
        <motion.p className="sub stat" data-text {...rise(0.34)}>
          <b className="pct">{Math.round(pct)}%</b> of songs on streaming got 1,000 plays or fewer last year. Hidden Jams finds them.
        </motion.p>
        <motion.p className="mono src" {...rise(0.44)}>Source: Luminate 2025 Year-End Music Report</motion.p>
      </div>
    </div>
  )
}
