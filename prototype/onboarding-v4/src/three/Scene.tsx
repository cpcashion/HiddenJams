import { Canvas, useFrame, useThree } from '@react-three/fiber'
import { useEffect, useMemo, useRef, useState } from 'react'
import * as THREE from 'three'
import { bus } from '../bus'
import { APPICON, TRACKS } from '../data'
import { dotTexture, glowTexture, roundedTexture } from './textures'

// Theme.swift tokens
const INK = new THREE.Color('#0B0B0F')
const MAGENTA = new THREE.Color('#E056B5')
const LIME = new THREE.Color('#C8E86B')

/* ------------------------------------------------------------------ */
/* AmbientBackground.swift as a shader: plum -> ink gradient with the   */
/* magenta bloom top-left and violet bloom top-right. Barely moves.     */
/* ------------------------------------------------------------------ */
const glowFrag = /* glsl */ `
precision highp float;
uniform float uTime; uniform vec2 uRes; uniform vec3 uTint; uniform float uTintI; uniform vec2 uTintP;
varying vec2 vUv;
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
float bloom(vec2 p, vec2 c, float r, float b){ return 1.0 - smoothstep(r - b, r + b, length(p - c)); }
void main(){
  float hw = uRes.y / uRes.x;                 // height in widths
  vec2 p = vec2(vUv.x, (1.0 - vUv.y) * hw);   // origin top-left, units of screen width
  float y = 1.0 - vUv.y;
  vec3 plum = vec3(0.110,0.063,0.141), plumDeep = vec3(0.071,0.039,0.094), ink = vec3(0.043,0.043,0.059);
  vec3 col = y < 0.3333 ? mix(plum, plumDeep, y * 3.0) : mix(plumDeep, ink, clamp((y - 0.3333) * 3.0, 0.0, 1.0));
  float t = uTime;
  col = mix(col, vec3(0.878,0.337,0.710), 0.42 * bloom(p, vec2(0.20 + 0.015 * sin(t * 0.21), 0.025 + 0.015 * cos(t * 0.17)), 0.475, 0.30));
  col = mix(col, vec3(0.557,0.302,0.878), 0.40 * bloom(p, vec2(0.85 + 0.015 * cos(t * 0.19), 0.125 + 0.015 * sin(t * 0.23)), 0.425, 0.32));
  col = mix(col, uTint, uTintI * bloom(p, vec2(uTintP.x, uTintP.y * hw), 0.45, 0.4));
  col += (hash(vUv * uRes + fract(uTime) * 91.0) - 0.5) * 0.014;
  gl_FragColor = vec4(col, 1.0);
}`

function Glow({ screen }: { screen: number }) {
  const { size } = useThree()
  const mat = useMemo(() => new THREE.ShaderMaterial({
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: glowFrag,
    depthWrite: false, depthTest: false,
    uniforms: { uTime: { value: 0 }, uRes: { value: new THREE.Vector2(1, 1) }, uTint: { value: new THREE.Color(...bus.cover) }, uTintI: { value: 0 }, uTintP: { value: new THREE.Vector2(0.5, 0.5) } },
  }), [])
  useFrame((_, dt) => {
    const u = mat.uniforms; u.uTime.value += dt; u.uRes.value.set(size.width, size.height)
    const k = 1 - Math.exp(-dt * 2.5)
    // One quiet extra tint per screen: the current cover on Swipe, a soft lime on a genre pick.
    const tint = screen === 1 ? new THREE.Color(...bus.cover) : LIME
    const ti = screen === 1 ? 0.14 : screen === 3 ? bus.pulse * 0.08 : screen === 5 ? 0.06 + bus.pulse * 0.06 : 0
    ;(u.uTint.value as THREE.Color).lerp(tint, k)
    u.uTintI.value += (ti - u.uTintI.value) * k
    ;(u.uTintP.value as THREE.Vector2).set(0.5, screen === 1 ? 0.45 : 0.5)
    bus.pulse *= Math.exp(-dt * 2.5)
  })
  return <mesh renderOrder={-10} frustumCulled={false} material={mat}><planeGeometry args={[2, 2]} /></mesh>
}

/* helpers */
function useTex<T>(p: () => Promise<T>, deps: unknown[]) {
  const [v, setV] = useState<T | null>(null)
  useEffect(() => { let on = true; p().then((x) => on && setV(x)); return () => { on = false } }, deps) // eslint-disable-line
  return v
}

