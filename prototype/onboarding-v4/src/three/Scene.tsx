import { Canvas, useFrame, useThree } from '@react-three/fiber'
import { useEffect, useMemo, useRef, useState } from 'react'
import * as THREE from 'three'
import { bus } from '../bus'
import { APPICON, TRACKS } from '../data'
import { dotTexture, glowTexture, roundedTexture, stickerTexture } from './textures'

// Theme.swift tokens
const INK = new THREE.Color('#0B0B0F')
const MAGENTA = new THREE.Color('#E056B5')
const VIOLET = new THREE.Color('#8E4DE0')
const LIME = new THREE.Color('#C8E86B')
const PLUM = new THREE.Color('#3B1A4F')

/* ------------------------------------------------------------------ */
/* Ambient glow: full-screen shader, 3 soft blobs + grain.             */
/* ------------------------------------------------------------------ */
type Blob = { c: THREE.Color; p: [number, number]; s: number; i: number }
const glowTargets = (screen: number): Blob[] => {
  const cov = new THREE.Color(...bus.cover)
  switch (screen) {
    case 0: return [
      { c: MAGENTA, p: [0.5, 0.74], s: 0.26, i: 0.5 },
      { c: VIOLET, p: [0.1, 0.95], s: 0.34, i: 0.5 },
      { c: VIOLET, p: [0.98, 0.5], s: 0.22, i: 0.22 }]
    case 1: return [
      { c: cov, p: [0.5, 0.55], s: 0.34, i: 0.55 },
      { c: VIOLET, p: [0.9, 0.98], s: 0.32, i: 0.35 },
      { c: MAGENTA, p: [0.05, 0.25], s: 0.3, i: 0.25 }]
    case 2: return [
      { c: VIOLET, p: [0.5, 0.62], s: 0.36 + bus.depth * 0.12, i: 0.4 + bus.depth * 0.25 },
      { c: MAGENTA, p: [0.85, 0.9], s: 0.35, i: 0.35 * (1 - bus.depth) + 0.1 },
      { c: LIME, p: [0.5, 0.22], s: 0.26, i: Math.max(0, bus.depth - 0.6) * 0.9 }]
    case 3: return [
      { c: LIME, p: [0.18, 0.52], s: 0.3, i: 0.3 + bus.pulse * 0.25 },
      { c: VIOLET, p: [0.86, 0.4], s: 0.36, i: 0.5 },
      { c: MAGENTA, p: [0.55, 0.95], s: 0.32, i: 0.3 }]
    case 4: return [
      { c: MAGENTA, p: [0.6, 0.95], s: 0.3, i: 0.3 },
      { c: VIOLET, p: [0.1, 0.65], s: 0.4, i: 0.5 },
      { c: LIME, p: [0.5, 0.12], s: 0.28, i: 0.22 }]
    default: return [
      { c: LIME, p: [0.5, 0.64], s: 0.27, i: 0.36 + bus.pulse * 0.3 },
      { c: MAGENTA, p: [0.2, 0.86], s: 0.38, i: 0.45 },
      { c: VIOLET, p: [0.88, 0.5], s: 0.4, i: 0.5 }]
  }
}

const glowFrag = /* glsl */ `
precision highp float;
uniform float uTime; uniform vec2 uRes;
uniform vec3 uC[3]; uniform vec2 uP[3]; uniform float uS[3]; uniform float uI[3];
varying vec2 vUv;
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453); }
void main(){
  float asp = uRes.x / uRes.y;
  vec2 p = vec2(vUv.x * asp, vUv.y);
  vec3 col = mix(vec3(0.043,0.043,0.059), vec3(0.110,0.063,0.141), smoothstep(0.0, 1.0, vUv.y) * 0.85);
  for (int k = 0; k < 3; k++) {
    float fk = float(k);
    vec2 c = vec2(uP[k].x * asp, uP[k].y) + 0.035 * vec2(sin(uTime * 0.35 + fk * 2.1), cos(uTime * 0.29 + fk * 1.3));
    vec2 d = p - c; d.x *= 0.85;
    float g = exp(-dot(d, d) / (uS[k] * uS[k] * 0.5));
    col += uC[k] * g * uI[k];
  }
  col = col / (1.0 + col * 0.35);               // soft tonemap so glows never clip
  col += (hash(vUv * uRes + fract(uTime) * 91.0) - 0.5) * 0.028; // film grain
  gl_FragColor = vec4(col, 1.0);
}`

