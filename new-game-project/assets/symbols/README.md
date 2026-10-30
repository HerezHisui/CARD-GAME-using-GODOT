# Card and control symbols

These are imported 24 x 24 SVG pixel masks, authored on a 12 x 12 cell grid.
Every visible cell is a white 2 x 2 rectangle. The transparent background and
single foreground color give a crisp, limited palette. Card symbol controls use
nearest texture filtering. `UI.icon(kind, color)` caches tinted masks so gold,
disabled controls, and arbitrary theme colors keep their existing behavior.

Regenerate the assets and inventory with `python tools/author_symbols.py`.
No image generator, external package, or runtime SVG authoring is involved.
Godot imports the SVGs as texture resources. Keep their `.import` sidecars.

`inventory.json` lists every glyph, shared alias, and effect/modifier/on-hit key
found in the card JSON files. The supplied `midnight_card_symbols_v1.zip` had
53 names and matching gold/white exports. All 53 names remain supported. The
status atlas in `Downloads/reference for atk and status.png` informed the stepped
silhouettes; the supplied smooth SVG drawings were replaced with pixel geometry.

The former generic placeholders now have separate meanings:

| Key | Pixel design |
| --- | --- |
| condition | Diamond trigger with central marker |
| status_bonus | Status droplet with plus sign |
| utility_power | Bolt with power spark |
| taunt | Target reticle that attracts attacks |
| more | Three separate dots |
| fallback | Question mark for unknown keys only |

Healing, recovery, armor, barrier, draw, tutor, refund, tax, burst, thorns,
fragility, damage statuses, movement, and offensive traits have distinct glyphs.
Shared aliases are limited to matching meanings: draw/on-play draw,
strength/rally, sealed/seal, resting/sluggish, armor/brace, and relocation names.
Deadweight (`delay`) has its own weight glyph rather than a resting symbol.

Card faces use one centered grid in the reserved area between the stat badges,
or the larger utility area. There is no duplicate large primary symbol and no
overflow collapse. All effects remain represented as the grid shrinks; counts
and contextual tooltips stay attached to their symbols. Seal timing has a
separate visible label: `SEAL Rn` while pending and `SEALED` while active. Full
timing and rules remain in the tooltip and inspection panel.
