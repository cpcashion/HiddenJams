// Tiny mutable bus shared between the DOM screens and the single WebGL scene.
// Read every frame in useFrame; written from gesture handlers. No re-renders.
export const bus = {
  screen: 0,
  pointer: { x: 0, y: 0 },      // -1..1 relative to the phone frame
  tilt: { x: 0, y: 0 },         // device orientation, -1..1
  pop: 0.3,                     // screen 3 popularity 0 (deep) .. 1 (hot), like PopularitySliderSettings
  pulse: 0,                     // genre toggle bump, decays in the scene
  burst: 0,                     // payoff burst trigger counter
  cover: [0.88, 0.34, 0.71] as [number, number, number], // screen 2 glow colour (from album art)
}

export const haptic = (ms = 8) => {
  try { navigator.vibrate?.(ms) } catch { /* iOS Safari: no-op */ }
}
