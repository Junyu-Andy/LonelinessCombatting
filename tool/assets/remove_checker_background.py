"""Remove the baked-in grey/white checkerboard from agent PNGs -> RGBA.

The original agent illustrations were exported as RGB with a fake
"transparent" checkerboard painted in. This keeps only the figure:
light, unsaturated pixels connected to the image border become
transparent, with a soft 1-2px edge so there is no white halo.

Usage (needs Pillow, numpy, scipy):
    python3 tool/assets/remove_checker_background.py in.png out.png
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

def cutout(src, dst):
    a = np.asarray(Image.open(src).convert('RGB')).astype(np.int16)
    sat = a.max(2) - a.min(2)
    br = a.mean(2)
    bg_like = (sat <= 6) & (br >= 236)
    lab, _ = ndimage.label(bg_like)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    # Only background connected to the border is removed: every enclosed
    # light region in these images is an eye white, not checkerboard.
    # Soft edge: 1-2px ring of light, low-sat pixels just outside the
    # figure gets partial alpha so there is no white halo on dark surfaces.
    alpha = np.where(bg, 0, 255).astype(np.float32)
    ring = ndimage.binary_dilation(bg, iterations=2) & ~bg
    light = (sat <= 14) & (br >= 215)
    soft = ring & light
    alpha[soft] = np.clip((250 - br[soft]) / (250 - 200) * 255, 0, 255)
    alpha = ndimage.gaussian_filter(alpha, 0.6)
    alpha[bg & ~ndimage.binary_dilation(~bg, iterations=1)] = 0
    rgba = np.dstack([a.astype(np.uint8), alpha.clip(0, 255).astype(np.uint8)])
    Image.fromarray(rgba, 'RGBA').save(dst, optimize=True)

if __name__ == '__main__':
    cutout(sys.argv[1], sys.argv[2])
