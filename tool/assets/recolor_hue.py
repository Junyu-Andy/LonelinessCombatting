"""Shift the hue of parts of an agent PNG, keeping each pixel's saturation
and brightness (decision 0031: Ah Jan / Ah Bak recoloured without making
them paler).

Settings used on 2026-10-10 (run once on the transparent originals):
    ah_jan_*:  hue_only(img, [(110, 185, 30, 305), (215, 300, 10, 340)])
    ah_bak_*:  hue_only(img, [(160, 220, 30, 272)])
Needs Pillow and numpy.
"""
import numpy as np
from PIL import Image

def hue_only(img, bands):
    """bands: (hue_lo, hue_hi, min_sat, new_hue). Only the hue moves;
    saturation and brightness of every pixel stay as drawn."""
    rgba = np.asarray(img.convert('RGBA'))
    hsv = np.asarray(img.convert('RGB').convert('HSV')).astype(np.float32)
    h = hsv[..., 0] * 360 / 255
    oh = h.copy()
    for lo, hi, mins, nh in bands:
        m = (rgba[..., 3] > 0) & (h >= lo) & (h <= hi) & (hsv[..., 1] >= mins)
        oh[m] = (nh + (h[m] - np.median(h[m])) * 0.5) % 360
    hsv[..., 0] = oh * 255 / 360
    rgb = np.asarray(Image.fromarray(hsv.round().astype(np.uint8), 'HSV').convert('RGB'))
    return Image.fromarray(np.dstack([rgb, rgba[..., 3]]), 'RGBA')
