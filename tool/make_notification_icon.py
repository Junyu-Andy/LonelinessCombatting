#!/usr/bin/env python3
"""Android notification small icon from the 陪住 app icon (decisions-log
10/20 items 99/100).

Android draws a notification's small icon from its alpha channel only, so
the full-colour app icon shows as a blank square (and an old build showed
the Flutter logo).  This makes a white, single-colour silhouette on a
transparent background from `assets/icon/app_icon.png`: everything that is
not the icon's flat background colour, the largest connected shape (the two
figures and the table; the cups stay as cut-outs), centred in a square, and
written as `ic_stat_peizhu.png` at the five densities (24 dp; the shape fills
the middle 20 dp).

    python3 tool/make_notification_icon.py

Needs Pillow and numpy.  AndroidManifest.xml points FCM at
@drawable/ic_stat_peizhu and @color/notification_color.
"""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'assets/icon/app_icon.png'
RES = ROOT / 'android/app/src/main/res'
SIZES = {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96}


def silhouette() -> Image.Image:
    rgb = np.asarray(Image.open(SOURCE).convert('RGB')).astype(int)
    background = rgb[5, 5]
    distance = np.sqrt(((rgb - background) ** 2).sum(axis=2))
    mask = Image.fromarray(((distance > 40) * 255).astype(np.uint8), 'L')
    mask = np.asarray(mask.filter(ImageFilter.MedianFilter(9))) > 127

    # Keep the largest connected shape only (drops the tea-surface islands).
    h, w = mask.shape
    label = np.zeros(mask.shape, dtype=np.int32)
    sizes = []
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or label[y, x]:
                continue
            label[y, x] = len(sizes) + 1
            queue, count = deque([(y, x)]), 0
            while queue:
                cy, cx = queue.popleft()
                count += 1
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1),
                               (cy, cx - 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] \
                            and not label[ny, nx]:
                        label[ny, nx] = len(sizes) + 1
                        queue.append((ny, nx))
            sizes.append(count)
    keep = label == (1 + int(np.argmax(sizes)))
    shape = Image.fromarray((keep * 255).astype(np.uint8), 'L')
    shape = shape.crop(shape.getbbox())
    side = max(shape.size)
    square = Image.new('L', (side, side), 0)
    square.paste(shape, ((side - shape.width) // 2,
                         (side - shape.height) // 2))
    return square


def icon(shape: Image.Image, px: int) -> Image.Image:
    inner = round(px * 20 / 24)
    alpha = shape.resize((inner, inner), Image.LANCZOS)
    white = Image.new('RGBA', (inner, inner), (255, 255, 255, 255))
    white.putalpha(alpha)
    canvas = Image.new('RGBA', (px, px), (255, 255, 255, 0))
    canvas.alpha_composite(white, ((px - inner) // 2, (px - inner) // 2))
    return canvas


def main() -> None:
    shape = silhouette()
    for density, px in SIZES.items():
        out = RES / f'drawable-{density}' / 'ic_stat_peizhu.png'
        out.parent.mkdir(parents=True, exist_ok=True)
        icon(shape, px).save(out, optimize=True)
        print(out.relative_to(ROOT), px)


if __name__ == '__main__':
    main()
