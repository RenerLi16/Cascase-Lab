"""Build the local landscape review from Godot screenshots (no export or deployment)."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/landscape'
OUT.mkdir(parents=True, exist_ok=True)
SCENARIOS = [json.loads(p.read_text()) for p in sorted((ROOT/'scenarios').glob('scenario_*.json'))]
LAYOUTS = {d['scenario_id']: d for p in (ROOT/'assets/maps/layouts').glob('*.json') if (d := json.loads(p.read_text()))}

def figure(path, caption):
    src = str(path)
    return f'<figure><a href="{src}" data-base="{src}"><img loading="lazy" src="{src}" data-base="{src}" alt="{html.escape(caption)}"></a><figcaption>{html.escape(caption)}</figcaption></figure>'

def pair(sid, state, caption):
    return '<div class="pair">'+''.join(figure(f'{phase}/1440-{sid}-{state}.png', f'{phase.title()} · {caption}') for phase in ['before','after'])+'</div>'

parts = ['''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cascade Lab · Landscape review</title>
<style>body{margin:0;background:#0b1b22;color:#dce6dc;font:17px/1.55 system-ui}main{max-width:1600px;margin:auto;padding:32px}h1,h2,h3{color:#e4c381;line-height:1.15}h1{font-size:38px}p{max-width:950px}a{color:#cde5dc}nav{position:sticky;top:0;background:#152b31;z-index:2;padding:12px;display:flex;gap:18px;flex-wrap:wrap}button{background:#344a40;color:white;border:1px solid #819475;border-radius:4px;padding:10px;cursor:pointer}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}figure{margin:8px 0 24px}img{width:100%;display:block;border:1px solid #304951}figcaption{font-size:14px;color:#b6c3bb;padding:8px}section{padding-top:32px;border-top:1px solid #304951;margin-top:32px}summary{cursor:pointer;color:#e4c381;font-size:21px;padding:16px 0}small{color:#b6c3bb}@media(max-width:850px){.pair{grid-template-columns:1fr}}</style>
<main><h1>Cascade Lab · Landscape review</h1><p>Four complete landscapes, preserving the medieval towers, forest and public-state beacons. Compare the original maps with the final local rendering. Click any image to inspect its full resolution.</p>
<nav><button onclick="resolution(1440)">1440 × 900</button><button onclick="resolution(1200)">1200 × 800</button>''']
for s in SCENARIOS: parts.append(f'<a href="#{s["scenario_id"]}">{html.escape(s["scenario_title"].split(":")[0])}</a>')
parts.append('</nav><p>Gameplay topology, bridge assignments, route costs and original delivery timing are unchanged. The gallery includes every designated crossing, closed decks, route previews, source selection, inspection views and the four camera corners.</p><p><small>Chinese-name views are rendering fixtures: ordinary production tower names remain English, as before. Source-picker Chinese text is the existing product UI. All captures are offline synthetic developer sessions.</small></p>')
for s in SCENARIOS:
    sid=s['scenario_id'];layout=LAYOUTS[sid]
    text=layout.get('composition','Riverside retains its existing composition: a continuous north–south river, the E–F crossing, a western settlement and an eastern branch. Scenery now covers the full camera range.')
    parts.append(f'<section id="{sid}"><h2>{html.escape(s["scenario_title"])}</h2><p>{html.escape(text)}</p>')
    parts.append(pair(sid,'overview-en','Overview'))
    parts.append('<details><summary>Compare every bridge crossing</summary>')
    for edge in s['bridges']:
        parts.append(f'<h3>Bridge {edge}</h3>'+pair(sid,'bridge-'+edge,edge+' crossing'))
    parts.append('</details><details><summary>Labels, routes and closed bridge</summary><div class="pair">')
    for state,label in [('overview-zh-fixture','Chinese public-name rendering fixture'),('sources-zh-fixture','Existing Chinese source picker'),('routes-en','Route preview and confirmation'),('closed-close','Closed bridge on its actual deck')]:
        # The bilingual source test uses -zh-fixture and the main capture supplies closed decks.
        parts.append(figure(f'after/1440-{sid}-{state}.png',label))
    parts.append('</div></details><details><summary>All tower inspection positions</summary><div class="pair">')
    for node in s['node_positions']: parts.append(figure(f'after/1440-{sid}-inspection-{node}.png',f'Tower {node} inspection'))
    parts.append('</div></details><details><summary>Camera pan limits</summary><div class="pair">')
    for x,y in [('-1000.0','-1000.0'),('2000.0','-1000.0'),('2000.0','1700.0'),('-1000.0','1700.0')]:parts.append(figure(f'after/1440-{sid}-pan-{x}-{y}.png',f'Camera corner {x}, {y}'))
    parts.append('</div></details></section>')
parts.append('''<script>function resolution(w){document.querySelectorAll('[data-base]').forEach(e=>{const s=e.dataset.base.replace('/1440-','/'+w+'-');e.tagName==='IMG'?e.src=s:e.href=s})}</script></main></html>''')
(OUT/'index.html').write_text(''.join(parts))
# Check every linked capture at both supported sizes, not just the default view.
import re
for src in re.findall(r'data-base="([^"]+)"',''.join(parts)):
    for width in (1440,1200):
        assert (OUT/src.replace('/1440-',f'/{width}-')).is_file(),src
print('Gallery verified:', OUT/'index.html')
