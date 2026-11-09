"""Sharp vector glyphs for the card and control symbols, exported as 24 x 24 white SVG masks.

Run from any directory with Python 3: python tools/author_glyphs.py
No third-party package and no image generator. Every path below is written by hand on a
24 x 24 grid: bold solid silhouettes, 45 degree cuts, and about 1.5 px of negative space for detail.
The masks stay white so UI.icon(kind, color) can tint them. Same names as before; inventory.json
is not changed. tools/author_symbols.py keeps the old 12 x 12 pixel versions as the source for
any glyph listed in KEEP_PIXEL.
"""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]

# (fill rule, path). "evenodd" cuts holes where subpaths are nested.
GLYPHS = {
    # Controls
    "on": ("nonzero", "M2.5 13 L6 9.5 L10 13.5 L18 5 L21.5 8.5 L10 20.5 Z"),
    "off": ("nonzero", "M4 7 L7 4 L12 9 L17 4 L20 7 L15 12 L20 17 L17 20 L12 15 L7 20 L4 17 L9 12 Z"),
    "arrow": ("nonzero", "M3 8.5 L6 5.5 L12 11.5 L18 5.5 L21 8.5 L12 17.5 Z"),
    "up": ("nonzero", "M3 15.5 L12 6.5 L21 15.5 L18 18.5 L12 12.5 L6 18.5 Z"),
    "updown": ("nonzero", "M5 9 L12 2 L19 9 L16.5 11.5 L12 7 L7.5 11.5 Z "
               "M5 15 L7.5 12.5 L12 17 L16.5 12.5 L19 15 L12 22 Z"),
    "empty": ("evenodd", "M6 3 H18 L21 6 V18 L18 21 H6 L3 18 V6 Z M6.5 6.5 V17.5 H17.5 V6.5 Z"),
    "radio_empty": ("evenodd", "M12 2 L22 12 L12 22 L2 12 Z M12 6 L6 12 L12 18 L18 12 Z"),
    "radio": ("evenodd", "M12 2 L22 12 L12 22 L2 12 Z M12 5.5 L5.5 12 L12 18.5 L18.5 12 Z "
              "M12 8 L16 12 L12 16 L8 12 Z"),
    "more": ("nonzero", "M2 9.5 H7 V14.5 H2 Z M9.5 9.5 H14.5 V14.5 H9.5 Z M17 9.5 H22 V14.5 H17 Z"),
    "fallback": ("nonzero", "M6 8 V6 L9 3 H15 L18 6 V10 L13.5 14 V16 H10.5 V12.5 L15 8.5 V7 L14 6 H10 "
                 "L9 7 V8 Z M10.5 18 H13.5 V21 H10.5 Z"),
    # Attack and damage
    "strength": ("nonzero", "M12 2 L21 11 H15.5 V22 H8.5 V11 H3 Z"),
    "piercing": ("nonzero", "M21.5 2.5 L21 12 L17.5 8.5 L6 20 L4 18 L15.5 6.5 L12 3 Z "
                 "M2 22 L2.5 17 L4 18.5 L5.5 20 L7 21.5 Z"),
    "blast": ("evenodd", "M12 1 L14 8 L20 4 L16 10 L23 12 L16 14 L20 20 L14 16 L12 23 L10 16 L4 20 "
              "L8 14 L1 12 L8 10 L4 4 L10 8 Z M12 9.5 L14.5 12 L12 14.5 L9.5 12 Z"),
    "fierce": ("nonzero", "M3 3 L6 2 L12 21 L10.5 22.5 Z M8 3 L11 2 L17 21 L15.5 22.5 Z "
               "M13 3 L16 2 L22 21 L20.5 22.5 Z"),
    "rampaging": ("nonzero", "M1.5 3 H6.5 L15.5 12 L6.5 21 H1.5 L10.5 12 Z "
                  "M9.5 3 H14.5 L23 12 L14.5 21 H9.5 L18.5 12 Z"),
    "flank": ("nonzero", "M3 22 V11 L7 7 H14 V3 L21 9.5 L14 16 V12 H8 V22 Z"),
    "thorns": ("nonzero", "M11 2 H13 V22 H11 Z M11 6 L5 3 L11 9.5 Z M13 10 L19 7 L13 13.5 Z "
               "M11 14 L5 11 L11 17.5 Z M13 18 L19 15 L13 21.5 Z"),
    "rally_all": ("nonzero", "M1.5 13 L4.5 8 L7.5 13 H5.6 V21 H3.4 V13 Z M9 8 L12 3 L15 8 H13.1 V21 H10.9 V8 Z "
                  "M16.5 13 L19.5 8 L22.5 13 H20.6 V21 H18.4 V13 Z"),
    "taunt": ("evenodd", "M8 1 H16 L23 8 V16 L16 23 H8 L1 16 V8 Z "
              "M9.5 4.5 H14.5 L19.5 9.5 V14.5 L14.5 19.5 H9.5 L4.5 14.5 V9.5 Z "
              "M12 8.5 L15.5 12 L12 15.5 L8.5 12 Z"),
    # Damage over time
    "bleed": ("evenodd", "M12 2 L19.5 12.5 V16 L16 21 H8 L4.5 16 V12.5 Z M8 13.5 H9.8 V18 L8 16.5 Z"),
    "burn": ("evenodd", "M12 1 L17 7 L18 5 L21 11 V16 L16 22 H8 L3 16 V10 L7 13 L8 6 Z "
             "M12 12 L15 16 L14 19 H10 L9 16 Z"),
    "poison": ("evenodd", "M5 3 H19 L21 6 V13 L18 16 V20 H6 V16 L3 13 V6 Z M7 8 H10.5 V11.5 H7 Z "
               "M13.5 8 H17 V11.5 H13.5 Z M9 16 H10.5 V20 H9 Z M13.5 16 H15 V20 H13.5 Z"),
    # Defense
    "armored": ("evenodd", "M12 2 L21 5 V12 L12 22 L3 12 V5 Z M5.5 10 H18.5 V11.5 H5.5 Z "
                "M11.25 4.5 H12.75 V10 H11.25 Z M11.25 11.5 H12.75 V19.5 H11.25 Z"),
    "barrier": ("evenodd", "M12 2 L21 5 V12 L12 22 L3 12 V5 Z M12 5.5 L18 7.5 V11.5 L12 18.5 L6 11.5 V7.5 Z"),
    "grave_guard": ("evenodd", "M6 19.5 V7 L9 3 H15 L18 7 V19.5 Z M11 6.5 H13 V9 H15.5 V11 H13 V17 H11 V11 "
                    "H8.5 V9 H11 Z M3 21 H21 V23.5 H3 Z"),
    "fragile": ("evenodd", "M12 2 L22 12 L12 22 L2 12 Z M11.6 3.5 L9.2 9 L13.2 13 L10.9 20.5 H12.1 "
                "L14.8 13 L10.8 9 L12.6 3.5 Z"),
    # Healing and support
    "heal_all": ("nonzero", "M9.5 7 H14.5 V11.5 H19 V16.5 H14.5 V21 H9.5 V16.5 H5 V11.5 H9.5 Z "
                 "M3 1 H5 V3 H7 V5 H5 V7 H3 V5 H1 V3 H3 Z M19 1 H21 V3 H23 V5 H21 V7 H19 V5 H17 V3 H19 Z"),
    "healing_reduced": ("nonzero", "M7 2 H12 V7 H17 V12 H12 V17 H7 V12 H2 V7 H7 Z "
                        "M15.5 13 H19.5 V18 H22.5 L17.5 23 L12.5 18 H15.5 Z"),
    "regenerating": ("nonzero", "M14 2 H8 L2 8 V16 L8 22 H16 L22 16 V11 H19.5 V15 L15 19.5 H9 L4.5 15 "
                     "V9 L9 4.5 H14 Z M14 0 L19 3.25 L14 6.5 Z "
                     "M10.5 7.5 H13.5 V10.5 H16.5 V13.5 H13.5 V16.5 H10.5 V13.5 H7.5 V10.5 H10.5 Z"),
    # Second try: one bite silhouette with two long fangs (the first try with a drop read as a crown).
    "leech": ("evenodd", "M2 3 H22 V8 H19.5 L16.5 21 L13.5 8 H10.5 L7.5 21 L4.5 8 H2 Z M5 4.5 H19 V6 H5 Z"),
    "herb": ("evenodd", "M21 3 L19.5 12 L12.5 19.5 H7 L3.2 23.3 L1.8 21.9 L5.5 18.2 L4.5 13 L12 5.5 Z "
             "M7 15.5 L17 5.5 L18.5 7 L8.5 17 Z"),
    "tablet": ("evenodd", "M2 14.5 L14.5 2 H16.5 L22 7.5 V9.5 L9.5 22 H7.5 L2 16.5 Z "
               "M8.8 7.7 L16.3 15.2 L15.2 16.3 L7.7 8.8 Z"),
    "cleanse": ("nonzero", "M12 1 L14.5 9.5 L23 12 L14.5 14.5 L12 23 L9.5 14.5 L1 12 L9.5 9.5 Z"),
    "status_bonus": ("nonzero", "M8 4 L14 10 L8 16 L2 10 Z "
                     "M15.5 12 H18.5 V15.5 H22 V18.5 H18.5 V22 H15.5 V18.5 H12 V15.5 H15.5 Z"),
    # Cards and turn flow
    "draw": ("nonzero", "M3 7 H13 L15 9 V22 H3 Z M7 2 H21 V17 H17 V14.5 H18.5 V4.5 H9.5 V5.5 H7 Z"),
    "tutor": ("evenodd", "M6 1 H14 L19 6 V14 L14 19 H6 L1 14 V6 Z M7 4 H13 L16 7 V13 L13 16 H7 L4 13 V7 Z "
              "M8 6.5 H12 V13.5 H8 Z M17.5 16 L23 21.5 L21.5 23 L16 17.5 Z"),
    "recover": ("nonzero", "M4 9 L10 3 V7 H16 L20 11 V17 L16 21 H8 V17.5 H14.5 L16.5 15.5 V12.5 "
                "L14.5 10.5 H10 V15 Z"),
    "move": ("nonzero", "M1 12 L7 6 V10 H17 V6 L23 12 L17 18 V14 H7 V18 Z"),
    "scout": ("evenodd", "M1 12 L7 6 H17 L23 12 L17 18 H7 Z M12 7.5 L16.5 12 L12 16.5 L7.5 12 Z "
              "M12 10 L14 12 L12 14 L10 12 Z"),
    "condition": ("evenodd", "M12 2 L23 21 H1 Z M11 8 H13 L12.6 15 H11.4 Z M11 17 H13 V19 H11 Z"),
    "delay": ("evenodd", "M5 2 H19 V4 L13.5 12 L19 20 V22 H5 V20 L10.5 12 L5 4 Z M8.2 4.5 H15.8 L12 9.8 Z"),
    "resting": ("nonzero", "M5 6 L7 4 H10 V20 H5 Z M14 4 H17 L19 6 V20 H14 Z"),
    "sealed": ("evenodd", "M7 10 V7 L9 4 H15 L17 7 V10 H14.5 V7.5 L13.5 6.5 H10.5 L9.5 7.5 V10 Z "
               "M4 10.5 H20 V21 H4 Z M11 13 H13 V18 H11 Z"),
    "tax": ("nonzero", "M4 4 H9 V9 H4 Z M15 15 H20 V20 H15 Z M17 3 H21 L7 21 H3 Z"),
    "refund_energy": ("nonzero", "M12 1 L5 9.5 H10 L8.5 15 L16 6.5 H11.5 Z "
                      "M20 12 V20 H8 V22.5 L3 18.75 L8 15 V17.5 H17.5 V12 Z"),
    "utility_power": ("nonzero", "M14 1 L4 14 H11 L9 23 L20 9.5 H13 Z"),
}