/** Fade a group's materials in on mount (and expose opacity for exit). */
function useFadeIn(ref: React.RefObject<THREE.Object3D>, speed = 2.5) {
  const t = useRef(0)
  useFrame((_, dt) => {
    if (!ref.current || t.current >= 1) return
    t.current = Math.min(1, t.current + dt * speed)
    const e = 1 - Math.pow(1 - t.current, 3)
    ref.current.traverse((o) => {
      const m = (o as THREE.Mesh).material as THREE.Material & { userData: { base?: number } }
      if (!m) return
      if (m.userData.base === undefined) m.userData.base = m.opacity
      m.transparent = true; m.opacity = m.userData.base * e
    })
  })
}

function Billboard({ children, ...p }: JSX.IntrinsicElements['group']) {
  const ref = useRef<THREE.Group>(null)
  const q = useMemo(() => new THREE.Quaternion(), [])
  useFrame(({ camera }) => {
    const g = ref.current; if (!g || !g.parent) return
    g.parent.getWorldQuaternion(q); q.invert().multiply(camera.quaternion); g.quaternion.copy(q)
  })
  return <group ref={ref} {...p}>{children}</group>
}

/* ------------------------------------------------------------------ */
/* Screen 1: app icon with two slow, faint orbits of covers.           */
/* ------------------------------------------------------------------ */
function Cover({ src, size, dim = 1, opacity = 1 }: { src: string; size: number; dim?: number; opacity?: number }) {
  const tex = useTex(() => roundedTexture(src, 256, 0.1), [src])
  if (!tex) return null
  return <mesh><planeGeometry args={[size, size]} /><meshBasicMaterial map={tex} color={new THREE.Color(dim, dim, dim)} transparent opacity={opacity} toneMapped={false} /></mesh>
}

function Ring({ r, tilt, speed, items, phase = 0 }: { r: number; tilt: [number, number, number]; speed: number; items: string[]; phase?: number }) {
  const spin = useRef<THREE.Group>(null)
  const line = useMemo(() => {
    const pts = Array.from({ length: 160 }, (_, i) => { const a = (i / 160) * Math.PI * 2; return new THREE.Vector3(Math.cos(a) * r, Math.sin(a) * r, 0) })
    const g = new THREE.BufferGeometry().setFromPoints(pts)
    return new THREE.LineLoop(g, new THREE.LineBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.07 }))
  }, [r])
  useFrame((_, dt) => { if (spin.current) spin.current.rotation.z += dt * speed })
  return (
    <group rotation={tilt}>
      <primitive object={line} />
      <group ref={spin} rotation={[0, 0, phase]}>
        {items.map((src, i) => {
          const a = (i / items.length) * Math.PI * 2
          return <group key={i} position={[Math.cos(a) * r, Math.sin(a) * r, 0]}><Billboard><Cover src={src} size={0.24} dim={0.8} /></Billboard></group>
        })}
      </group>
    </group>
  )
}

function Hero() {
  const root = useRef<THREE.Group>(null)
  const iconG = useRef<THREE.Group>(null)
  const icon = useTex(() => roundedTexture(APPICON, 512, 0.225), [])
  useFadeIn(root, 1.2)
  const c = (i: number) => TRACKS[i].cover
  useFrame(({ clock }, dt) => {
    const g = root.current; if (!g) return
    const px = bus.pointer.x + bus.tilt.x, py = bus.pointer.y + bus.tilt.y
    const k = 1 - Math.exp(-dt * 2)
    g.rotation.y += (px * 0.1 - g.rotation.y) * k
    g.rotation.x += (-py * 0.07 - g.rotation.x) * k
    if (iconG.current) iconG.current.position.y = Math.sin(clock.elapsedTime * 0.9) * 0.025
  })
  return (
    <group ref={root} position={[0, 0.95, 0]} scale={0.88}>
      <Ring r={0.85} tilt={[1.32, 0.12, 0]} speed={0.07} items={[c(0), c(5), c(9)]} phase={0.6} />
      <Ring r={1.3} tilt={[1.26, -0.2, 0.14]} speed={-0.045} items={[c(1), c(3), c(6), c(10)]} phase={1.4} />
      <Billboard>
        <mesh renderOrder={1}><planeGeometry args={[2.4, 2.4]} /><meshBasicMaterial map={glowTexture()} color={MAGENTA} transparent opacity={0.22} blending={THREE.AdditiveBlending} depthWrite={false} /></mesh>
        <group ref={iconG}>
          {icon && <mesh renderOrder={2}><planeGeometry args={[0.64, 0.64]} /><meshBasicMaterial map={icon} transparent toneMapped={false} /></mesh>}
        </group>
      </Billboard>
    </group>
  )
}

