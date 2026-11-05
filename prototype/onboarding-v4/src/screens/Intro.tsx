import { motion } from 'framer-motion'
import SlideToGo from '../ui/SlideToGo'
import { Sparkle, Starburst } from '../ui/bits'

const rise = (d: number) => ({ initial: { y: 40, opacity: 0 }, animate: { y: 0, opacity: 1 }, transition: { type: 'spring', stiffness: 260, damping: 26, delay: d } } as const)

export default function Intro({ next }: { next: () => void }) {
  return (
    <div className="screen intro">
      <div className="hero-space" />
      <div className="bottom">
        <motion.h1 className="display xl" {...rise(0.15)}>
          Songs<br />nobody’s<br />heard. <span className="hl">Yet.</span>
          <Starburst className="d-star" />
        </motion.h1>
        <motion.p className="sub" {...rise(0.28)}>Music discovery below the charts. <b>One swipe at a time.</b></motion.p>
        <motion.div {...rise(0.38)}><SlideToGo label="Slide to start" onDone={next} testId="slide-intro" /></motion.div>
        <Sparkle className="d-spark" />
      </div>
    </div>
  )
}
