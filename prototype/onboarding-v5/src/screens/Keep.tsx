import { AnimatePresence, animate, motion, useMotionValue, useTransform } from 'framer-motion'
import { useEffect, useRef, useState } from 'react'
import { byFile } from '../data'
import { Sticker, rise } from '../ui/bits'

const DECK = ['nala.jpg', 'ana.jpg', 'yazmin.jpg', 'mndsgn.jpg', 'hermanos.jpg', 'cleo.jpg'].map(byFile)
const PLAYS = [2418, 731, 412, 3290, 1366, 864]
const SCRIPT: ('keep' | 'skip')[] = ['keep', 'skip', 'keep', 'keep']
const wait = (ms: number) => new Promise<void>((r) => setTimeout(r, ms))

/** Auto-playing demo of the app's swipe: nothing for the user to do. */
export default function Keep() {
  const [i, setI] = useState(0)
  const [kept, setKept] = useState<string[]>([])
  const [hint, setHint] = useState<'keep' | 'skip'>('keep')
  const [bump, setBump] = useState(0)
  const x = useMotionValue(0)
  const fingerOp = useMotionValue(0)
  const rot = useTransform(x, [-220, 220], [-16, 16])
  const keepOp = useTransform(x, [20, 110], [0, 1])
  const skipOp = useTransform(x, [-110, -20], [1, 0])
  const alive = useRef(true)

  useEffect(() => {
    alive.current = true
    ;(async () => {
      let n = 0
      await wait(1000)
      while (alive.current) {
        for (const act of SCRIPT) {
          if (!alive.current) return
          setHint(act)
          const dir = act === 'keep' ? 1 : -1
          await wait(650)
          animate(fingerOp, 1, { duration: 0.18 })
          await wait(220)
          await animate(x, dir * 120, { duration: 0.75, ease: [0.3, 0.1, 0.3, 1] })
          await wait(160)
          await animate(x, dir * 560, { duration: 0.34, ease: [0.5, 0, 0.9, 0.6] })
          animate(fingerOp, 0, { duration: 0.1 })
          if (!alive.current) return
          if (act === 'keep') { setKept((k) => [...k, DECK[n % DECK.length].file]); setBump((b) => b + 1) }
          n++; setI(n); x.set(0)
          await wait(900)
        }
        await wait(1500)
        if (!alive.current) return
        setKept([])
      }
    })()
    return () => { alive.current = false }
  }, []) // eslint-disable-line

  const top = DECK[i % DECK.length]
  const n1 = DECK[(i + 1) % DECK.length], n2 = DECK[(i + 2) % DECK.length]
  return (
    <div className="screen keep">
      <motion.h1 className="display l" {...rise(0.1)}>Keep what<br /><span className="hl">moves</span> you.</motion.h1>
      <motion.p className="sub tight" {...rise(0.2)}>Swipe right to save a song to your <b>Hidden Jams</b> playlist. Swipe left to skip.</motion.p>

      <div className="deck" data-zone="deck">
        <img className="card under u2" src={n2.cover} alt="" />
        <img className="card under u1" src={n1.cover} alt="" />
        <motion.div className="card top" data-testid="card-top" style={{ x, rotate: rot }}>
          <img src={top.cover} alt="" draggable={false} />
          <Sticker tone="paper" rot={-6} className="c-tag">#{top.genre.toLowerCase().replace('r&b/soul', 'soul').replace('indie pop', 'indie').replace('indie rock', 'psych')}</Sticker>
          <Sticker tone="lime" rot={5} className="c-plays">{PLAYS[i % PLAYS.length].toLocaleString('en-US')} plays</Sticker>
          <motion.div className="stamp keep" style={{ opacity: keepOp }}>Keep</motion.div>
          <motion.div className="stamp skip" style={{ opacity: skipOp }}>Skip</motion.div>
          <motion.div className="finger" style={{ opacity: fingerOp }} aria-hidden />
        </motion.div>
      </div>

      <div className="hintrow" data-text>
        <AnimatePresence mode="wait" initial={false}>
          <motion.span key={hint} className="hint mono" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.18 }}>
            {hint === 'keep' ? 'Swipe right to keep  →' : '←  Swipe left to skip'}
          </motion.span>
        </AnimatePresence>
      </div>

      <motion.div className="plist" {...rise(0.3)} data-testid="playlist-chip">
        <div className="mosaic">
          {[0, 1, 2, 3].map((k) => {
            const f = kept[kept.length - 1 - k]
            return <div key={k} className="mcell">{f && <motion.img key={f + kept.length} src={byFile(f).cover} alt="" initial={{ scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: 'spring', stiffness: 300, damping: 18 }} />}</div>
          })}
        </div>
        <div className="pl-t"><b>Hidden Jams</b><span>Playlist in your music app</span></div>
        <motion.div key={bump} className="pl-n" initial={{ scale: bump ? 1.35 : 1 }} animate={{ scale: 1 }} transition={{ type: 'spring', stiffness: 400, damping: 12 }}>
          <b>{kept.length}</b> saved
        </motion.div>
      </motion.div>
    </div>
  )
}