function Glow({ screen }: { screen: number }) {
  const { size } = useThree()
  const mat = useMemo(() => new THREE.ShaderMaterial({
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: glowFrag,
    depthWrite: false, depthTest: false,
    uniforms: {
      uTime: { value: 0 }, uRes: { value: new THREE.Vector2(1, 1) },
      uC: { value: [MAGENTA.clone(), VIOLET.clone(), VIOLET.clone()] },
      uP: { value: [new THREE.Vector2(0.5, 0.7), new THREE.Vector2(0.1, 0.9), new THREE.Vector2(0.9, 0.5)] },
      uS: { value: [0.3, 0.4, 0.3] }, uI: { value: [0, 0, 0] },
    },
  }), [])
  useFrame((_, dt) => {
    const u = mat.uniforms; u.uTime.value += dt; u.uRes.value.set(size.width, size.height)
    const t = glowTargets(screen); const k = 1 - Math.exp(-dt * 3.2)
    t.forEach((b, i) => {
      (u.uC.value[i] as THREE.Color).lerp(b.c, k)
      ;(u.uP.value[i] as THREE.Vector2).lerp(new THREE.Vector2(...b.p), k)
      u.uS.value[i] += (b.s - u.uS.value[i]) * k
      u.uI.value[i] += (b.i - u.uI.value[i]) * k
    })
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
/* Screen 1: hero icon + orbit rings carrying covers and stickers.     */
/* ------------------------------------------------------------------ */
type OrbitItem = { cover?: string; sticker?: [string, string, string] }
function Cover({ src, size, dim = 1 }: { src: string; size: number; dim?: number }) {
  const tex = useTex(() => roundedTexture(src, 256, 0.1), [src])
  if (!tex) return null
  return <mesh><planeGeometry args={[size, size]} /><meshBasicMaterial map={tex} color={new THREE.Color(dim, dim, dim)} transparent toneMapped={false} /></mesh>
}
function Sticker({ text, bg, fg, h }: { text: string; bg: string; fg: string; h: number }) {
  const s = useTex(() => stickerTexture(text, bg, fg), [text])
  if (!s) return null
  return <mesh><planeGeometry args={[h * s.aspect, h]} /><meshBasicMaterial map={s.tex} transparent toneMapped={false} /></mesh>
}

function Ring({ r, tilt, speed, items, phase = 0 }: { r: number; tilt: [number, number, number]; speed: number; items: OrbitItem[]; phase?: number }) {
  const spin = useRef<THREE.Group>(null)
  const line = useMemo(() => {
    const pts = Array.from({ length: 160 }, (_, i) => { const a = (i / 160) * Math.PI * 2; return new THREE.Vector3(Math.cos(a) * r, Math.sin(a) * r, 0) })
    const g = new THREE.BufferGeometry().setFromPoints(pts)
    return new THREE.LineLoop(g, new THREE.LineBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.16 }))
  }, [r])
  useFrame((_, dt) => { if (spin.current) spin.current.rotation.z += dt * speed * (1 + bus.slide * 4) })
  return (
    <group rotation={tilt}>
      <primitive object={line} />
      <group ref={spin} rotation={[0, 0, phase]}>
        {items.map((it, i) => {
          const a = (i / items.length) * Math.PI * 2
          return (
            <group key={i} position={[Math.cos(a) * r, Math.sin(a) * r, 0]}>
              <Billboard>
                {it.cover && <Cover src={it.cover} size={0.3} />}
                {it.sticker && <Sticker text={it.sticker[0]} bg={it.sticker[1]} fg={it.sticker[2]} h={0.13} />}
              </Billboard>
            </group>
          )
        })}
      </group>
    </group>
  )
}

function Hero() {
  const root = useRef<THREE.Group>(null)
  const iconG = useRef<THREE.Group>(null)
  const glowM = useRef<THREE.MeshBasicMaterial>(null)
  const icon = useTex(() => roundedTexture(APPICON, 512, 0.225), [])
  useFadeIn(root)
  const c = (i: number) => TRACKS[i].cover
  useFrame(({ clock }, dt) => {
    const g = root.current; if (!g) return
    const px = bus.pointer.x + bus.tilt.x, py = bus.pointer.y + bus.tilt.y
    const k = 1 - Math.exp(-dt * 4)
    g.rotation.y += (px * 0.45 - g.rotation.y) * k
    g.rotation.x += (-py * 0.3 - g.rotation.x) * k
    const t = clock.elapsedTime
    if (iconG.current) {
      iconG.current.position.y = Math.sin(t * 1.3) * 0.05
      iconG.current.rotation.z = Math.sin(t * 0.8) * 0.04
      const s = 1 + bus.slide * 0.12; iconG.current.scale.setScalar(s)
    }
    if (glowM.current) glowM.current.opacity = 0.55 + Math.sin(t * 2) * 0.08 + bus.slide * 0.3
  })
  return (
    <group ref={root} position={[0, 0.9, 0]}>
      <Ring r={0.78} tilt={[1.3, 0.12, 0]} speed={0.22} items={[{ cover: c(0) }, { sticker: ['#soul', '#F7F3EE', '#0B0B0F'] }, { cover: c(5) }]} phase={0.6} />
      <Ring r={1.12} tilt={[1.38, -0.22, 0.16]} speed={-0.13} items={[{ cover: c(1) }, { cover: c(3) }, { sticker: ['2,418 plays', '#C8E86B', '#0B0B0F'] }, { cover: c(6) }, { cover: c(9) }]} phase={1.4} />
      <Ring r={1.5} tilt={[1.22, 0.3, -0.12]} speed={0.08} items={[{ cover: c(4) }, { sticker: ['#jazz', '#F7F3EE', '#0B0B0F'] }, { cover: c(7) }, { cover: c(10) }, { sticker: ['412 plays', '#F7F3EE', '#0B0B0F'] }, { cover: c(11) }]} phase={2.2} />
      <Billboard>
        <mesh renderOrder={1}><planeGeometry args={[3.2, 3.2]} /><meshBasicMaterial ref={glowM} map={glowTexture()} color={MAGENTA} transparent opacity={0.6} blending={THREE.AdditiveBlending} depthWrite={false} /></mesh>
        <group ref={iconG}>
          {icon && <mesh renderOrder={2}><planeGeometry args={[0.82, 0.82]} /><meshBasicMaterial map={icon} transparent toneMapped={false} /></mesh>}
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
    for (let i = 0; i < n; i++) { let y = p.getY(i) + dt * 0.08; if (y > 3) y = -3; p.setY(i, y) }
    p.needsUpdate = true
    if (ref.current) { ref.current.rotation.y = bus.pointer.x * 0.15; ref.current.rotation.x = -bus.pointer.y * 0.1 }
  })
  return <points ref={ref} geometry={geo}><pointsMaterial map={dotTexture()} color={color} size={0.035} transparent opacity={0.45} depthWrite={false} blending={THREE.AdditiveBlending} /></points>
}

