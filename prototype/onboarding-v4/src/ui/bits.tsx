import { motion } from 'framer-motion'
import { CSSProperties, ReactNode, useLayoutEffect, useRef, useState } from 'react'

export const spring = { type: 'spring', stiffness: 420, damping: 32 } as const

/** Sticker tag: a little rotated label like a sticker on a record sleeve. */
export function Sticker({ children, tone = 'paper', rot = -4, style, className = '' }: { children: ReactNode; tone?: 'paper' | 'lime' | 'ink'; rot?: number; style?: CSSProperties; className?: string }) {
  return <span className={`sticker ${tone} ${className}`} style={{ ...style, transform: `rotate(${rot}deg)` }}>{children}</span>
}

/** Hand-drawn doodles (stroke only, sparse). */
export function Squiggle({ className = '', style, color = '#F7F3EE' }: { className?: string; style?: CSSProperties; color?: string }) {
  return (
    <svg className={`doodle ${className}`} style={style} viewBox="0 0 120 90" fill="none">
      <path d="M8 18c14-10 30-6 30 8s-20 18-14 30 32 8 44-2 22-22 40-6" stroke={color} strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M96 40l12 9-14 6" stroke={color} strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
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
export function Circle({ className = '', style, color = '#C8E86B' }: { className?: string; style?: CSSProperties; color?: string }) {
  return <svg className={`doodle ${className}`} style={style} viewBox="0 0 200 80" fill="none" preserveAspectRatio="none"><path d="M30 12C80 0 190 6 192 38S70 82 22 64 6 20 70 10" stroke={color} strokeWidth="3" strokeLinecap="round" /></svg>
}

/** Scales a single line of display type so it fills the available width exactly. */
export function FitText({ children, max = 400, className = '', style }: { children: string; max?: number; className?: string; style?: CSSProperties }) {
  const box = useRef<HTMLDivElement>(null), txt = useRef<HTMLSpanElement>(null)
  const [fs, setFs] = useState(80)
  useLayoutEffect(() => {
    const fit = () => {
      if (!box.current || !txt.current) return
      const cur = parseFloat(getComputedStyle(txt.current).fontSize)
      const w = txt.current.getBoundingClientRect().width
      if (w > 0) setFs(Math.min(max, (box.current.clientWidth / w) * cur * 0.995))
    }
    fit(); document.fonts?.ready.then(fit)
    window.addEventListener('resize', fit); return () => window.removeEventListener('resize', fit)
  }, [children, max])
  return <div ref={box} className={`fit ${className}`} style={style}><span ref={txt} style={{ fontSize: fs }}>{children}</span></div>
}

export function Progress({ i, n }: { i: number; n: number }) {
  return (
    <div className="progress" aria-label={`Step ${i + 1} of ${n}`}>
      {Array.from({ length: n }, (_, k) => (
        <div key={k} className="seg"><motion.div className="seg-in" initial={false} animate={{ scaleX: k <= i ? 1 : 0, opacity: k === i ? 1 : 0.55 }} transition={spring} style={{ background: k === i ? '#C8E86B' : '#F7F3EE' }} /></div>
      ))}
    </div>
  )
}

export function Pill({ children, onClick, kind = 'lime', disabled, testId, className = '' }: { children: ReactNode; onClick?: () => void; kind?: 'lime' | 'glass'; disabled?: boolean; testId?: string; className?: string }) {
  return (
    <motion.button data-testid={testId} className={`pill ${kind} ${className}`} disabled={disabled} onClick={onClick}
      whileTap={disabled ? undefined : { scale: 0.96 }} animate={{ opacity: disabled ? 0.38 : 1 }} transition={spring}>
      {children}
    </motion.button>
  )
}
