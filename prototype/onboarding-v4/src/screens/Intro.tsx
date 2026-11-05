import { motion } from 'framer-motion'
import { CTA, rise } from '../ui/bits'

export default function Intro({ next }: { next: () => void }) {
  return (
    <div className="screen intro">
      <div className="bottom">
        <motion.h1 className="large" {...rise(0.1)}>
          <span className="light">Songs nobody’s</span><br />heard <span className="accent">yet</span>.
        </motion.h1>
        <motion.p className="sub" {...rise(0.18)}>Music discovery below the charts, one swipe at a time.</motion.p>
        <motion.div {...rise(0.26)}><CTA onClick={next} testId="intro-next">Get started</CTA></motion.div>
      </div>
    </div>
  )
}
