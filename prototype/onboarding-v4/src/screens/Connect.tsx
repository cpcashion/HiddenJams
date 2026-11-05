import { motion } from 'framer-motion'
import { spring } from '../ui/bits'

const up = (d: number) => ({ initial: { y: 30, opacity: 0 }, animate: { y: 0, opacity: 1 }, transition: { ...spring, delay: d } })

export default function Connect({ next }: { next: () => void }) {
  return (
    <div className="screen connect">
      <div className="fade-top" />
      <div className="bottom">
        <motion.h1 className="display l" {...up(0.05)}>Straight to<br />your <span className="hl">library.</span></motion.h1>
        <motion.p className="sub" {...up(0.12)}>Every keep lands in a Hidden Jams playlist. Connect where you listen.</motion.p>
        <motion.button className="spotify" data-testid="btn-spotify" onClick={next} whileTap={{ scale: 0.97 }} {...up(0.2)}>
          <svg width="30" height="30" viewBox="0 0 24 24" aria-hidden><circle cx="12" cy="12" r="11" fill="#0B0B0F" /><path d="M6.5 9.3c3.8-1.1 8-.8 11.2 1M7.2 12.4c3.1-.9 6.5-.6 9.2.9M7.9 15.3c2.5-.6 5-.4 7.2.7" stroke="#C8E86B" strokeWidth="1.7" strokeLinecap="round" fill="none" /></svg>
          <span>Continue with Spotify</span>
        </motion.button>
        <motion.div className="tiles" {...up(0.28)}>
          <motion.button className="tile glass" data-testid="btn-apple" onClick={next} whileTap={{ scale: 0.95 }}>
            <svg width="22" height="22" viewBox="0 0 24 24" aria-hidden><path d="M9 18V6l10-2v12" stroke="#F7F3EE" strokeWidth="2" fill="none" strokeLinejoin="round" /><circle cx="6.5" cy="18" r="2.5" fill="#F7F3EE" /><circle cx="16.5" cy="16" r="2.5" fill="#F7F3EE" /></svg>
            <span>Apple Music</span>
          </motion.button>
          <motion.button className="tile glass" data-testid="btn-look" onClick={next} whileTap={{ scale: 0.95 }}>
            <svg width="22" height="22" viewBox="0 0 24 24" aria-hidden><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z" stroke="#F7F3EE" strokeWidth="2" fill="none" /><circle cx="12" cy="12" r="3" fill="#F7F3EE" /></svg>
            <span>Look around first</span>
          </motion.button>
        </motion.div>
        <motion.p className="mono foot" {...up(0.34)}>You can connect later in Settings</motion.p>
      </div>
    </div>
  )
}