# Map room glyphs, same 24 x 24 grid and method. Written to assets/ui/map/<kind>.svg.
MAP_GLYPHS = {
    # Two crossed blades, each with a short grip.
    "battle": ("nonzero", "M22 2 L21.5 6 L9 18.5 L5.5 15 L18 2.5 Z M4 15.5 L8.5 20 L7 21.5 L2.5 17 Z "
               "M4.5 18.5 L5.5 19.5 L3 22 L2 21 Z "
               "M2 2 L2.5 6 L15 18.5 L18.5 15 L6 2.5 Z M20 15.5 L15.5 20 L17 21.5 L21.5 17 Z "
               "M19.5 18.5 L18.5 19.5 L21 22 L22 21 Z"),
    # Horned helmet with two eye slits.
    "elite": ("evenodd", "M2 3 L7 8 H17 L22 3 V11 L19 14 V19 L16 22 H8 L5 19 V14 L2 11 Z "
              "M7.5 12.5 H11 V15.5 H7.5 Z M13 12.5 H16.5 V15.5 H13 Z"),
    # Crown with a cut diamond, on a base bar.
    "boss": ("evenodd", "M2 5 L7.5 10.5 L12 2.5 L16.5 10.5 L22 5 V18 H2 Z M12 11 L14.5 14 L12 17 L9.5 14 Z "
             "M2 19.5 H22 V22.5 H2 Z"),
    # Square-cut cross: heal.
    "rest": ("nonzero", "M9 2 H15 V9 H22 V15 H15 V22 H9 V15 H2 V9 H9 Z"),
    # Supply bag with a handle and a cut coin.
    "shop": ("evenodd", "M4 8.5 H20 L21.5 22 H2.5 Z M12 11.5 L15 14.75 L12 18 L9 14.75 Z "
             "M7.5 8 V5 L10 2 H14 L16.5 5 V8 H14.5 V5.75 L13.25 4 H10.75 L9.5 5.75 V8 Z"),
    # Sharp question mark.
    "event": ("nonzero", "M5.5 8.5 V6 L9 2.5 H15 L18.5 6 V10.5 L14 14.5 V16.5 H10 V12.75 L14.5 8.75 V7 "
              "L13.5 6 H10.5 L9.5 7 V8.5 Z M10 18.5 H14 V22.5 H10 Z"),
    # Double chevron pointing up.
    "upgrade": ("nonzero", "M12 2 L21 11 L18 14 L12 8 L6 14 L3 11 Z M12 10 L21 19 L18 22 L12 16 L6 22 L3 19 Z"),
}

