import * as THREE from 'three'

const cache = new Map<string, Promise<THREE.Texture>>()
export const coverColors = new Map<string, [number, number, number]>()

function loadImg(src: string) {
  return new Promise<HTMLImageElement>((res, rej) => {
    const im = new Image(); im.crossOrigin = 'anonymous'
    im.onload = () => res(im); im.onerror = rej; im.src = src
  })
}

function rgbToHsl(r: number, g: number, b: number) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b); let h = 0, s = 0; const l = (mx + mn) / 2
  if (mx !== mn) {
    const d = mx - mn; s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6
  }
  return [h, s, l]
}

/** Dominant glow colour for a cover. Blues are pushed to violet (palette has no blue). */
function glowColor(im: HTMLImageElement): [number, number, number] {
  const c = document.createElement('canvas'); c.width = c.height = 24
  const x = c.getContext('2d')!; x.drawImage(im, 0, 0, 24, 24)
  const d = x.getImageData(0, 0, 24, 24).data
  let r = 0, g = 0, b = 0, w = 0
  for (let i = 0; i < d.length; i += 4) {
    const [, s, l] = rgbToHsl(d[i] / 255, d[i + 1] / 255, d[i + 2] / 255)
    const k = s * (1 - Math.abs(l - 0.5) * 2) + 0.02
    r += d[i] * k; g += d[i + 1] * k; b += d[i + 2] * k; w += k
  }
  let [h, s] = rgbToHsl(r / w / 255, g / w / 255, b / w / 255)
  if (h > 0.45 && h < 0.72) h = 0.77 // blue/cyan -> violet
  s = Math.max(0.55, s)
  const col = new THREE.Color().setHSL(h, s, 0.55)
  return [col.r, col.g, col.b]
}

export function roundedTexture(src: string, size = 256, radius = 0.12): Promise<THREE.Texture> {
  const key = `${src}|${size}|${radius}`
  if (!cache.has(key)) {
    cache.set(key, loadImg(src).then((im) => {
      if (!coverColors.has(src)) coverColors.set(src, glowColor(im))
      const c = document.createElement('canvas'); c.width = c.height = size
      const x = c.getContext('2d')!; const r = size * radius
      x.beginPath(); x.roundRect(0, 0, size, size, r); x.clip()
      x.drawImage(im, 0, 0, size, size)
      const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4
      return t
    }))
  }
  return cache.get(key)!
}

/** Sticker tag rendered to a texture: pill with heavy type. */
export function stickerTexture(text: string, bg: string, fg: string): Promise<{ tex: THREE.Texture; aspect: number }> {
  const key = `sticker|${text}|${bg}`
  return (cache.get(key) as unknown as Promise<{ tex: THREE.Texture; aspect: number }>) ?? (() => {
    const p = document.fonts.load('900 64px "Cabinet Grotesk"').then(() => {
      const h = 96, pad = 34
      const m = document.createElement('canvas').getContext('2d')!
      m.font = '900 54px "Cabinet Grotesk"'
      const w = Math.ceil(m.measureText(text).width) + pad * 2
      const c = document.createElement('canvas'); c.width = w; c.height = h
      const x = c.getContext('2d')!
      x.fillStyle = bg; x.beginPath(); x.roundRect(2, 2, w - 4, h - 4, (h - 4) / 2); x.fill()
      x.fillStyle = fg; x.font = '900 54px "Cabinet Grotesk"'; x.textBaseline = 'middle'
      x.fillText(text, pad, h / 2 + 3)
      const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace
      return { tex, aspect: w / h }
    })
    cache.set(key, p as unknown as Promise<THREE.Texture>)
    return p
  })()
}

let dot: THREE.Texture | null = null
export function dotTexture() {
  if (dot) return dot
  const c = document.createElement('canvas'); c.width = c.height = 64
  const x = c.getContext('2d')!
  const g = x.createRadialGradient(32, 32, 0, 32, 32, 32)
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.35, 'rgba(255,255,255,0.9)'); g.addColorStop(1, 'rgba(255,255,255,0)')
  x.fillStyle = g; x.fillRect(0, 0, 64, 64)
  dot = new THREE.CanvasTexture(c); return dot
}

let glow: THREE.Texture | null = null
export function glowTexture() {
  if (glow) return glow
  const c = document.createElement('canvas'); c.width = c.height = 256
  const x = c.getContext('2d')!
  const g = x.createRadialGradient(128, 128, 0, 128, 128, 128)
  g.addColorStop(0, 'rgba(255,255,255,0.95)'); g.addColorStop(0.25, 'rgba(255,255,255,0.45)'); g.addColorStop(0.6, 'rgba(255,255,255,0.1)'); g.addColorStop(1, 'rgba(255,255,255,0)')
  x.fillStyle = g; x.fillRect(0, 0, 256, 256)
  glow = new THREE.CanvasTexture(c); return glow
}
