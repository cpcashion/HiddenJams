import { motion } from 'framer-motion'
import { ReactNode } from 'react'

export const spring = { type: 'spring', stiffness: 420, damping: 34 } as const
export const rise = (d: number) => ({ initial: { y: 16, opacity: 0 }, animate: { y: 0, opacity: 1 }, transition: { type: 'spring', stiffness: 260, damping: 30, delay: d } } as const)

/** Quiet page indicator, like the TabView page dots in OnboardingView. */
export function Dots({ i, n }: { i: number; n: number }) {
  return (
    <div className="dots" aria-label={`Step ${i + 1} of ${n}`}>
      {Array.from({ length: n }, (_, k) => (
        <motion.div key={k} className="dot" initial={false} animate={{ width: k === i ? 18 : 6, opacity: k === i ? 0.95 : 0.28 }} transition={spring} />
      ))}
    </div>
  )
}

/** LimeCTAButtonStyle: lime Liquid Glass capsule, full width, tap. */
export function CTA({ children, onClick, disabled, testId }: { children: ReactNode; onClick?: () => void; disabled?: boolean; testId?: string }) {
  return <button data-testid={testId} className="glass lime cta" disabled={disabled} onClick={onClick}>{children}</button>
}
