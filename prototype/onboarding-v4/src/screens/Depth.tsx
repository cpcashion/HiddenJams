import { useEffect, useRef, useState } from 'react'
import { motion } from 'framer-motion'
import { bus, haptic } from '../bus'
import { CTA, rise } from '../ui/bits'

// Same mappings as PopularitySliderSettings.swift (0 = most obscure, 1 = most popular).
const level = (v: number) => v < 0.2 ? 'Deep Cuts' : v < 0.4 ? 'Hidden Gems' : v < 0.6 ? 'Underground' : v < 0.8 ? 'Rising Stars' : 'Mainstream'
const threshold = (v: number) => 15 + Math.floor(75 * v)
const followers = (v: number) => Math.round(10000 * Math.pow(50, Math.min(1, Math.max(0, v))))
const short = (n: number) => n >= 1e6 ? (n / 1e6).toFixed(1).replace('.0', '') + 'M' : Math.round(n / 1e3) + 'K'

export default function Depth({ next }: { next: () => void }) {
  const [v, setV] = useState(bus.pop)
  const track = useRef<HTMLDivElement>(null)
  const dragging = useRef(false)
  const lv = level(v)
  const prev = useRef(lv)
  useEffect(() => { bus.pop = v }, [v])
  useEffect(() => { if (prev.current !== lv) { haptic(8); prev.current = lv } }, [lv])
  const set = (clientX: number) => {
    const r = track.current!.getBoundingClientRect()
    setV(Math.min(1, Math.max(0, (clientX - r.left) / r.width)))
  }
  return (
    <div className="screen depth">
      <motion.div {...rise(0.05)}>
        <h1 className="title">How deep do you dig?</h1>
        <p className="sub">Fewer people in the crowd means rarer finds. You can change this on the Dashboard.</p>
      </motion.div>
      <div className="crowd-space" />
      <motion.div {...rise(0.12)}>
        <div className="numeral">
          <div className="n" data-testid="plays">≤ {short(followers(v))}</div>
          <div className="c">followers per artist</div>
        </div>
        <div className="panel">
          <div className="p-head">
            <span className="p-level" data-testid="depth-word">{lv}</span>
            <span className="p-pop">Popularity ≤ {threshold(v)}</span>
          </div>
          <div className="p-row">
            <div className="p-end">
              <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden><path d="M6 3h12l4 6-10 12L2 9z" fill="none" stroke="#C9A0F0" strokeWidth="1.8" strokeLinejoin="round" /><path d="M2 9h20M9 3l3 18 3-18" fill="none" stroke="#C9A0F0" strokeWidth="1.2" /></svg>
              Deep
            </div>
            <div className="slider" ref={track} data-testid="depth-slider"
              onPointerDown={(e) => { dragging.current = true; (e.currentTarget as Element).setPointerCapture?.(e.pointerId); set(e.clientX) }}
              onPointerMove={(e) => dragging.current && set(e.clientX)}
              onPointerUp={() => { dragging.current = false }} onPointerCancel={() => { dragging.current = false }}>
              <div className="rail" />
              <div className="rail-fill" style={{ width: `${v * 100}%` }} />
              <div className="glass lime thumb" style={{ left: `${v * 100}%` }} />
            </div>
            <div className="p-end">
              <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden><path d="M12 22c4.4 0 7-3 7-7 0-4-3-6-4-10-2 2-3 4-3 6-1-1-2-2-2-4-3 3-5 5-5 8 0 4 2.6 7 7 7z" fill="none" stroke="#F9C9A8" strokeWidth="1.8" strokeLinejoin="round" /></svg>
              Hot
            </div>
          </div>
        </div>
        <div className="actions"><CTA onClick={next} testId="depth-continue">Continue</CTA></div>
      </motion.div>
    </div>
  )
}
