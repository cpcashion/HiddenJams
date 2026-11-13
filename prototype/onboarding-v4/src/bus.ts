// Tiny mutable bus shared between the DOM screens and the single WebGL scene.
// Read every frame in useFrame; written from gesture handlers. No re-renders.
export const bus = {
  screen: 0,
  pointer: { x: 0, y: 0 },      // -1..1 relative to the phone frame
  tilt: { x: 0, y: 0 },         // device orientation, -1..1
  depth: 0.5,                   // screen 3 slider 0..1
  pulse: 0,                     // genre toggle bump, decays in the scene
  burst: 0,                     // payoff burst trigger counter
  cover: [0.88, 0.34, 0.71] as [number, number, number], // screen 2 glow colour (from album art)
  slide: 0,                     // slide-to-go progress 0..1 (hero reacts)
}

export const haptic = (ms = 8) => {
  try { navigator.vibrate?.(ms) } catch { /* iOS Safari: no-op */ }
}
