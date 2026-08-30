"""Shared geometry for ground tiles.

Lives in the asset tree rather than src/ because it is art, not machinery: it
encodes what a Gods and Lamb ground block IS, and changing it restyles the
whole world. `assets/_kit/` is skipped by registry discovery, which is how a
shared helper lives beside the assets that use it.

Every ground tile in the game is this function with two materials.

The shape decisions and what they cost are in Terrain/grass.py -- read that
first. In short: the sides stay flat and full width so tiles butt together, and
only the CAP is rounded, so a floor reads as separated blocks without opening a
hole wherever four tiles meet.
"""
from kit import M, box, soften_top, soften_all

# HALF-METRE GRID. The tile was 1.0 m and everything below is that set of
# numbers halved. The props did NOT change size with it -- that is the whole
# point of the change: a hut that spanned 1.6 tiles now spans 3.3, so the world
# has four times the tiles for the same ground and reads as detailed rather
# than as a handful of enormous blocks.
#
# Anything that measures itself against the ground measures against TILE, never
# against a literal 1.0.
SIZE = 0.5        # the grid module. Nothing may overhang it.
HEIGHT = 0.5      # top surface at z=0.5; everything that stands on the ground
                  # assumes exactly this.
CAP = 0.15        # depth of the cap band down the side faces. Most of the top
                  # of this band is eaten by ROUND, so it has to be deeper than
                  # the band you want to SEE on the side.
ROUND = 0.055     # top radius, as a fraction of the tile unchanged from the
                  # 1 m version -- the block silhouette is what was tuned, and
                  # it is scale-free.
SIDE = 0.35       # cap vertical-edge rounding as a fraction of ROUND, which is
                  # what separates one block from the next.


def ground_tile(tag, body_mat, cap_mat, cap=CAP, round_=ROUND, side=SIDE,
                height=HEIGHT, size=SIZE):
    """A ground block: a squared body with a rounded cap on top.

    Two boxes that MEET rather than overlap -- two coplanar faces inside a
    solid would z-fight once the tile is instanced a few hundred times, and the
    merge welds the seam anyway.

    Pass cap_mat is body_mat for a single-material block; the cap still exists,
    because it is what carries the rounding.
    """
    cap_z = height - cap * 0.5
    body_h = height - cap

    body = box(tag + "_Body", (0, 0, body_h * 0.5), (size, size, body_h),
               body_mat)
    top = box(tag + "_Cap", (0, 0, cap_z), (size, size, cap), cap_mat)

    # Only the cap is rounded -- it owns the top face. The body is buried
    # between its neighbours and the cap above it, so rounding it would cost
    # triangles for geometry nobody can see, and would open the very gap the
    # flat sides exist to avoid.
    soften_top(top, width=round_, segments=3, side=side)
    soften_all([body], width=0.0)   # smooth-shade only; tags it `softened`

    return [body, top]


def sunken_tile(tag, body_mat, cap_mat, drop=0.06, **kw):
    """A ground block whose surface sits BELOW the grid top.

    Water and anything else that should read as a hollow rather than a slab.
    The body still reaches z=0 so the block is solid from below; only the
    surface drops, which keeps the sides of neighbouring land tiles covered.
    """
    parts = ground_tile(tag, body_mat, cap_mat, height=HEIGHT - drop, **kw)
    return parts
