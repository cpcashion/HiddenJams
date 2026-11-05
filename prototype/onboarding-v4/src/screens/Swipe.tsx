import { AnimatePresence, animate, motion, useMotionValue, useTransform } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { bus, haptic } from '../bus'
import { TRACKS, fmt, type Track } from '../data'
import { coverColors, roundedTexture } from '../three/textures'
import { Pill, Squiggle, Sticker, spring } from '../ui/bits'

const DECK = TRACKS.slice(0, 8)
const NEED = 3

function TopCard({ t, onGone, cmd }: { t: Track; onGone: (dir: 1 | -1) => void; cmd: { dir: 1 | -1; n: number } | null }) {
  const x = useMotionValue(0)
  const rot = useTransform(x, [-220, 220], [-16, 16])
  const keep = useTransform(x, [20, 110], [0, 1])
  const skip = useTransform(x, [-110, -20], [1, 0])
  const fly = (dir: 1 | -1, v = 0) => {
    haptic(14)
    animate(x, dir * 520, { type: 'spring', stiffness: 220, damping: 30, velocity: v, onComplete: () => onGone(dir) })
  }
  useEffect(() => { if (cmd) fly(cmd.dir) }, [cmd?.n]) // eslint-disable-line
  return (
    <motion.div className="card top" data-testid="card-top" style={{ x, rotate: rot, zIndex: 5 }}
      drag="x" dragElastic={0.9} dragMomentum={false} dragConstraints={{ left: 0, right: 0 }}
      onDragEnd={(_, info) => {
        if (Math.abs(info.offset.x) > 105 || Math.abs(info.velocity.x) > 650) fly(info.offset.x > 0 ? 1 : -1, info.velocity.x)
        else animate(x, 0, { type: 'spring', stiffness: 500, damping: 28 })
      }}
      initial={{ scale: 0.94, y: 14 }} animate={{ scale: 1, y: 0 }} transition={spring}
      whileTap={{ scale: 1.02 }}>
      <CardFace t={t} />
      <motion.div className="stamp keep" style={{ opacity: keep }}>Keep</motion.div>
      <motion.div className="stamp skip" style={{ opacity: skip }}>Skip</motion.div>
    </motion.div>
  )
}

function CardFace({ t }: { t: Track }) {
  return (
    <>
      <img src={t.cover} alt="" draggable={false} />
      <Sticker tone="paper" rot={-6} className="c-tag">{t.tag}</Sticker>
      <Sticker tone="lime" rot={5} className="c-plays">{fmt(t.plays)} plays</Sticker>
    </>
  )
}

export default function Swipe({ next }: { next: () => void }) {
  const [i, setI] = useState(0)
  const [kept, setKept] = useState(0)
  const [cmd, setCmd] = useState<{ dir: 1 | -1; n: number } | null>(null)
  const [hint, setHint] = useState(true)
  const busy = useRef(false)
  const t = DECK[i % DECK.length]
  useEffect(() => {
    roundedTexture(t.cover).then(() => { const c = coverColors.get(t.cover); if (c) bus.cover = c })
  }, [t.cover])
  const gone = (dir: 1 | -1) => { if (dir > 0) setKept((k) => k + 1); setI((v) => v + 1); setHint(false); busy.current = false }
  const press = (dir: 1 | -1) => { if (busy.current) return; busy.current = true; setCmd({ dir, n: Date.now() }) }
  const swiped = i
  return (
    <div className="screen swipe">
      <div className="top-copy">
        <h1 className="display l">Keep what<br /><span className="hl">moves</span> you.</h1>
      </div>
      <div className="deck">
        {[2, 1].map((d) => {
          const n = DECK[(i + d) % DECK.length]
          return (
            <motion.div key={(i + d) + '-' + n.file} className="card under" layout={false}
              initial={false}
              animate={{ x: d === 1 ? 34 : -34, rotate: d === 1 ? 7 : -8, scale: d === 1 ? 0.9 : 0.84, y: d === 1 ? 8 : 14, opacity: d === 1 ? 0.9 : 0.6 }}
              transition={spring} style={{ zIndex: 5 - d }}>
              <CardFace t={n} />
            </motion.div>
          )
        })}
        <AnimatePresence initial={false}>
          <TopCard key={i} t={t} onGone={gone} cmd={cmd} />
        </AnimatePresence>
        <AnimatePresence>
          {hint && (
            <motion.div className="hint" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ delay: 0.6 }}>
              <Squiggle className="hint-arrow" />
              <span>Swipe right<br />to keep</span>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
      <div className="meta">
        <AnimatePresence mode="popLayout" initial={false}>
          <motion.div key={i} initial={{ y: 18, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: -18, opacity: 0 }} transition={spring}>
            <div className="track">{t.track}</div>
            <div className="artist">{t.artist} <span className="dim">· {t.year}</span></div>
          </motion.div>
        </AnimatePresence>
      </div>
      <div className="actions">
        {swiped < NEED ? (
          <>
            <motion.button className="round glass" data-testid="btn-skip" whileTap={{ scale: 0.9 }} onClick={() => press(-1)} aria-label="Skip">
              <svg width="22" height="22" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18" stroke="#F7F3EE" strokeWidth="2.6" strokeLinecap="round" /></svg>
            </motion.button>
            <div className="count"><b>{swiped}</b>/{NEED}</div>
            <motion.button className="round lime" data-testid="btn-keep" whileTap={{ scale: 0.9 }} onClick={() => press(1)} aria-label="Keep">
              <svg width="24" height="24" viewBox="0 0 24 24"><path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" fill="#0B0B0F" /></svg>
            </motion.button>
          </>
        ) : (
          <motion.div style={{ width: '100%' }} initial={{ y: 20, opacity: 0 }} animate={{ y: 0, opacity: 1 }} transition={spring}>
            <Pill onClick={next} testId="swipe-continue">Nice. {kept} kept <span className="arrow">→</span></Pill>
          </motion.div>
        )}
      </div>
    </div>
  )
}
