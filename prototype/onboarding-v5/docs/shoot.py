import asyncio, json, sys
from playwright.async_api import async_playwright
BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:4175/'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/workspace/hidden-jams/design-research/onboarding-v5/shots/'
WAITS = {1: 4300, 2: 2600, 3: 5200, 4: 1500, 5: 2200, 6: 5200, 7: 3600, 8: 3600, 9: 3600, 10: 3600, 11: 2200}
JS_BOXES = """() => {
  const r = (e) => { const b = e.getBoundingClientRect(); return {l:b.left,t:b.top,r:b.right,b:b.bottom} }
  const q = (s) => [...document.querySelectorAll(s)].map(r)
  const cta = document.querySelector('[data-testid=next]') || document.querySelector('[data-testid=btn-spotify]')
  const dots = document.querySelector('[data-testid=page-dots]')
  const texts = [...document.querySelectorAll('.display, .sub, .stages, .helper, .mono.src, .eyebrow')].map(e => ({k: e.className, ...r(e)}))
  const covers = [...document.querySelectorAll('[data-cover], .card, .deck, .descent, .gbars, .sig, .deep, .score, .flowzone, .pillscroll, .gcloud, .plist, .mqzone')].map(e => ({k: e.className.toString().slice(0,20), ...r(e)}))
  return { vw: innerWidth, vh: innerHeight, cta: cta && r(cta), ctaLabel: cta && cta.innerText.trim(), dots: dots && r(dots), texts, covers,
    overflowX: [...document.querySelectorAll('.display,.sub,.stage,.rr-t b,.gpill')].filter(e => e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflow !== 'hidden').map(e => e.className + ':' + e.textContent.slice(0,24)),
    pageOverflow: [...document.querySelectorAll('.screen *')].filter(e => { const b = e.getBoundingClientRect(); return b.width > 0 && (b.right > innerWidth + 2 || b.left < -2) && !e.closest('.mq,.mqzone,.flowzone,.cloud,.sheet') }).slice(0,5).map(e => e.className.toString() + e.tagName)
  }
}"""
def inter(a, b): return not (a['r'] <= b['l'] or b['r'] <= a['l'] or a['b'] <= b['t'] or b['b'] <= a['t'])
async def main():
    report = {}
    async with async_playwright() as p:
        br = await p.chromium.launch(args=['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'])
        ctx = await br.new_context(viewport={'width': 393, 'height': 852}, device_scale_factor=2, is_mobile=True, has_touch=True)
        errs = []
        for s in range(1, 12):
            page = await ctx.new_page()
            page.on('console', lambda m: errs.append(f'{m.type}: {m.text}') if m.type in ('error',) else None)
            page.on('pageerror', lambda e: errs.append(f'pageerror: {e}'))
            await page.goto(f'{BASE}?s={s}'); await page.wait_for_timeout(WAITS[s])
            if s == 4:
                await page.screenshot(path=f'{OUT}04a-none.png')
                for g in ['soul', 'jazz', 'funk', 'ambient']:
                    await page.click(f'[data-testid="genre-{g}"]'); await page.wait_for_timeout(120)
                await page.wait_for_timeout(500)
            if s == 2:
                await page.screenshot(path=f'{OUT}02a-keep-stamp.png'); await page.wait_for_timeout(3600)
            if s == 6:
                await page.screenshot(path=f'{OUT}06a-loading-early.png'); await page.wait_for_timeout(1600)
                await page.screenshot(path=f'{OUT}06b-loading-genres.png'); await page.wait_for_timeout(1500)
            if s == 1:
                await page.screenshot(path=f'{OUT}01a-title-grab.png')
            box = await page.evaluate(JS_BOXES)
            await page.screenshot(path=f'{OUT}{s:02d}.png')
            tx = [t for t in box['texts'] if t['b'] - t['t'] > 4]
            hits = []
            for c in box['covers']:
                for t in tx:
                    if c['k'].startswith(('cv', 'card', 'mqzone', 'flowzone')) or 'cv' in c['k']:
                        if inter(c, t): hits.append((c['k'], t['k']))
            report[s] = {'cta': box['cta'], 'label': box['ctaLabel'], 'dots_bottom': box['dots'] and round(box['dots']['b']), 'collisions': hits, 'overflowX': box['overflowX'], 'offscreen': box['pageOverflow']}
            await page.close()
        # flow test: s=1 -> Next x3 -> pills -> Next -> connect -> auto analysis -> reveals -> end; persistence
        page = await ctx.new_page(); await page.goto(f'{BASE}?s=1'); await page.wait_for_timeout(800)
        steps = []
        for k in range(3):
            await page.click('[data-testid=next]'); await page.wait_for_timeout(900); steps.append(await page.evaluate("document.querySelector('.phone').dataset.step"))
        for g in ['soul', 'jazz', 'hip hop']: await page.click(f'[data-testid="genre-{g}"]'); await page.wait_for_timeout(100)
        await page.click('[data-testid=next]'); await page.wait_for_timeout(900); steps.append(await page.evaluate("document.querySelector('.phone').dataset.step"))
        stored = await page.evaluate("localStorage.getItem('selectedGenres')")
        await page.click('[data-testid=btn-spotify]'); await page.wait_for_timeout(1500); steps.append(await page.evaluate("document.querySelector('.phone').dataset.step"))
        await page.wait_for_timeout(9800); steps.append(await page.evaluate("document.querySelector('.phone').dataset.step"))
        for k in range(3):
            await page.click('[data-testid=next]'); await page.wait_for_timeout(1000); steps.append(await page.evaluate("document.querySelector('.phone').dataset.step"))
        await page.wait_for_timeout(2500); await page.screenshot(path=f'{OUT}10b-deepest-picks.png')
        await page.click('[data-testid=next]'); await page.wait_for_timeout(800); await page.screenshot(path=f'{OUT}12-end.png')
        # fresh load: picks pre-selected from storage
        await page.goto(f'{BASE}?s=4'); await page.wait_for_timeout(1500)
        pre = await page.evaluate("[...document.querySelectorAll('.gpill.on')].map(e => e.textContent)")
        # swipe nav
        await page.goto(f'{BASE}?s=1'); await page.wait_for_timeout(600)
        await page.mouse.move(300, 400); await page.mouse.down(); await page.mouse.move(120, 410, steps=10); await page.mouse.up(); await page.wait_for_timeout(900)
        sw = await page.evaluate("document.querySelector('.phone').dataset.step")
        # empty path
        await page.goto(f'{BASE}?s=6&empty=1&speed=2'); await page.wait_for_timeout(3600)
        await page.screenshot(path=f'{OUT}06c-empty-loading.png'); await page.wait_for_timeout(1500)
        emp = await page.evaluate("document.querySelector('.phone').dataset.step")
        # apple variant
        await page.goto(f'{BASE}?s=6&svc=apple'); await page.wait_for_timeout(3000); await page.screenshot(path=f'{OUT}06d-apple-loading.png')
        # desktop framed overview
        d = await br.new_context(viewport={'width': 1280, 'height': 900}, device_scale_factor=1)
        dp = await d.new_page(); await dp.goto(f'{BASE}?s=1'); await dp.wait_for_timeout(4500); await dp.screenshot(path=f'{OUT}00-desktop-framed.png')
        print(json.dumps({'flow_steps(expect 2,3,4,5,6,7,8,9,10)': steps, 'stored': stored, 'pre_selected_after_reload': pre, 'swipe_left_from_1_goes_to': sw, 'empty_path_ends_on': emp, 'console_errors': errs or 'clean'}, indent=1))
        await br.close()
    ctas = {s: (r['cta'] and (round(r['cta']['l']), round(r['cta']['r']), round(r['cta']['b']))) for s, r in report.items()}
    print(json.dumps(report, indent=1, default=str)); print('CTA boxes', ctas)
asyncio.run(main())
