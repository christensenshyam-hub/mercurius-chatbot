"""Make a standalone copy of a Claude Design certificate (.dc.html):
{{name}} -> the sample name, [Date] -> the sample date, the /_blob/ mark ->
the local mark file, no support.js / x-dc wrapper / dc script, and the Google
Fonts link replaced by @font-face rules on the bundled TTFs (the same files
the app ships), so Chrome and the app draw with identical fonts.
Usage: standalone.py <in.dc.html> <out.html> <name> <date> <mark.png> <fonts-dir> [--measure]
"""
import re, sys, html
src, out, name, date, mark, fonts = sys.argv[1:7]
measure = '--measure' in sys.argv
s = open(src, encoding='utf-8').read()
s = s.replace('{{name}}', html.escape(name)).replace('[Date]', html.escape(date))
s = re.sub(r'src="/_blob/[0-9a-f]+"', 'src="file://%s"' % mark, s)
s = re.sub(r'<script src="\./support\.js"></script>\n?', '', s)
s = re.sub(r'<script type="text/x-dc"[\s\S]*?</script>\n?', '', s)
for tag in ('x-dc', 'helmet'):
    s = s.replace('<%s>' % tag, '').replace('</%s>' % tag, '')
s = re.sub(r'<link rel="preconnect"[^>]*>\n?', '', s)
s = re.sub(r'<link rel="stylesheet" href="https://fonts\.googleapis\.com[^>]*>\n?', '', s)
faces = ''
for fam, file, style, wght in [
    ('Cormorant Garamond', 'CormorantGaramond-Variable.ttf', 'normal', '300 700'),
    ('Cormorant Garamond', 'CormorantGaramond-Italic-Variable.ttf', 'italic', '300 700'),
    ('EB Garamond', 'EBGaramond-Variable.ttf', 'normal', '400 800'),
    ('EB Garamond', 'EBGaramond-Italic-Variable.ttf', 'italic', '400 800'),
]:
    faces += "@font-face{font-family:'%s';src:url('file://%s/%s') format('truetype');font-style:%s;font-weight:%s}\n" % (fam, fonts, file, style, wght)
s = s.replace('<style>\n', '<style>\n' + faces, 1)
if measure:
    js = r"""
<script>
document.fonts.ready.then(() => {
  const out = [];
  const root = document.body.querySelector('div');
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let n;
  while ((n = walker.nextNode())) {
    const t = n.textContent.trim();
    if (!t) continue;
    const r = document.createRange(); r.selectNodeContents(n);
    const el = n.parentElement; const cs = getComputedStyle(el);
    const lines = [...r.getClientRects()].map(b => [b.x, b.y, b.width, b.height].map(v => +v.toFixed(3)));
    out.push({text: t, font: cs.fontFamily.split(',')[0], size: cs.fontSize, weight: cs.fontWeight, style: cs.fontStyle, ls: cs.letterSpacing, lh: cs.lineHeight, color: cs.color, lines});
  }
  for (const el of root.querySelectorAll('img, svg, div')) {
    const b = el.getBoundingClientRect();
    if (el.tagName === 'DIV' && el.children.length) continue;
    out.push({el: el.tagName, box: [b.x, b.y, b.width, b.height].map(v => +v.toFixed(3))});
  }
  const pre = document.createElement('pre'); pre.id = 'measure';
  pre.textContent = JSON.stringify(out);
  document.body.appendChild(pre);
});
</script>
"""
    s = s.replace('</body>', js + '</body>')
open(out, 'w', encoding='utf-8').write(s)
