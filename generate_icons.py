#!/usr/bin/env python3
"""Generate Deft app icon and menu bar icon.

Draws 4 keycaps labeled A, S, D, F (home row keys).
Uses only Python stdlib — no Pillow or external deps.
"""
import struct
import zlib
import os
import subprocess
import math


# Bitmap font for A, S, D, F — each letter is 5 wide x 7 tall
FONT = {
    'A': [
        0b01110,
        0b10001,
        0b10001,
        0b11111,
        0b10001,
        0b10001,
        0b10001,
    ],
    'S': [
        0b01111,
        0b10000,
        0b10000,
        0b01110,
        0b00001,
        0b00001,
        0b11110,
    ],
    'D': [
        0b11110,
        0b10001,
        0b10001,
        0b10001,
        0b10001,
        0b10001,
        0b11110,
    ],
    'F': [
        0b11111,
        0b10000,
        0b10000,
        0b11110,
        0b10000,
        0b10000,
        0b10000,
    ],
    'd': [
        0b00001,
        0b00001,
        0b01101,
        0b10011,
        0b10001,
        0b10011,
        0b01101,
    ],
}


def create_png(width, height, pixels):
    """Create a PNG file from RGBA pixel data (list of (r,g,b,a) tuples).

    pixels is row-major: pixels[y * width + x] = (r, g, b, a)
    """
    def make_chunk(chunk_type, data):
        c = chunk_type + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xffffffff)
        return struct.pack('>I', len(data)) + c + crc

    # PNG signature
    sig = b'\x89PNG\r\n\x1a\n'

    # IHDR
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    ihdr = make_chunk(b'IHDR', ihdr_data)

    # IDAT — raw pixel rows with filter byte
    raw = b''
    for y in range(height):
        raw += b'\x00'  # no filter
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw += struct.pack('BBBB', r, g, b, a)

    compressed = zlib.compress(raw)
    idat = make_chunk(b'IDAT', compressed)

    # IEND
    iend = make_chunk(b'IEND', b'')

    return sig + ihdr + idat + iend


