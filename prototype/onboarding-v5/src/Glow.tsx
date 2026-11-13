import { Canvas, useFrame, useThree } from '@react-three/fiber'
import { useMemo } from 'react'
import * as THREE from 'three'
import { bus } from './bus'

// Theme.swift tokens. Same ambient shader family as v4 (plum -> ink + three soft blooms + grain).
const INK = new THREE.Color('#0B0B0F')
const MAGENTA = new THREE.Color('#E056B5')
const VIOLET = new THREE.Color('#8E4DE0')
const LIME = new THREE.Color('#C8E86B')
type Blob = { c: THREE.Color; p: [number, number]; s: number; i: number }

const targets = (screen: number): Blob[] => {
  switch (screen) {
    case 0: return [{ c: MAGENTA, p: [0.5, 0.78], s: 0.26, i: 0.5 }, { c: VIOLET, p: [0.1, 0.98], s: 0.34, i: 0.5 }, { c: VIOLET, p: [0.98, 0.55], s: 0.22, i: 0.22 }]
    case 1: return [{ c: MAGENTA, p: [0.5, 0.52], s: 0.34, i: 0.4 }, { c: VIOLET, p: [0.9, 0.98], s: 0.32, i: 0.35 }, { c: LIME, p: [0.1, 0.3], s: 0.22, i: 0.12 }]
    case 2: return [{ c: VIOLET, p: [0.5, 0.62], s: 0.4, i: 0.5 }, { c: MAGENTA, p: [0.85, 0.3], s: 0.3, i: 0.28 }, { c: LIME, p: [0.5, 0.92], s: 0.3, i: 0.34 }]
    case 3: return [{ c: LIME, p: [0.15, 0.55], s: 0.3, i: 0.28 + bus.pulse * 0.25 }, { c: VIOLET, p: [0.86, 0.4], s: 0.36, i: 0.5 }, { c: MAGENTA, p: [0.55, 0.95], s: 0.32, i: 0.3 }]
    case 4: return [{ c: MAGENTA, p: [0.6, 0.95], s: 0.3, i: 0.32 }, { c: VIOLET, p: [0.1, 0.55], s: 0.4, i: 0.5 }, { c: LIME, p: [0.5, 0.12], s: 0.26, i: 0.2 }]
    case 5: return [{ c: VIOLET, p: [0.5, 0.4], s: 0.42, i: 0.55 }, { c: MAGENTA, p: [0.1, 0.9], s: 0.34, i: 0.32 }, { c: LIME, p: [0.9, 0.7], s: 0.28, i: 0.25 }]
    case 6: return [{ c: LIME, p: [0.2, 0.45], s: 0.3, i: 0.22 }, { c: VIOLET, p: [0.85, 0.35], s: 0.4, i: 0.5 }, { c: MAGENTA, p: [0.5, 0.95], s: 0.34, i: 0.34 }]
    case 7: return [{ c: LIME, p: [0.5, 0.42], s: 0.34, i: 0.34 }, { c: MAGENTA, p: [0.1, 0.85], s: 0.36, i: 0.4 }, { c: VIOLET, p: [0.9, 0.7], s: 0.4, i: 0.5 }]
    case 8: return [{ c: MAGENTA, p: [0.3, 0.5], s: 0.36, i: 0.4 }, { c: VIOLET, p: [0.8, 0.8], s: 0.4, i: 0.5 }, { c: LIME, p: [0.7, 0.15], s: 0.26, i: 0.2 }]
    default: return [{ c: LIME, p: [0.5, 0.5], s: 0.3, i: 0.3 }, { c: MAGENTA, p: [0.15, 0.85], s: 0.38, i: 0.42 }, { c: VIOLET, p: [0.88, 0.45], s: 0.4, i: 0.5 }]
  }
}

const frag = /* glsl */ `
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
  col = col / (1.0 + col * 0.35);
  col += (hash(vUv * uRes + fract(uTime) * 91.0) - 0.5) * 0.028;
  gl_FragColor = vec4(col, 1.0);
}`

function Bloom() {
  const { size } = useThree()
  const mat = useMemo(() => new THREE.ShaderMaterial({
    vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }',
    fragmentShader: frag, depthWrite: false, depthTest: false,
    uniforms: {
      uTime: { value: 0 }, uRes: { value: new THREE.Vector2(1, 1) },
      uC: { value: [MAGENTA.clone(), VIOLET.clone(), VIOLET.clone()] },
      uP: { value: [new THREE.Vector2(0.5, 0.7), new THREE.Vector2(0.1, 0.9), new THREE.Vector2(0.9, 0.5)] },
      uS: { value: [0.3, 0.4, 0.3] }, uI: { value: [0, 0, 0] },
    },
  }), [])
  useFrame((_, dt) => {
    const u = mat.uniforms; u.uTime.value += dt; u.uRes.value.set(size.width, size.height)
    const t = targets(bus.screen); const k = 1 - Math.exp(-dt * 3.2)
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

export default function Glow() {
  return (
    <Canvas className="gl" dpr={[1, 2]} gl={{ antialias: true, powerPreference: 'high-performance', alpha: false }}
      camera={{ position: [0, 0, 5], fov: 45, near: 0.1, far: 60 }} onCreated={({ gl }) => gl.setClearColor(INK)}>
      <Bloom />
    </Canvas>
  )
}
