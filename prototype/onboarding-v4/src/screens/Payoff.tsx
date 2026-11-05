import { AnimatePresence, motion } from 'framer-motion'
import { useEffect, useState } from 'react'
import { bus } from '../bus'
import { TRACKS } from '../data'
import { CTA, rise, spring } from '../ui/bits'

const THUMBS = [TRACKS[6], TRACKS[3], TRACKS[1], TRACKS[8]]

export default function Payoff({ replay }: { replay: () => void }) {
  const [done, setDone] = useState(false)
  useEffect(() => { const t = setTimeout(() => { bus.burst++ }, 300); return () => clearTimeout(t) }, [])
  return (
    <div className="screen payoff">
      <motion.div {...rise(0.05)}>
        <h1 className="title">Your first jams are <span className="accent">ready</span></h1>
        <p className="sub">Saved to Spotify. Every song you keep from now on lands here too.</p>
      </motion.div>
      <div className="pay-mid">
        <motion.div className="pastel lavender" initial={{ y: 24, opacity: 0, scale: 0.98 }} animate={{ y: 0, opacity: 1, scale: 1 }} transition={{ ...spring, delay: 0.12 }}>
          <div className="pl-k">Playlist</div>
          <div className="pl-t">Hidden Jams</div>
          <div className="pl-s">12 songs · all under 10K plays</div>
          <div className="thumbs">
            {THUMBS.map((t, k) => (
              <motion.img key={t.file} src={t.cover} alt="" draggable={false} style={{ zIndex: 4 - k }}
                initial={{ x: -12, opacity: 0 }} animate={{ x: 0, opacity: 1 }} transition={{ ...spring, delay: 0.25 + k * 0.06 }} />
            ))}
            <div className="more">+8</div>
          </div>
        </motion.div>
      </div>
      <div className="bottom">
        <AnimatePresence mode="popLayout" initial={false}>
          {!done ? (
            <motion.div key="s" exit={{ opacity: 0 }}>
              <CTA onClick={() => { setDone(true); bus.burst++ }} testId="start">Start digging</CTA>
            </motion.div>
          ) : (
            <motion.div key="d" className="done" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={spring}>
              <div className="title" style={{ fontSize: 20 }}>You’re in</div>
              <div className="caption">This is where the app opens to Discover.</div>
            </motion.div>
          )}
        </AnimatePresence>
        <button className="replay" data-testid="replay" onClick={replay}>Replay onboarding</button>
      </div>
    </div>
  )
}