/* ------------------------------------------------------------------ */
/* Screen 3: depth tunnel. Speed and colour follow the slider.         */
/* ------------------------------------------------------------------ */
function Tunnel() {
  const N = 700
  const ref = useRef<THREE.Points>(null)
  const mat = useRef<THREE.PointsMaterial>(null)
  const geo = useMemo(() => {
    const a = new Float32Array(N * 3)
    for (let i = 0; i < N; i++) {
      const ang = Math.random() * Math.PI * 2, rad = 0.6 + Math.random() * 2.2
      a[i * 3] = Math.cos(ang) * rad; a[i * 3 + 1] = Math.sin(ang) * rad; a[i * 3 + 2] = -Math.random() * 24
    }
    const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(a, 3)); return g
  }, [])
  const white = useMemo(() => new THREE.Color('#ffffff'), [])
  const tmp = useMemo(() => new THREE.Color(), [])
  const speed = useRef(1)
  useFadeIn(ref)
  useFrame((_, dt) => {
    speed.current += (0.6 + bus.depth * bus.depth * 9 - speed.current) * (1 - Math.exp(-dt * 3))
    const p = geo.attributes.position as THREE.BufferAttribute
    for (let i = 0; i < N; i++) { let z = p.getZ(i) + dt * speed.current; if (z > 5) z -= 24; p.setZ(i, z) }
    p.needsUpdate = true
    if (ref.current) { ref.current.rotation.z += dt * 0.05 * (1 + bus.depth * 2); ref.current.position.y = 0.6 }
    if (mat.current) { mat.current.color.copy(tmp.copy(white).lerp(LIME, Math.min(1, Math.max(0, (bus.depth - 0.45) * 1.8)))); mat.current.size = 0.03 + bus.depth * 0.025 }
  })
  return <points ref={ref} geometry={geo}><pointsMaterial ref={mat} map={dotTexture()} size={0.04} transparent opacity={0.7} depthWrite={false} blending={THREE.AdditiveBlending} /></points>
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
    if (scroll.current) { scroll.current.position.y += dt * 0.12; if (scroll.current.position.y > (s + gap) * 4) scroll.current.position.y -= (s + gap) * 4 }
    if (ref.current) { ref.current.rotation.y = -0.38 + bus.pointer.x * 0.12; ref.current.rotation.x = -0.42 - bus.pointer.y * 0.08 }
  })
  return (
    <group ref={ref} position={[0, 1.5, -1.6]} rotation={[-0.42, -0.38, -0.12]}>
      <group ref={scroll}>
        {Array.from({ length: cols * rows }, (_, i) => {
          const cx = (i % cols) - (cols - 1) / 2, cy = Math.floor(i / cols) - rows / 2
          return <group key={i} position={[cx * (s + gap), -cy * (s + gap) - 2, 0]}><Cover src={TRACKS[(i * 5 + Math.floor(i / cols)) % TRACKS.length].cover} size={s} dim={0.4} /></group>
        })}
      </group>
    </group>
  )
}

