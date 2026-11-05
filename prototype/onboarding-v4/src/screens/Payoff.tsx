import { motion } from 'framer-motion'
import { useEffect, useState } from 'react'
import { bus } from '../bus'
import { TRACKS } from '../data'
import SlideToGo from '../ui/SlideToGo'
import { Circle, Sparkle, Squiggle, Starburst, Sticker, spring } from '../ui/bits'

const STACK = [TRACKS[6], TRACKS[3], TRACKS[1]]
const out = (x: number, y: number, r: number, d: number) => ({
  initial: { x: 0, y: 40, scale: 0.2, rotate: 0, opacity: 0 },
  animate: { x, y, scale: 1, rotate: r, opacity: 1 },
  transition: { type: 'spring', stiffness: 260, damping: 14, delay: d },
} as const)

export default function Payoff({ replay }: { replay: () => void }) {
  const [done, setDone] = useState(false)
  useEffect(() => { const t = setTimeout(() => { bus.burst++; bus.pulse = 1 }, 250); return () => clearTimeout(t) }, [])
  return (
    <div className="screen payoff">
      <div className="stack-area">
        <div className="stack">
          {STACK.map((t, k) => (
            <motion.img key={t.file} src={t.cover} alt="" className="scard" draggable={false}
              initial={{ y: 120, rotate: 0, opacity: 0 }} animate={{ y: [0, -6, -12][k], x: [-38, 34, 0][k], rotate: [-11, 9, -2][k], opacity: 1 }}
              transition={{ ...spring, delay: 0.05 + k * 0.08 }} style={{ zIndex: k }} />
          ))}
          <motion.div className="doodles" initial="i" animate="a">
            <motion.div className="dd d1" {...out(-118, -112, -12, 0.35)}><Starburst /></motion.div>
            <motion.div className="dd d2" {...out(122, -96, 10, 0.42)}><Sparkle /></motion.div>
            <motion.div className="dd d3" {...out(-128, 70, -6, 0.5)}><Squiggle /></motion.div>
            <motion.div className="dd d4" {...out(116, 92, 8, 0.46)}><Sticker tone="lime" rot={0}>12 jams</Sticker></motion.div>
            <motion.div className="dd d5" {...out(-92, -158, 0, 0.55)}><Sticker tone="paper" rot={0}>#soul</Sticker></motion.div>
            <motion.div className="dd d6" {...out(84, -168, 0, 0.6)}><Sparkle color="#C8E86B" /></motion.div>
          </motion.div>
        </div>
      </div>
      <div className="bottom">
        <h1 className="display l">Your first<br /><span className="ring-word">jams<Circle className="ringd" /></span>are<br />ready.</h1>
        <p className="sub">12 songs, all under 10K plays, saved to <b>Hidden Jams</b> on Spotify.</p>
        
          {!done ? (
            <motion.div key="s"><SlideToGo label="Start digging" onDone={() => { setDone(true); bus.burst++ }} testId="slide-start" /></motion.div>
          ) : (
            <motion.div key="d" className="done" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
              <div className="done-pill">You’re in. <span className="dim">This is where the app opens.</span></div>
              <button className="replay" data-testid="replay" onClick={replay}>Replay onboarding</button>
            </motion.div>
          )}
        
        {!done && <button className="replay small" onClick={replay}>Replay</button>}
      </div>
    </div>
  )
}
