"""Build a local visual review from actual Godot captures; never redraw game UI."""
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont
root = Path(__file__).resolve().parents[1]
out = root / 'docs/screenshots/tower-controls'
font = ImageFont.truetype(str(root/'assets/fonts/Barlow-SemiBold.ttf'), 19) if (root/'assets/fonts/Barlow-SemiBold.ttf').exists() else ImageFont.load_default(size=19)
states = [('idle','Idle'),('hover','Hover'),('focus','Keyboard focus'),('pressed','Pressed · face +3px'),('selected','Selected · before delivery'),('disabled','Installed · unavailable')]
sheet = Image.new('RGB',(1164,332),'#0b181d')
draw = ImageDraw.Draw(sheet)
for i,(state,title) in enumerate(states):
 x=16+(i%3)*384; y=12+(i//3)*164
 draw.text((x,y),title,font=font,fill='#eee5ce')
 shot=Image.open(out/'after'/f'1440-en-{state}-control.png').convert('RGB')
 sheet.paste(shot,(x,y+34))
sheet.save(out/'states.png',optimize=True)
Image.open(out/'before/inspector.png').crop((1016,172,1416,788)).save(out/'before/inspector-close.png')
parts=['''<!doctype html><html lang="en"><meta charset="utf-8"><title>Cascade Lab · Tower control review</title><style>body{background:#0b181d;color:#f0e8cf;font:18px/1.6 system-ui;max-width:1440px;margin:40px auto;padding:0 24px}h1,h2{color:#d5c18d}a{color:#a5d0c4}img,video{max-width:100%;height:auto;image-rendering:pixelated}figure{margin:0}section{margin:36px 0}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}details{border-top:1px solid #546455;padding:18px 0}summary{cursor:pointer}small{color:#b5c2b6}</style><h1>Lighthouse activation controls</h1><p>Actual game captures. Equal-size iron controls, original pixel icons, fixed brass rims and moving faces. No supply is spent until delivery confirmation; Monitor pressure becomes public only on arrival.</p><img src="states.png" alt="Idle, hover, focus, pressed, selected and disabled Monitor controls"><section><h2>Interaction recording · 7 seconds</h2><video controls muted playsinline preload="metadata" src="interaction.mp4"></video><p><small>Automated real-engine input: hover → focus → press → source selection → route preview → confirmation → arrival. The physical press is held briefly to make its travel visible. No audio.</small></p></section><h2>Before and after</h2><div class="grid"><figure><figcaption>Before</figcaption><img src="before/inspector-close.png"></figure><figure><figcaption>After</figcaption><img src="after/1440-en-idle-close.png"></figure></div><h2>Monitor label: before and after delivery</h2><div class="grid"><figure><figcaption>Old installed monitor: still unobserved</figcaption><img src="before/monitor-installed.png"></figure><figure><figcaption>New installed monitor: public live reading</figcaption><img src="after/1440-en-disabled.png"></figure></div>''']
for size in [1440,1200]:
 for lang,label in [('en','English'),('zh','Simplified Chinese')]:
  parts.append(f'<details><summary>{size} × {900 if size==1440 else 800} · {label} · all states</summary>')
  for state,title in states+[('preview','Route preview'),('map-label','Current Monitor reading')]:
   parts.append(f'<section><h3>{title}</h3><a href="after/{size}-{lang}-{state}.png"><img src="after/{size}-{lang}-{state}-close.png" alt="{title} in {label}"></a></section>')
  parts.append(f'<p><a href="after/{size}-{lang}-idle.png">Full inspector and map</a> · <a href="after/{size}-{lang}-disabled.png">After delivery</a></p></details>')
parts.append('<p>Balance caveat: Monitor still costs 1 supply and now provides Verify’s information plus persistent updates. Verify is retained; this dominance remains unresolved.</p></html>')
(out/'review.html').write_text('\n'.join(parts))
for src in re.findall(r'(?:src|href)="([^"]+)"',(out/'review.html').read_text()):
 assert (out/src).exists(),src
print(out/'review.html')