/* ------------------------------------------------------------------ */
/* Screen 6: lime + white confetti burst from behind the card stack.   */
/* ------------------------------------------------------------------ */
function Burst() {
  const N = 150
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
        p.setXYZ(i, 0, 0.75, 0)
        const th = Math.random() * Math.PI * 2, ph = Math.acos(2 * Math.random() - 1), sp = 1.2 + Math.random() * 3.2
        state.v[i * 3] = Math.sin(ph) * Math.cos(th) * sp; state.v[i * 3 + 1] = Math.sin(ph) * Math.sin(th) * sp + 0.6; state.v[i * 3 + 2] = Math.cos(ph) * sp * 0.5
      }
    }
    state.age += dt
    if (mat.current) mat.current.opacity = 0.95 * Math.max(0.18, 1 - Math.max(0, state.age - 0.9) / 1.6)
    const damp = Math.exp(-dt * 1.6)
    for (let i = 0; i < N; i++) {
      state.v[i * 3] *= damp; state.v[i * 3 + 1] = state.v[i * 3 + 1] * damp - dt * 0.25; state.v[i * 3 + 2] *= damp
      p.setXYZ(i, p.getX(i) + state.v[i * 3] * dt, p.getY(i) + state.v[i * 3 + 1] * dt, p.getZ(i) + state.v[i * 3 + 2] * dt)
    }
    p.needsUpdate = true
  })
  return <points ref={ref} geometry={geo}><pointsMaterial ref={mat} map={dotTexture()} vertexColors size={0.06} transparent opacity={0.9} depthWrite={false} blending={THREE.AdditiveBlending} /></points>
}

function Content({ screen }: { screen: number }) {
  return (
    <>
      <Glow screen={screen} />
      {screen === 0 && <Hero />}
      {screen === 1 && <Dust />}
      {screen === 2 && <Tunnel />}
      {screen === 3 && <Dust n={70} />}
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
      onCreated={({ gl, scene }) => { gl.setClearColor(INK); scene.fog = new THREE.Fog(INK, 6, 14); void PLUM }}
    >
      <Content screen={screen} />
    </Canvas>
  )
}
