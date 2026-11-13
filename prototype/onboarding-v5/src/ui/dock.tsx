import { motion } from 'framer-motion'
import { ReactNode } from 'react'
import { spring } from './bits'

/** iOS TabView `.page` dots with `.indexViewStyle(.page(backgroundDisplayMode: .always))` — same as the live OnboardingView. */
export function PageDots({ n, i }: { n: number; i: number }) {
  return (
    <div className="dots" role="tablist" aria-label={`Page ${i + 1} of ${n}`} data-testid="page-dots">
      {Array.from({ length: n }, (_, k) => <i key={k} className={k === i ? 'on' : ''} />)}
    </div>
  )
}

/** LimeCTAButtonStyle: lime capsule, 16pt semibold, brand glass rim. Tap (never slide). */
export function CTA({ children, onClick, disabled, testId = 'next', className = '' }: { children: ReactNode; onClick?: () => void; disabled?: boolean; testId?: string; className?: string }) {
  return (
    <motion.button data-testid={testId} className={`cta ${className}`} disabled={disabled} onClick={onClick}
      whileTap={disabled ? undefined : { scale: 0.97 }} animate={{ opacity: disabled ? 0.38 : 1 }} transition={spring}>
      {children}
    </motion.button>
  )
}

/* Brand marks. PROTOTYPE PLACEHOLDERS: production must use the official, unaltered assets.
   Spotify: full-color icon only on black or white (guideline) -> sits on a white tile.
   Apple Music: the colored music-note icon, never recolored and never the Apple logo -> sits on the same white tile. */
export const SpotifyIcon = ({ size = 22 }: { size?: number }) => (
  <span className="brand-tile" aria-hidden="true">
    <svg width={size} height={size} viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="12" fill="#1ED760" />
      <path d="M5.4 8.6c4.3-1.2 9.1-.8 12.9 1.4" stroke="#0B0B0F" strokeWidth="1.9" strokeLinecap="round" fill="none" />
      <path d="M6.2 12.1c3.6-1 7.4-.6 10.5 1.2" stroke="#0B0B0F" strokeWidth="1.6" strokeLinecap="round" fill="none" />
      <path d="M7 15.3c2.9-.8 5.6-.5 8.1.9" stroke="#0B0B0F" strokeWidth="1.4" strokeLinecap="round" fill="none" />
    </svg>
  </span>
)
export const AppleMusicIcon = ({ size = 22 }: { size?: number }) => (
  <span className="brand-tile" aria-hidden="true">
    <svg width={size} height={size} viewBox="0 0 24 24">
      <defs><linearGradient id="amg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FB5C74" /><stop offset="1" stopColor="#FA233B" /></linearGradient></defs>
      <rect width="24" height="24" rx="5.5" fill="url(#amg)" />
      <path d="M16.6 5.2v9.1a2.4 2.4 0 1 1-1.5-2.2V8.2l-5.2 1.3v6.1a2.4 2.4 0 1 1-1.5-2.2V7.6c0-.4.3-.7.6-.8l6.5-1.6c.4-.1.8.2.8.6z" fill="#fff" />
    </svg>
  </span>
)
