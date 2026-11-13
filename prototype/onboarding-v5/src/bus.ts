// Shared with the WebGL glow only (read each frame).
export const bus = { screen: 0, pulse: 0 }
export const haptic = (ms = 8) => { try { navigator.vibrate?.(ms) } catch { /* iOS Safari: no-op */ } }
