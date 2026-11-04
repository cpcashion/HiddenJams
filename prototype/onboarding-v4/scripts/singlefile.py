"""Bundle dist/ into one self-contained dist-single/index.html (JS, CSS, fonts, covers inlined).
Used for hosts that take a single file. Usage: python3 scripts/singlefile.py (after npm run build)."""
import base64, json, os, re
D = os.path.join(os.path.dirname(__file__), '..', 'dist')
def b64(p): return base64.b64encode(open(os.path.join(D, p), 'rb').read()).decode()
html = open(os.path.join(D, 'index.html')).read()
html = re.sub(r'<link rel="preload"[^>]*>\s*', '', html)
icon = 'data:image/png;base64,' + b64('art/appicon.png')
html = html.replace('./art/appicon.png', icon)
arts = {f: ('data:image/png;base64,' if f.endswith('.png') else 'data:image/jpeg;base64,') + b64('art/' + f)
        for f in os.listdir(os.path.join(D, 'art')) if f != 'rockhand.png'}
def css_inline(m):
    css = open(os.path.join(D, m.group(1).lstrip('./'))).read()
    css = re.sub(r'url\((?:\.\./|/)?fonts/([^)\'"]+)\)', lambda f: 'url(data:font/woff2;base64,' + b64('fonts/' + f.group(1)) + ')', css)
    return '<style>' + css + '</style>'
html = re.sub(r'<link rel="stylesheet"[^>]*href="([^"]+)"[^>]*>', css_inline, html)
def js_inline(m):
    js = open(os.path.join(D, m.group(1).lstrip('./'))).read().replace('</script', '<\\/script')
    return '<script>window.__ART=' + json.dumps(arts) + '</script><script type="module">' + js + '</script>'
html = re.sub(r'<script type="module" crossorigin src="([^"]+)"></script>', js_inline, html)
os.makedirs(os.path.join(D, '..', 'dist-single'), exist_ok=True)
open(os.path.join(D, '..', 'dist-single', 'index.html'), 'w').write(html)
print('dist-single/index.html', len(html) // 1024, 'KB')
