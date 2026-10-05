"""Validate authored layouts; render editable SVG street layers and PNG guides.
Requires Pillow. Does not alter layouts, terrain, or simulation scenarios.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/map-alignment'
def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def intersects(a,b,c,d):return cross(a,b,c)*cross(a,b,d)<0 and cross(c,d,a)*cross(c,d,b)<0
for file in sorted((ROOT/'assets/maps/layouts').glob('*.json')):
 name=file.stem;layout=json.loads(file.read_text());nodes=layout['nodes'];roads=layout['edges']
 scenario=next(json.loads(p.read_text()) for p in (ROOT/'scenarios').glob('scenario_*.json') if json.loads(p.read_text())['scenario_id']==layout['scenario_id'])
 assert set(roads)=={a+'-'+b for a,b in scenario['edges']}
 assert tuple(layout['image_size'])==Image.open(ROOT/layout['texture'].removeprefix('res://')).size
 for eid,e in roads.items():
  assert e['centerline'][0]==nodes[e['from']]['anchor'] and e['centerline'][-1]==nodes[e['to']]['anchor']
  for a,b in zip(e['centerline'],e['centerline'][1:]):
   assert a!=b
   for nid,n in nodes.items():
    x,y,w,h=n['building'];margin=e['width']/2;x-=margin;y-=margin;w+=margin*2;h+=margin*2
    corners=[(x,y),(x+w,y),(x+w,y+h),(x,y+h)]
    assert not any(intersects(a,b,corners[k],corners[(k+1)%4]) for k in range(4)),(name,eid,nid)
   for fid,f in roads.items():
    if set((e['from'],e['to'])) & set((f['from'],f['to'])): continue
    for c,d in zip(f['centerline'],f['centerline'][1:]): assert not intersects(a,b,c,d),(name,eid,fid)
 # Export same layers/widths/order as NetworkView._draw_streets().
 svg=['<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">'%tuple(layout['image_size']+layout['world_size'])]
 for n in nodes.values():
  a,b=n['anchor'],n['entrance'];svg.append(f'<path d="M{a[0]} {a[1]} L{b[0]} {b[1]}" stroke="#d5cfb9" stroke-width="3"/>')
 for extra,color in [(10,'#c8c4b6'),(8,'#eee9d9'),(1.5,'#909a96'),(0,'#b5bbb7')]:
  for e in roads.values():
   points=' '.join(f'{x},{y}' for x,y in e['centerline']);svg.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{e["width"]+extra}"/>')
  for n in nodes.values():
   x,y=n['anchor'];svg.append(f'<circle cx="{x}" cy="{y}" r="{n["junction_radius"]+extra/2}" fill="{color}"/>')
 svg.append('</svg>');(OUT/f'{name}-streets.svg').write_text('\n'.join(svg))
 im=Image.new('RGB',(2000,1400),'#f0ecdf');d=ImageDraw.Draw(im)
 def pt(p):return tuple(round(v*2) for v in p)
 for e in roads.values(): d.line([pt(p) for p in e['centerline']],fill='#fffdf5',width=round(e['corridor_width']*2))
 for n in nodes.values():
  x,y=pt(n['anchor']);radius=(n['junction_radius']+6)*2;d.ellipse((x-radius,y-radius,x+radius,y+radius),fill='#fffdf5')
 for e in roads.values():d.line([pt(p) for p in e['centerline']],fill='#acb0ad',width=round(e['width']*2))
 for id,n in nodes.items():
  x,y=pt(n['anchor']);r=n['junction_radius']*2;d.ellipse((x-r,y-r,x+r,y+r),fill='#acb0ad')
  d.line([pt(n['anchor']),pt(n['entrance'])],fill='#ded7c5',width=6)
  x,y,w,h=n['building'];d.rectangle((x*2,y*2,(x+w)*2,(y+h)*2),fill='#8f9691',outline='#5e6d67',width=3);d.text((x*2+8,y*2+8),id,fill='white')
 im.save(OUT/f'{name}-guide.png');print(name,'verified',len(roads),'edges')