/* ------------------------------------------------------------------ */
/* Dust: slow drifting points (screens 2 and 4).                       */
/* ------------------------------------------------------------------ */
function Dust({ n = 110, color = '#ffffff' }: { n?: number; color?: string }) {
  const ref = useRef<THREE.Points>(null)
  const geo = useMemo(() => {
    const a = new Float32Array(n * 3)
    for (let i = 0; i < n; i++) { a[i * 3] = (Math.random() - 0.5) * 4; a[i * 3 + 1] = (Math.random() - 0.5) * 6; a[i * 3 + 2] = (Math.random() - 0.5) * 3 }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(a, 3)); return g
  }, [n])
  useFadeIn(ref)
  useFrame((_, dt) => {
    const p = geo.attributes.position as THREE.BufferAttribute
    for (let i = 0; i < n; i++) { let y = p.getY(i) + dt * 0.05; if (y > 3) y = -3; p.setY(i, y) }
    p.needsUpdate = true
    if (ref.current) { ref.current.rotation.y = bus.pointer.x * 0.15; ref.current.rotation.x = -bus.pointer.y * 0.1 }
  })
  return <points ref={ref} geometry={geo}><pointsMaterial map={dotTexture()} color={color} size={0.03} transparent opacity={0.22} depthWrite={false} blending={THREE.AdditiveBlending} /></points>
}

/* ------------------------------------------------------------------ */
/* Screen 3: the Dashboard's concert crowd, as soft 3D points.         */
/* Crowd size follows PopularitySliderSettings: 5 at Deep, 80 at Hot.  */
/* ------------------------------------------------------------------ */
function Crowd() {
  const N = 80
  const ref = useRef<THREE.Points>(null)
  const seed = useMemo(() => Array.from({ length: N }, (_, i) => {
    // fill from the centre out so a small crowd stands near the stage
    const r = Math.sqrt((i + 0.5) / N), a = i * 2.39996
    return { x: Math.cos(a) * r * 1.5, z: Math.sin(a) * r * 1.1, ph: Math.random() * 6.28, sp: 1.6 + Math.random() * 1.4 }
  }), [])
  const geo = useMemo(() => {
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 3), 3))
    const col = new Float32Array(N * 3)
    for (let i = 0; i < N; i++) { const c = i % 9 === 4 ? LIME : i % 4 === 1 ? new THREE.Color('#C9A0F0') : new THREE.Color('#ffffff'); col.set([c.r, c.g, c.b], i * 3) }
    g.setAttribute('color', new THREE.BufferAttribute(col, 3)); return g
  }, [])
  const shown = useRef(5 + 75 * bus.pop)
  useFadeIn(ref, 1.5)
  useFrame(({ clock }, dt) => {
    shown.current += (5 + 75 * bus.pop - shown.current) * (1 - Math.exp(-dt * 4))
    const t = clock.elapsedTime, p = geo.attributes.position as THREE.BufferAttribute
    for (let i = 0; i < N; i++) {
      const s = seed[i], vis = Math.min(1, Math.max(0, shown.current - i))
      const bob = Math.max(0, Math.sin(t * s.sp + s.ph)) * 0.05 * (0.4 + bus.pop)
      p.setXYZ(i, s.x, vis > 0 ? bob - (1 - vis) * 0.3 : -50, s.z)
    }
    p.needsUpdate = true
    if (ref.current) { ref.current.rotation.set(0.62, bus.pointer.x * 0.1, 0); ref.current.position.set(0, 0.35, 0) }
  })
  return <points ref={ref} geometry={geo}><pointsMaterial map={dotTexture()} vertexColors size={0.12} transparent opacity={0.6} depthWrite={false} /></points>
}