# Glyphs that were not readable as vectors after two tries keep the old pixel mask.
KEEP_PIXEL: set = set()


def old_pixel_svg(name: str) -> str:
    spec = importlib.util.spec_from_file_location("author_symbols", ROOT / "tools" / "author_symbols.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    rows = module.GLYPHS[name]
    top = (12 - len(rows)) // 2
    left = (12 - max(map(len, rows))) // 2
    pixels = [f'<rect x="{2*(left+x)}" y="{2*(top+y)}" width="2" height="2"/>'
              for y, row in enumerate(rows) for x, cell in enumerate(row) if cell == "#"]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
            'viewBox="0 0 24 24"><g fill="#ffffff">' + ''.join(pixels) + '</g></svg>\n')


def vector_svg(name: str, table: dict = GLYPHS) -> str:
    rule, path = table[name]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
            f'<path fill="#ffffff" fill-rule="{rule}" d="{path}"/></svg>\n')


def main():
    destination = ROOT / "assets" / "symbols"
    for name in sorted(GLYPHS):
        svg = old_pixel_svg(name) if name in KEEP_PIXEL else vector_svg(name)
        # LF line endings, like the old masks.
        with open(destination / f"{name}.svg", "w", encoding="utf-8", newline="\n") as handle:
            handle.write(svg)
    for name in sorted(MAP_GLYPHS):
        path = ROOT / "assets" / "ui" / "map" / f"{name}.svg"
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(vector_svg(name, MAP_GLYPHS))


if __name__ == "__main__":
    main()
