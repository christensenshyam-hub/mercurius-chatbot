"""compare.py design.png app.png out-prefix [label]
Writes <prefix>-side.png (design | app, labelled) and <prefix>-overlay.png
(design in red, app in cyan: aligned ink reads dark grey, misses fringe red
or cyan), and prints the mean absolute difference and the bounding boxes of
the ink in a few bands so offsets can be read off as numbers."""
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps
d = Image.open(sys.argv[1]).convert('RGB')
a = Image.open(sys.argv[2]).convert('RGB')
prefix = sys.argv[3]
label = sys.argv[4] if len(sys.argv) > 4 else ''
assert d.size == a.size, (d.size, a.size)
W, H = d.size
pad, top = 24, 56
side = Image.new('RGB', (W * 2 + pad * 3, H + top + pad), (236, 236, 240))
side.paste(d, (pad, top)); side.paste(a, (W + pad * 2, top))
dr = ImageDraw.Draw(side)
try:
    f = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 26)
except Exception:
    f = ImageFont.load_default()
dr.text((pad, 14), 'Design (Chrome, %s)' % label, fill=(30, 30, 40), font=f)
dr.text((W + pad * 2, 14), 'App PDF (CertificateView via ImageRenderer, 150 dpi)', fill=(30, 30, 40), font=f)
side.save(prefix + '-side.png')
gd = ImageOps.grayscale(d); ga = ImageOps.grayscale(a)
over = Image.merge('RGB', (ga, gd, gd))  # red channel = app, g/b = design
over.save(prefix + '-overlay.png')
diff = ImageChops.difference(gd, ga)
hist = diff.histogram()
mean = sum(i * c for i, c in enumerate(hist)) / (W * H)
big = sum(c for i, c in enumerate(hist) if i > 64) / (W * H)
print('%s: mean |diff| %.3f, pixels off by >64: %.4f%%' % (label, mean, big * 100))
