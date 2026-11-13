import { motion } from 'framer-motion'
import { TRACKS } from '../data'
import { rise } from '../ui/bits'

const ROW_A = TRACKS.slice(0, 8), ROW_B = TRACKS.slice(4).concat(TRACKS.slice(0, 4)).slice(0, 8)

function Marquee({ items, dir, dur }: { items: typeof TRACKS; dir: 1 | -1; dur: number }) {
  const list = [...items, ...items]
  return (
    <div className="mq">
      <div className="mq-in" style={{ animationDuration: `${dur}s`, animationDirection: dir > 0 ? 'normal' : 'reverse' }}>
        {list.map((t, i) => <img key={i} data-cover src={t.cover} alt="" draggable={false} />)}
      </div>
    </div>
  )
}

export default function Connect() {
  return (
    <div className="screen connect">
      <div className="mqzone" data-zone="covers">
        <Marquee items={ROW_A} dir={1} dur={38} />
        <Marquee items={ROW_B} dir={-1} dur={46} />
      </div>
      <div className="ctext">
        <motion.h1 className="display m" data-title {...rise(0.1)}>Find what the<br />big apps<br /><span className="hl">won’t</span> play.</motion.h1>
        <motion.p className="sub tight" data-text {...rise(0.22)}>Streaming pushes what’s trending and promoted. Connect your music and we’ll dig up what you’d never hear otherwise.</motion.p>
        <motion.p className="mono foot" {...rise(0.3)}>We only save songs you keep.</motion.p>
      </div>
    </div>
  )
}