/* ------------------------------------------------------------------ */
/* Screen 5: slow 3D wall of real covers behind the glass.             */
/* ------------------------------------------------------------------ */
function CoverWall() {
  const ref = useRef<THREE.Group>(null)
  const scroll = useRef<THREE.Group>(null)
  const cols = 4, rows = 8, s = 0.78, gap = 0.08
  useFadeIn(ref, 1.5)
  useFrame((_, dt) => {
    if (scroll.current) { scroll.current.position.y += dt * 0.07; if (scroll.current.position.y > (s + gap) * 4) scroll.current.position.y -= (s + gap) * 4 }
    if (ref.current) { ref.current.rotation.y = -0.3 + bus.pointer.x * 0.06; ref.current.rotation.x = -0.36 - bus.pointer.y * 0.04 }
  })
  return (
    <group ref={ref} position={[0, 1.5, -1.6]} rotation={[-0.42, -0.38, -0.12]}>
      <group ref={scroll}>
        {Array.from({ length: cols * rows }, (_, i) => {
          const cx = (i % cols) - (cols - 1) / 2, cy = Math.floor(i / cols) - rows / 2
          return <group key={i} position={[cx * (s + gap), -cy * (s + gap) - 2, 0]}><Cover src={TRACKS[(i * 5 + Math.floor(i / cols)) % TRACKS.length].cover} size={s} dim={0.22} /></group>
        })}
      </group>
    </group>
  )
}

/* ------------------------------------------------------------------ */
/* Screen 6: lime + white confetti burst from behind the card stack.   */
/* ------------------------------------------------------------------ */
function Burst() {
  const N = 60
  const ref = useRef<THREE.Points>(null)
  const mat = useRef<THREE.PointsMaterial>(null)
  const state = useMemo(() => ({ v: new Float32Array(N * 3), seen: -1, age: 0 }), [])
  const geo = useMemo(() => {
    const g = new THREE.BufferGeometry()
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 3), 3))
    const col = new Float32Array(N * 3)
    for (let i = 0; i < N; i++) { const c = i % 3 === 0 ? new THREE.Color('#ffffff') : LIME; col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b }
    g.setAttribute('color', new THREE.BufferAttribute(col, 3)); return g
  }, [])
  useFrame((_, dt) => {
    const p = geo.attributes.position as THREE.BufferAttribute
    if (state.seen !== bus.burst) {
      state.seen = bus.burst; state.age = 0
      for (let i = 0; i < N; i++) {
        p.setXYZ(i, (Math.random() - 0.5) * 1.6, 0.1, -0.5)
        const th = Math.random() * Math.PI * 2, ph = Math.acos(2 * Math.random() - 1), sp = 0.25 + Math.random() * 0.5
        state.v[i * 3] = Math.sin(ph) * Math.cos(th) * sp; state.v[i * 3 + 1] = Math.sin(ph) * Math.sin(th) * sp + 0.6; state.v[i * 3 + 2] = Math.cos(ph) * sp * 0.5
      }
    }
    state.age += dt
    if (mat.current) mat.current.opacity = 0.5 * Math.min(1, state.age * 2) * Math.max(0, 1 - Math.max(0, state.age - 1.5) / 2.5)
    const damp = Math.exp(-dt * 0.6)
    for (let i = 0; i < N; i++) {
      state.v[i * 3] *= damp; state.v[i * 3 + 1] = state.v[i * 3 + 1] * damp + dt * 0.04; state.v[i * 3 + 2] *= damp
      p.setXYZ(i, p.getX(i) + state.v[i * 3] * dt, p.getY(i) + state.v[i * 3 + 1] * dt, p.getZ(i) + state.v[i * 3 + 2] * dt)
    }
    p.needsUpdate = true
  })
  return <points ref={ref} geometry={geo}><pointsMaterial ref={mat} map={dotTexture()} vertexColors size={0.04} transparent opacity={0} depthWrite={false} blending={THREE.AdditiveBlending} /></points>
}

function Content({ screen }: { screen: number }) {
  return (
    <>
      <Glow screen={screen} />
      {screen === 0 && <Hero />}
      {screen === 1 && <Dust n={70} />}
      {screen === 2 && <Crowd />}
      {screen === 3 && <Dust n={60} />}
      {screen === 4 && <CoverWall />}
      {screen === 5 && <Burst />}
    </>
  )
}

export default function Scene({ screen }: { screen: number }) {
  return (
    <Canvas
      className="gl"
      dpr={[1, 2]}
      gl={{ antialias: true, powerPreference: 'high-performance', alpha: false }}
      camera={{ position: [0, 0, 5], fov: 45, near: 0.1, far: 60 }}
      onCreated={({ gl, scene }) => { gl.setClearColor(INK); scene.fog = new THREE.Fog(INK, 6, 14) }}
    >
      <Content screen={screen} />
    </Canvas>
  )
}