def draw_rounded_rect(pixels, width, x0, y0, w, h, radius, color):
    """Draw a filled rounded rectangle."""
    r, g, b, a = color
    for py in range(y0, min(y0 + h, len(pixels) // width)):
        for px in range(x0, min(x0 + w, width)):
            # Check if pixel is inside rounded rect
            # Relative coords within the rect
            rx = px - x0
            ry = py - y0
            inside = False

            # Interior (not in corner zones)
            if radius <= rx <= w - radius - 1 or radius <= ry <= h - radius - 1:
                inside = True
            else:
                # Check corners
                corners = [
                    (x0 + radius, y0 + radius),           # top-left
                    (x0 + w - radius - 1, y0 + radius),   # top-right
                    (x0 + radius, y0 + h - radius - 1),   # bottom-left
                    (x0 + w - radius - 1, y0 + h - radius - 1),  # bottom-right
                ]
                for cx, cy in corners:
                    dist = math.sqrt((px - cx) ** 2 + (py - cy) ** 2)
                    if dist <= radius + 0.5:
                        inside = True
                        break

            if inside:
                idx = py * width + px
                if 0 <= idx < len(pixels):
                    pixels[idx] = (r, g, b, a)


def draw_letter(pixels, width, letter, cx, cy, scale, color):
    """Draw a bitmap font letter centered at (cx, cy)."""
    bitmap = FONT.get(letter)
    if not bitmap:
        return

    fw, fh = 5, 7
    total_w = fw * scale
    total_h = fh * scale
    start_x = cx - total_w // 2
    start_y = cy - total_h // 2

    for row_idx, row in enumerate(bitmap):
        for col in range(fw):
            if row & (1 << (fw - 1 - col)):
                for sy in range(scale):
                    for sx in range(scale):
                        px = start_x + col * scale + sx
                        py = start_y + row_idx * scale + sy
                        idx = py * width + px
                        if 0 <= px < width and 0 <= py < (len(pixels) // width) and 0 <= idx < len(pixels):
                            pixels[idx] = color


def generate_app_icon(size):
    """Generate app icon at given size — dark bg, light keycaps with ASDF."""
    pixels = [(45, 45, 50, 255)] * (size * size)  # dark background

    # Overall rounding of the background
    # (macOS applies its own mask, but we round the bg for clean preview)
    margin = max(1, size // 16)
    bg_radius = max(2, size // 5)

    # Clear to transparent first, then draw rounded bg
    pixels = [(0, 0, 0, 0)] * (size * size)
    draw_rounded_rect(pixels, size, 0, 0, size, size, bg_radius, (45, 45, 50, 255))

    # Keycap layout
    letters = ['A', 'S', 'D', 'F']
    num_keys = 4

    padding = max(2, size // 8)
    available = size - 2 * padding
    gap = max(1, size // 24)
    key_w = (available - (num_keys - 1) * gap) // num_keys
    key_h = max(key_w, int(key_w * 1.1))

    key_radius = max(1, key_w // 6)

    # Center vertically
    total_h = key_h
    y_start = (size - total_h) // 2
    x_start = padding + (available - (num_keys * key_w + (num_keys - 1) * gap)) // 2

    # Key colors
    cap_color = (224, 224, 228, 255)    # light keycap
    letter_color = (50, 50, 55, 255)     # dark letter
    shadow_color = (30, 30, 35, 255)     # subtle shadow

    font_scale = max(1, key_w // 7)

    for i, letter in enumerate(letters):
        kx = x_start + i * (key_w + gap)

        # Shadow (offset down by 1-2px)
        shadow_off = max(1, size // 128)
        draw_rounded_rect(pixels, size, kx, y_start + shadow_off, key_w, key_h, key_radius, shadow_color)

        # Keycap
        draw_rounded_rect(pixels, size, kx, y_start, key_w, key_h - shadow_off, key_radius, cap_color)

        # Letter
        letter_cx = kx + key_w // 2
        letter_cy = y_start + (key_h - shadow_off) // 2
        draw_letter(pixels, size, letter, letter_cx, letter_cy, font_scale, letter_color)

    return create_png(size, size, pixels)


def generate_menubar_icon(size):
    """Menu bar template icon: one keycap with a lowercase 'd' punched out.

    A single glyph stays readable at 18px, unlike the old four-keycap design.
    """
    pixels = [(0, 0, 0, 0)] * (size * size)  # transparent

    margin = max(2, size // 9)
    key = size - 2 * margin
    key_radius = max(2, key // 4)
    draw_rounded_rect(pixels, size, margin, margin, key, key, key_radius, (0, 0, 0, 255))

    # Punch the 'd' out of the keycap (transparent letter), ~60% of cap height
    font_scale = max(1, int(key * 0.6) // 7)
    draw_letter(pixels, size, 'd', size // 2, size // 2, font_scale, (0, 0, 0, 0))

    return create_png(size, size, pixels)


def main():
    os.makedirs("resources", exist_ok=True)

    # Generate .iconset for app icon
    iconset_dir = "AppIcon.iconset"
    os.makedirs(iconset_dir, exist_ok=True)

    icon_sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    print("Generating app icon sizes...")
    for filename, size in icon_sizes:
        path = os.path.join(iconset_dir, filename)
        png_data = generate_app_icon(size)
        with open(path, 'wb') as f:
            f.write(png_data)
        print(f"  {filename} ({size}x{size})")

    # Convert to .icns
    print("Converting to AppIcon.icns...")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", "resources/AppIcon.icns"], check=True)

    # Generate menu bar icons
    print("Generating menu bar icons...")

    menubar_1x = generate_menubar_icon(18)
    with open("resources/menubar_icon.png", 'wb') as f:
        f.write(menubar_1x)
    print("  menubar_icon.png (18x18)")

    menubar_2x = generate_menubar_icon(36)
    with open("resources/menubar_icon@2x.png", 'wb') as f:
        f.write(menubar_2x)
    print("  menubar_icon@2x.png (36x36)")

    # Cleanup iconset directory
    import shutil
    shutil.rmtree(iconset_dir)

    print("\nDone! Generated:")
    print("  resources/AppIcon.icns")
    print("  resources/menubar_icon.png")
    print("  resources/menubar_icon@2x.png")


if __name__ == "__main__":
    main()
