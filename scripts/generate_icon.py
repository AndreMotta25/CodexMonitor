#!/usr/bin/env python3
"""Draw the project's original terminal/gauge icon without external dependencies."""
import json
import math
import struct
import zlib
from pathlib import Path

size = 1024
output = Path(__file__).resolve().parent.parent/'CodexMonitor/Assets.xcassets/AppIcon.appiconset'
output.mkdir(parents=True, exist_ok=True)

def segment_distance(x, y, ax, ay, bx, by):
    t = max(0, min(1, ((x-ax)*(bx-ax)+(y-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2)))
    return math.hypot(x-ax-t*(bx-ax), y-ay-t*(by-ay))

rows = bytearray()
for y in range(size):
    rows.append(0)
    for x in range(size):
        glow = max(0, 1-math.hypot(x-820, y-180)/1100)
        color = [int(12+6*glow), int(24+25*glow), int(26+20*glow)]
        angle = math.atan2(y-512, x-512)
        ring = abs(math.hypot(x-512, y-512)-338)
        if ring < 17:
            alpha = min(1, 17-ring)
            ink = [65, 221, 169] if -2.5 < angle < 1.0 else [38, 67, 61]
            color = [round(a*(1-alpha)+b*alpha) for a,b in zip(color, ink)]
        distance = min(segment_distance(x,y,365,394,477,500), segment_distance(x,y,477,500,365,606),
                       segment_distance(x,y,535,606,668,606))
        if distance < 24:
            alpha = min(1,24-distance)
            color = [round(a*(1-alpha)+b*alpha) for a,b in zip(color,[229,249,241])]
        rows.extend(color)

def chunk(kind, data):
    return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)

png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(rows),9))+chunk(b'IEND',b'')
(output/'AppIcon.png').write_bytes(png)
(output/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}], 'info':{'author':'xcode','version':1}}, indent=2))

# Standalone icons also support a device build without Simulator asset services.
resources = output.parent.parent/'Resources'
resources.mkdir(exist_ok=True)
for target_size, name in [(120, 'AppIcon60@2x.png'), (180, 'AppIcon60@3x.png')]:
    reduced = bytearray()
    for y in range(target_size):
        reduced.append(0)
        for x in range(target_size):
            samples = []
            for dy in [0.25, 0.75]:
                for dx in [0.25, 0.75]:
                    sx = min(size-1, int((x+dx)*size/target_size))
                    sy = min(size-1, int((y+dy)*size/target_size))
                    offset = sy*(size*3+1)+1+sx*3
                    samples.append(rows[offset:offset+3])
            reduced.extend(round(sum(sample[c] for sample in samples)/len(samples)) for c in range(3))
    image = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',target_size,target_size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(reduced),9))+chunk(b'IEND',b'')
    (resources/name).write_bytes(image)
