import { motion } from 'framer-motion'
import { CSSProperties, ReactNode, useEffect, useState } from 'react'
import { capitalized, genreColors, textOnGenre } from '../genres'

export const spring = { type: 'spring', stiffness: 420, damping: 32 } as const
export const rise = (d: number) => ({ initial: { y: 36, opacity: 0 }, animate: { y: 0, opacity: 1 }, transition: { type: 'spring', stiffness: 260, damping: 26, delay: d } } as const)

export function Sticker({ children, tone = 'paper', rot = -4, style, className = '' }: { children: ReactNode; tone?: 'paper' | 'lime' | 'ink'; rot?: number; style?: CSSProperties; className?: string }) {
  return <span className={`sticker ${tone} ${className}`} style={{ ...style, transform: `rotate(${rot}deg)` }}>{children}</span>
}
export function Starburst({ className = '', style, color = '#C8E86B' }: { className?: string; style?: CSSProperties; color?: string }) {
  const rays = Array.from({ length: 9 }, (_, i) => {
    const a = (i / 9) * Math.PI * 2 + 0.2, r1 = 9 + (i % 2) * 3, r2 = 26 + (i % 3) * 4
    return `M${40 + Math.cos(a) * r1} ${40 + Math.sin(a) * r1}L${40 + Math.cos(a) * r2} ${40 + Math.sin(a) * r2}`
  }).join('')
  return <svg className={`doodle ${className}`} style={style} viewBox="0 0 80 80" fill="none"><path d={rays} stroke={color} strokeWidth="3.4" strokeLinecap="round" /></svg>
}
export function Sparkle({ className = '', style, color = '#F7F3EE' }: { className?: string; style?: CSSProperties; color?: string }) {
  return <svg className={`doodle ${className}`} style={style} viewBox="0 0 40 40" fill="none"><path d="M20 3c1 10 4 15 17 17-13 2-16 7-17 17-1-10-4-15-17-17 13-2 16-7 17-17z" stroke={color} strokeWidth="2.6" strokeLinejoin="round" /></svg>
}

/** Count from 0 to `to` after `delay` ms over `dur` ms (ease-out). */
export function useCountUp(to: number, delay = 0, dur = 1200, active = true) {
  const [v, setV] = useState(0)
  useEffect(() => {
    if (!active) { setV(0); return }
    let raf = 0, t0 = 0
    const to1 = setTimeout(() => {
      const tick = (t: number) => {
        if (!t0) t0 = t
        const k = Math.min(1, (t - t0) / dur)
        setV(to * (1 - Math.pow(1 - k, 3)))
        if (k < 1) raf = requestAnimationFrame(tick)
      }
      raf = requestAnimationFrame(tick)
    }, delay)
    return () => { clearTimeout(to1); cancelAnimationFrame(raf) }
  }, [to, delay, dur, active])
  return v
}

/** Genre pill. Exactly GenrePillContent in GenreSelectionView.swift. */
export function GenrePill({ genre, selected, color, onClick, testId, filled }: { genre: string; selected: boolean; color: string; onClick?: () => void; testId?: string; filled?: boolean }) {
  const on = selected || filled
  const style: CSSProperties = on
    ? { background: color, color: textOnGenre(color), fontWeight: 600, boxShadow: `0 2px 8px ${color}73` }
    : {}
  return (
    <motion.button data-testid={testId} className={`gpill ${on ? 'on' : ''}`} style={style} onClick={onClick}
      animate={{ scale: on ? 1.02 : 1 }} transition={{ type: 'spring', stiffness: 400, damping: 20 }} tabIndex={onClick ? 0 : -1} aria-pressed={on}>
      {capitalized(genre)}
    </motion.button>
  )
}
export { genreColors }
