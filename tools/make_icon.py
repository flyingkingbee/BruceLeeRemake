"""Draw the program icon, src/BruceLee.ico.

The picture is Bruce's extended flying kick, facing right: pose 18 in
data/bruce.bin, the same pixels as the game draws. Yellow is palette 7
and the tile is the playfield grey, palette 12. Black hair, eyes, and
trousers sit on top of the yellow.

A size that holds a whole multiple of the 30 by 17 picture shows every
pixel at that scale. 48 falls between those sizes, so the picture grows
to fill the tile and each source pixel is one or two pixels across.
16 and 24 are smaller than the picture. There a pixel stays lit if any
source pixel in its box is ink, and black wins over yellow, so the thin
kicking leg does not vanish.

Run it from the workspace root:

    python tools/make_icon.py

It writes src/BruceLee.ico and tmp/icon_preview.png, which shows every size.
"""

import math
import os

from PIL import Image, ImageDraw

CLEAR = (0, 0, 0, 0)
# Palette entries from src/game.cpp. 7 is Bruce's body, 12 is the
# playfield, 11 is the dark grey used for the tile edge.
YELLOW = (239, 243, 71, 255)
INK = (0, 0, 0, 255)
GREY = (120, 120, 120, 255)
EDGE = (71, 71, 71, 255)

POSE = 18  # flying kick right, leg extended
SPRITE_ROWS = 21
SPRITE_COLS = 32
FRAME_BYTES = SPRITE_ROWS * (SPRITE_COLS // 8)


def flying_kick(bruce_bin):
    """Pose 18 as a tight RGBA picture. Black replaces yellow where both are set."""
    with open(bruce_bin, "rb") as f:
        data = f.read()
    pixels = {}
    for plane, color in ((0, YELLOW), (1, INK)):
        start = (POSE * 2 + plane) * FRAME_BYTES
        frame = data[start:start + FRAME_BYTES]
        for y in range(SPRITE_ROWS):
            for x in range(SPRITE_COLS):
                bits = frame[y * 4 + x // 8]
                if bits & (0x80 >> (x & 7)):
                    pixels[(x, y)] = color
    xs = [p[0] for p in pixels]
    ys = [p[1] for p in pixels]
    minx, miny = min(xs), min(ys)
    width = max(xs) - minx + 1
    height = max(ys) - miny + 1
    img = Image.new("RGBA", (width, height), CLEAR)
    for (x, y), color in pixels.items():
        img.putpixel((x - minx, y - miny), color)
    return img


def span(count, dst):
    """How many output pixels each of `count` source pixels gets. The
    widths add up to `dst` and neighbours differ by one pixel at most."""
    base, extra = divmod(dst, count)
    widths = []
    error = 0
    for _ in range(count):
        width = base
        error += extra
        if error >= count:
            width += 1
            error -= count
        widths.append(width)
    return widths


def crisp_scale(sprite, dw, dh):
    """Scale up without blending. Used when the next whole multiple of
    the sprite does not fit, so the figure still fills the tile."""
    cols = span(sprite.size[0], dw)
    rows = span(sprite.size[1], dh)
    src = sprite.load()
    out = Image.new("RGBA", (dw, dh), CLEAR)
    y = 0
    for sy, height in enumerate(rows):
        x = 0
        for sx, width in enumerate(cols):
            pixel = src[sx, sy]
            if pixel[3]:
                for yy in range(height):
                    for xx in range(width):
                        out.putpixel((x + xx, y + yy), pixel)
            x += width
        y += height
    return out


def fit_down(sprite, max_w, max_h):
    """Shrink the sprite so a thin black line survives the smaller grid."""
    sw, sh = sprite.size
    scale = min(max_w / sw, max_h / sh)
    dw = max(1, round(sw * scale))
    dh = max(1, round(sh * scale))
    src = sprite.load()
    out = Image.new("RGBA", (dw, dh), CLEAR)
    dst = out.load()
    for oy in range(dh):
        y0 = math.floor(oy * sh / dh)
        y1 = math.ceil((oy + 1) * sh / dh)
        for ox in range(dw):
            x0 = math.floor(ox * sw / dw)
            x1 = math.ceil((ox + 1) * sw / dw)
            seen_yellow = False
            seen_black = False
            for y in range(y0, y1):
                for x in range(x0, x1):
                    if src[x, y][3] == 0:
                        continue
                    if src[x, y][:3] == INK[:3]:
                        seen_black = True
                    else:
                        seen_yellow = True
            if seen_black:
                dst[ox, oy] = INK
            elif seen_yellow:
                dst[ox, oy] = YELLOW
    return out


def place(sprite, size):
    """The sprite, as large as it can be, on a size x size canvas."""
    sw, sh = sprite.size
    # One pixel of air, more on the big tiles, so the figure does not
    # sit on the rounded corner or the edge.
    margin = 1 if size <= 32 else max(2, size // 32)
    inner = size - 2 * margin
    k = min(inner // sw, inner // sh)
    if k >= 1 and sw * k * 5 >= inner * 4:
        art = sprite.resize((sw * k, sh * k), Image.NEAREST)
    elif k >= 1:
        dw = inner
        dh = max(1, round(sh * inner / sw))
        art = crisp_scale(sprite, dw, dh)
    else:
        art = fit_down(sprite, inner, inner)
    canvas = Image.new("RGBA", (size, size), CLEAR)
    canvas.alpha_composite(art, ((size - art.size[0]) // 2, (size - art.size[1]) // 2))
    return canvas


def rounded(img):
    """The playfield grey, cut to a rounded square, with the figure on it."""
    n = img.size[0]
    radius = max(2, n // 6)
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, n - 1, n - 1], radius=radius, fill=255)
    plate = Image.new("RGBA", (n, n), GREY)
    out = Image.new("RGBA", (n, n), CLEAR)
    out.paste(plate, mask=mask)
    out.alpha_composite(img)
    # The corner cut stays clear if a pixel of the figure reaches it.
    clipped = Image.new("RGBA", (n, n), CLEAR)
    clipped.paste(out, mask=mask)
    ImageDraw.Draw(clipped).rounded_rectangle(
        [0, 0, n - 1, n - 1], radius=radius, outline=EDGE)
    return clipped


def icon(sprite, size):
    return rounded(place(sprite, size))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sprite = flying_kick(os.path.join(root, "data", "bruce.bin"))
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = {n: icon(sprite, n) for n in sizes}
    ico = os.path.join(root, "src", "BruceLee.ico")
    images[256].save(
        ico,
        format="ICO",
        sizes=[(n, n) for n in sizes],
        append_images=[images[n] for n in sizes if n != 256],
    )
    os.makedirs(os.path.join(root, "tmp"), exist_ok=True)
    gap = 8
    width = sum(sizes) + gap * (len(sizes) + 1) + 256 + gap
    sheet = Image.new("RGBA", (width, 256 + 2 * gap), (200, 200, 200, 255))
    x = gap
    for n in sizes:
        sheet.alpha_composite(images[n], (x, gap))
        x += n + gap
    sheet.alpha_composite(images[16].resize((256, 256), Image.NEAREST), (x, gap))
    preview = os.path.join(root, "tmp", "icon_preview.png")
    sheet.save(preview)
    print("sprite", sprite.size)
    print("wrote", ico)
    print("wrote", preview)


if __name__ == "__main__":
    main()
