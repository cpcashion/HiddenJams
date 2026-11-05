import { motion } from 'framer-motion'
import { rise } from '../ui/bits'

export default function Connect({ next }: { next: () => void }) {
  return (
    <div className="screen connect">
      <div className="fade-top" />
      <div className="bottom" style={{ zIndex: 2 }}>
        <motion.div {...rise(0.05)} style={{ marginBottom: 20 }}>
          <h1 className="title">Connect your music</h1>
          <p className="sub">Every song you keep lands in one Hidden Jams playlist, so it’s there when you want it.</p>
        </motion.div>
        <motion.button className="glass lime cta" data-testid="btn-spotify" onClick={next} {...rise(0.12)}>
          <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden><circle cx="12" cy="12" r="11" fill="#000" /><path d="M6.5 9.3c3.8-1.1 8-.8 11.2 1M7.2 12.4c3.1-.9 6.5-.6 9.2.9M7.9 15.3c2.5-.6 5-.4 7.2.7" stroke="#C8E86B" strokeWidth="1.7" strokeLinecap="round" fill="none" /></svg>
          Continue with Spotify
        </motion.button>
        <motion.button className="glass subtle outline cta" data-testid="btn-apple" onClick={next} {...rise(0.16)}>
          <svg width="16" height="18" viewBox="0 0 17 20" aria-hidden><path fill="#fff" d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9C3.6 4.8 2 5.8 1.1 7.4c-1.9 3.2-.5 8 1.3 10.6.9 1.3 1.9 2.7 3.3 2.6 1.3-.1 1.8-.9 3.4-.9s2 .9 3.4.8c1.4 0 2.3-1.3 3.2-2.6 1-1.5 1.4-2.9 1.4-3-.1 0-2.9-1.1-3-4.3zM11.5 3c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.3 2-1.1 3.1 1.1.1 2.3-.6 3-1.5z" /></svg>
          Connect with Apple Music
        </motion.button>
        <motion.button className="textbtn" data-testid="btn-look" onClick={next} {...rise(0.2)}>Look around first</motion.button>
        <p className="caption fine">We’ll never post or modify your music without permission.</p>
      </div>
    </div>
  )
}
