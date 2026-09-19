"""Draws the app icon: a roof over four sorted-waste blocks, gear in the roof.

The roof is maintenance, the blocks are the waste streams, in the same colours
the app uses for them. Written as code rather than drawn by hand so the gear
teeth and the block grid stay exact, and so a colour change is one edit.

    python3 tool/make_icon.py
    rsvg-convert -w 1024 -h 1024 assets/icon/icon.svg -o assets/icon/icon.png
    rsvg-convert -w 1024 -h 1024 -b none assets/icon/icon_foreground.svg \
        -o assets/icon/icon_foreground.png
    dart run flutter_launcher_icons
"""

import math
from pathlib import Path

TILE = "#EDF2F1"
ROOF = "#00796B"
BLOCKS = ["#0288D1", "#F9A825", "#5D4037", "#2E7D32"]

def gear(cx, cy, tip, root, teeth):
    pitch = 2 * math.pi / teeth
    pts = []
    for i in range(teeth):
        a = i * pitch - math.pi / 2
        for radius, offset in ((root, -0.30), (tip, -0.17), (tip, 0.17), (root, 0.30)):
            ang = a + offset * pitch
            pts.append((cx + radius * math.cos(ang), cy + radius * math.sin(ang)))
    d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    return d

MARK = f"""  <path d="M512 171 L870 461 L154 461 Z" fill="{ROOF}" stroke="{ROOF}"
        stroke-width="68" stroke-linejoin="round"/>
  <path d="{gear(512, 358, 62, 45, 8)}" fill="{TILE}" stroke="{TILE}"
        stroke-width="10" stroke-linejoin="round"/>
  <circle cx="512" cy="358" r="17" fill="{ROOF}"/>
  <rect x="178" y="549" width="307" height="137" rx="34" fill="{BLOCKS[0]}"/>
  <rect x="539" y="549" width="307" height="137" rx="34" fill="{BLOCKS[1]}"/>
  <rect x="178" y="740" width="307" height="137" rx="34" fill="{BLOCKS[2]}"/>
  <rect x="539" y="740" width="307" height="137" rx="34" fill="{BLOCKS[3]}"/>"""

def document(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">\n' + body + '\n</svg>\n')

# The bare mark measures 784x750 and sits a little above the canvas centre, so
# every placement re-centres it on 512,502 before scaling.
def placed(scale):
    return (f'  <g transform="translate(512 512) scale({scale}) '
            'translate(-512 -502)">\n' + MARK + '\n  </g>')

icon = document(f'  <rect width="1024" height="1024" rx="232" fill="{TILE}"/>\n'
                + placed(0.86))
# The adaptive foreground keeps to the inner 66% of the canvas: anything outside
# it is cropped away by whichever mask the launcher applies.
foreground = document(placed(0.95))

Path('assets/icon/icon.svg').write_text(icon)
Path('assets/icon/icon_foreground.svg').write_text(foreground)
print('written')
