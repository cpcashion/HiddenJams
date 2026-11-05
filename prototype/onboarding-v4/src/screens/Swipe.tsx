import { AnimatePresence, animate, motion, useMotionValue, useTransform } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { bus, haptic } from '../bus'
import { TRACKS, fmt, type Track } from '../data'
import { coverColors, roundedTexture } from '../three/textures'
import { CTA, rise, spring } from '../ui/bits'

const DECK = TRACKS.slice(0, 8)
const NEED = 3

function TopCard({ t, onGone, cmd }: { t: Track; onGone: (dir: 1 | -1) => void; cmd: { dir: 1 | -1; n: number } | null }) {
  const x = useMotionValue(0)
  const rot = useTransform(x, [-220, 220], [-12, 12])
  const keep = useTransform(x, [20, 100], [0, 1])
  const skip = useTransform(x, [-100, -20], [1, 0])
  const fly = (dir: 1 | -1, v = 0) => {
    haptic(12)
    animate(x, dir * 520, { type: 'spring', stiffness: 220, damping: 30, velocity: v, onComplete: () => onGone(dir) })
  }
  const born = useRef(performance.now())
  // Only obey button presses made after this card appeared (a fresh card must not inherit the last fling).
  useEffect(() => { if (cmd && cmd.n > born.current) fly(cmd.dir) }, [cmd?.n]) // eslint-disable-line
  return (
    <motion.div className="card top" data-testid="card-top" style={{ x, rotate: rot, zIndex: 5 }}
      drag="x" dragElastic={0.9} dragMomentum={false} dragConstraints={{ left: 0, right: 0 }}
      onDragEnd={(_, info) => {
        if (Math.abs(info.offset.x) > 105 || Math.abs(info.velocity.x) > 650) fly(info.offset.x > 0 ? 1 : -1, info.velocity.x)
        else animate(x, 0, { type: 'spring', stiffness: 500, damping: 30 })
      }}
      initial={{ scale: 0.96, y: 10 }} animate={{ scale: 1, y: 0 }} transition={spring}>
      <CardFace t={t} />
      <motion.div className="badge keep" style={{ opacity: keep }}>Keep</motion.div>
      <motion.div className="badge skip" style={{ opacity: skip }}>Skip</motion.div>
    </motion.div>
  )
}

function CardFace({ t }: { t: Track }) {
  return (
    <>
      <img src={t.cover} alt="" draggable={false} />
      <div className="info">
        <div className="tn">{t.track}</div>
        <div className="ta">{t.artist}</div>
        <div className="tm">{fmt(t.plays)} plays · {t.genre}</div>
      </div>
    </>
  )
}

export default function Swipe({ next }: { next: () => void }) {
  const [i, setI] = useState(0)
  const [kept, setKept] = useState(0)
  const [cmd, setCmd] = useState<{ dir: 1 | -1; n: number } | null>(null)
  const busy = useRef(false)
  const t = DECK[i % DECK.length]
  useEffect(() => {
    roundedTexture(t.cover).then(() => { const c = coverColors.get(t.cover); if (c) bus.cover = c })
  }, [t.cover])
  const gone = (dir: 1 | -1) => { if (dir > 0) setKept((k) => k + 1); setI((v) => v + 1); busy.current = false }
  const press = (dir: 1 | -1) => { if (busy.current) return; busy.current = true; setCmd({ dir, n: performance.now() }) }
  const done = i >= NEED
  return (
    <div className="screen swipe">
      <motion.div {...rise(0.05)}>
        <h1 className="title">Keep what moves you</h1>
        <p className="sub">Swipe right to save a song, left to skip it.</p>
      </motion.div>
      <div className="deck">
        {[1].map((d) => {
          const n = DECK[(i + d) % DECK.length]
          return (
            <motion.div key={(i + d) + '-' + n.file} className="card under" initial={false}
              animate={{ scale: 0.94, y: 14, opacity: 0.55 }} transition={spring} style={{ zIndex: 4 }}>
              <CardFace t={n} />
            </motion.div>
          )
        })}
        <AnimatePresence initial={false}>
          <TopCard key={i} t={t} onGone={gone} cmd={cmd} />
        </AnimatePresence>
      </div>
      <div className="actions">
        {!done ? (
          <>
            <button className="glass subtle circle" data-testid="btn-skip" onClick={() => press(-1)} aria-label="Skip">
              <svg width="20" height="20" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" /></svg>
            </button>
            <div className="count">{i} of {NEED}</div>
            <button className="glass lime circle" data-testid="btn-keep" onClick={() => press(1)} aria-label="Keep">
              <svg width="22" height="22" viewBox="0 0 24 24"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" fill="#000" /></svg>
            </button>
          </>
        ) : (
          <motion.div style={{ width: '100%' }} initial={{ y: 12, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={spring}>
            <CTA onClick={next} testId="swipe-continue">Continue</CTA>
            <div className="caption" style={{ textAlign: 'center', marginTop: 10 }}>{kept} saved · you can keep going in Discover</div>
          </motion.div>
        )}
      </div>
    </div>
  )
}
