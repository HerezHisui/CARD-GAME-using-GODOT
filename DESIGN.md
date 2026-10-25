---
name: Midnight DRRills
description: Brass-edged, cut-corner plates over a dark school at midnight, color-coded like a safety drill.
colors:
  background: "#0b0b0d"
  inset: "#111014"
  panel: "#1e1c20"
  raised: "#2c292e"
  bronze: "#c69c49"
  bronze-dim: "#81652f"
  bronze-deep: "#634e24"
  gold: "#e0b963"
  response: "#e0b963"
  amber: "#d99b26"
  crimson: "#8b1e24"
  crimson-deep: "#27080a"
  action: "#b8252b"
  danger: "#ed8985"
  text: "#eae4dc"
  muted: "#8c867e"
  disabled: "#77716c"
  affinity-evac: "#91ad59"
  affinity-douse: "#66a9b4"
  affinity-clearance: "#da9148"
  affinity-brace: "#b8bcc5"
  affinity-earthquake: "#c2aa57"
  affinity-fire: "#d65349"
  affinity-flood: "#598dc3"
  affinity-typhoon: "#a47bc1"
typography:
  heading:
    fontFamily: "Bahnschrift Condensed, Bahnschrift, Arial Narrow, Arial"
    fontSize: "30px"
    fontWeight: 700
  title:
    fontFamily: "Bahnschrift Condensed, Bahnschrift, Arial Narrow, Arial"
    fontSize: "22px"
    fontWeight: 700
  label:
    fontFamily: "Bahnschrift Condensed, Bahnschrift, Arial Narrow, Arial"
    fontSize: "18px"
    fontWeight: 700
  body:
    fontFamily: "Segoe UI, Arial"
    fontSize: "18px"
    fontWeight: 400
  small:
    fontFamily: "Segoe UI, Arial"
    fontSize: "14px"
    fontWeight: 400
rounded:
  none: "0px"
  bar: "3px"
  plate: "8px"
  badge: "9px"
  card: "10px"
  terminal: "16px"
spacing:
  xs: "5px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
components:
  button:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text}"
    typography: "{typography.label}"
    rounded: "{rounded.plate}"
    padding: "8px 12px"
  button-hover:
    backgroundColor: "{colors.background}"
    textColor: "{colors.gold}"
  button-disabled:
    backgroundColor: "{colors.background}"
    textColor: "{colors.disabled}"
  button-primary:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text}"
    typography: "{typography.label}"
    rounded: "{rounded.card}"
    padding: "20px"
  button-primary-disabled:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.disabled}"
  button-terminal:
    backgroundColor: "{colors.background}"
    textColor: "{colors.text}"
    typography: "{typography.title}"
    rounded: "{rounded.terminal}"
    padding: "20px"
  panel:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text}"
    rounded: "{rounded.plate}"
    padding: "16px"
  panel-dashboard:
    backgroundColor: "{colors.inset}"
    rounded: "{rounded.plate}"
    padding: "16px"
  panel-prompt:
    backgroundColor: "{colors.background}"
    rounded: "{rounded.plate}"
    padding: "16px"
  tooltip:
    backgroundColor: "{colors.inset}"
    textColor: "{colors.text}"
    rounded: "{rounded.plate}"
    padding: "16px"
  input:
    backgroundColor: "{colors.inset}"
    textColor: "{colors.text}"
    rounded: "{rounded.plate}"
    padding: "8px"
  card-frame-response:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.card}"
  card-frame-disaster:
    backgroundColor: "{colors.crimson-deep}"
    rounded: "{rounded.card}"
  card-badge:
    rounded: "{rounded.badge}"
  energy-bar:
    backgroundColor: "{colors.response}"
    rounded: "{rounded.bar}"
  tension-bar:
    backgroundColor: "{colors.danger}"
    rounded: "{rounded.bar}"
---

# Design System: Midnight DRRills

<!-- Sources: new-game-project/data/ui_theme.tres (normative), new-game-project/scripts/ui_theme.gd (fallbacks
and builders), docs/notes/ui/*.png (look of the UI). This is a Godot 4.7 Control theme, not CSS: "padding" means
StyleBoxFlat content margins, and sizes are in pixels at the 1280x800 base window. -->

## Overview

**Creative North Star: "The Drill Placard"**

The UI works like the safety signs in a school hallway at night: dark plates with cut corners and a brass edge,
very little text, and color that tells you what kind of hazard you are dealing with. The 2D layer sits over a 3D
classroom table. It frames the board and does not compete with it. Every panel, button, badge and bar is drawn from
the same brass-trimmed plate, so the screen reads as one family of signs.

The density is low and the layout is functional: a header strip, one bar per side for health and resources, the
hand along the bottom, and modals in the center. Gold is light catching the metal. It marks focus, hover, the
player's side and headings. Crimson marks the enemy side. The eight affinity colors carry the DRR lesson: each
response and each disaster has its own hue, shown as a band on the card.

**Key Characteristics:**
- Near-black warm-violet surfaces (`background` → `inset` → `panel` → `raised`) instead of pure black or grey.
- One plate shape everywhere: a 1px brass border, a 2px bottom edge and straight cut corners (`corner_detail = 1`).
- Gold and bronze are the only accents for UI chrome. Crimson and danger pink belong to the enemy.
- Condensed bold headings (Bahnschrift) over a plain body face (Segoe UI).
- Each affinity has its own color, and that color appears only on cards and type labels.

**Direction (target, not yet built).** The user's set direction is Limbus Company: a dark UI with gold accents,
minimal text and a hand-made feel. The palette and plate shape already point that way. These parts of the current
UI fall short and should move toward the target:
- Placeholder copy is still on screen ("MIDNIGHT DRRILLS (PLACEHOLDER) NEEDS TO BE ANOTHER IMAGE", the map legend's
  "PLACEHOLDER NEEDS TO BE THE SYMBOLS IMAGE"). These should be a logo image and symbols, not text.
- Card art windows are empty black boxes. The card has no illustration yet.
- The map side panel and the header stat line are lists of text. Icons and symbols should carry that meaning.
- System fonts (Segoe UI, Bahnschrift) look like default Windows. A hand-made feel probably needs a bundled
  display face. That choice is still open.
- Everything is drawn as flat StyleBoxFlat plates. Texture, wear and hand-drawn ornament do not exist yet.

## Colors

A warm near-black base, brass and gold for all UI chrome, crimson for the enemy, and eight muted hazard hues for
the card types.

### Primary
- **Lamplit Gold** (`gold`): the light on the metal. Used for hover and focus borders, hover text, headings, the
  player's HP bar, the energy bar, check marks, scrollbar grabbers and the caret. `response` is the same value
  under a semantic name, for anything that belongs to the player's side.
- **Worn Bronze** (`bronze`): the resting border on panels, card frames and badges. `bronze-dim` (bronze darkened
  35%) is the resting border of ordinary buttons. `bronze-deep` (darkened 50%) is used for separators and bar
  outlines.
- **Warning Amber** (`amber`): the lag bar behind HP drops, and the hazard trim drawn by `ui_plate.gd`.

### Secondary
- **Janitor Crimson** (`crimson`): the enemy's HP bar, the hover fill on popup menus and the text selection color.
  `crimson-deep` (crimson darkened 72%) fills Disaster card frames.
- **Alarm Red** (`action`): a strong red for urgent actions. In the screenshots it fills the Draw button.
- **Tension Pink** (`danger`): the Janitor's Tension bar.

### Tertiary
The affinity hues. They stay muted so they sit next to gold without fighting it.
- **Drill Green** (`affinity-evac`), **Hose Teal** (`affinity-douse`), **Debris Orange** (`affinity-clearance`),
  **Steel Brace** (`affinity-brace`) on the Response side.
- **Fault Ochre** (`affinity-earthquake`), **Ember Red** (`affinity-fire`), **Floodwater Blue** (`affinity-flood`),
  **Storm Violet** (`affinity-typhoon`) on the Disaster side.

On a card, the affinity band fills with that hue darkened 60%, and its border is the hue mixed 30% toward gold.

### Neutral
- **Midnight** (`background`): the screen base, button fills and text outlines.
- **Locker Shadow** (`inset`): recessed wells such as tooltips, inputs, the dashboard panel, bar tracks and scroll
  tracks.
- **Classroom Slate** (`panel`): the default panel and modal fill, and the Response card frame.
- **Raised Slate** (`raised`): a step lighter than `panel`. It is in the palette but not yet used by any theme
  style box.
- **Chalk** (`text`): all body and label text.
- **Faded Chalk** (`muted`): secondary text such as subtitles and counts.
- **Dust** (`disabled`): disabled text and disabled check icons.

### Named Rules
**The Brass-Only Chrome Rule.** UI chrome (borders, focus, hover, headings) uses only bronze and gold. Affinity
hues are for card types and nothing else.

**The Two Sides Rule.** Gold means the player and Response. Crimson and danger pink mean the Janitor and Disaster.
Never swap them.

**The One Palette Rule.** Colors live in the "Game" type of `data/ui_theme.tres`. `ui_theme.gd` only keeps the
fallbacks. After a recolor, update the frozen list in `tests/ui_palette_smoke.gd`.

## Typography

**Display Font:** Bahnschrift Condensed, weight 700 (fallbacks: Bahnschrift, Arial Narrow, Arial)
**Body Font:** Segoe UI (fallback: Arial)

**Character:** a condensed, engineered face for headings and buttons, like stencilled signage, with a neutral
Windows sans for reading. Both are SystemFonts, so they depend on what the player's Windows has installed.

### Hierarchy
- **Heading** (700, 30px, `HEADING_SIZE`): screen and modal titles such as THE SCHOOL MAP, DECK and the card name in
  the inspect panel. Shown in capitals and gold in the screenshots.
- **Title** (700, 22px): the large `TerminalButton` variant.
- **Label** (700, 18px): every button, `HeadingLabel`, and the bold font in RichTextLabel.
- **Body** (400, 18px, `BODY_SIZE`): the theme default for labels and rich text.
- **Small** (400, 14px, `SMALL_SIZE`): secondary lines such as "12 collected cards" and the map instructions.

### Named Rules
**The Stencil Rule.** Anything you click or anything that names a screen uses the condensed bold face. Running
text uses the body face.

**The Outline Rule.** Text over the 3D scene gets a `background`-colored outline through `UiTheme.outline()`
(2px by default). Text on plates gets no outline (`outline_size = 0`).

## Layout

The base window is 1280x800. The 2D UI frames the 3D table and leaves the middle of the screen to the board.

- **Battle:** a header plate across the top with the title, run stats and screen buttons. Under it, the player's HP
  bar sits top left and the enemy's HP and Tension bars sit top right. The hand fans out at the bottom center. A
  bottom strip holds energy on the left and Graveyard, Draw and End turn on the right.
- **Map:** a grid of room plates in rows by floor, numbered on the left, with gold route lines and junction dots.
  An info plate sits on the right and a single button at the bottom right.
- **Modals:** a centered plate with a gold heading, its content, and a full-width action at the bottom.

Spacing is a small set of fixed steps. Box containers and grids separate children by 12px. Plate content margins
are 5px (scroll tracks), 8px (inputs, vertical padding on buttons), 12px (horizontal padding on buttons), 16px
(panels) and 20px (primary and terminal buttons). `snap_2d_transforms_to_pixel` is on, so moving UI text stays
sharp.

## Elevation & Depth

The 2D UI is flat today. No style box has a shadow. Depth comes from tonal steps (`background` → `inset` → `panel`
→ `raised`) and from the 2px bottom border, which makes every plate look slightly thicker at its base. The 3D
classroom supplies the real depth and lighting. This is how things are now, not a rule. Shadows, glows or texture
may be added later if they serve the Limbus direction.

### Named Rules
**The Heavy Base Rule.** Every plate has a 1px border on top and sides and a 2px border at the bottom. Keep it on
new plates so they match the family.

## Shapes

One silhouette: a rectangle with straight cut corners. Every StyleBoxFlat uses `corner_detail = 1`, so a corner
radius draws a single diagonal cut instead of a curve. The size of the cut sets the role:

- **No cut** (`none`, 0px): affinity bands on cards.
- **Small cut** (`bar`, 3px): progress-bar fills and separators.
- **Standard cut** (`plate`, 8px): panels, modals, ordinary buttons, inputs, tooltips, popups and scrollbars.
- **Badge cut** (`badge`, 9px): the cost, ATK and HP badges on cards, with a 3px border.
- **Card cut** (`card`, 10px): card frames (4px border) and `PrimaryButton`.
- **Terminal cut** (`terminal`, 16px): `TerminalButton`, the heaviest chamfer.

The icons in `UiTheme.icon()` are 24px SVG line drawings, a 2px stroke inside a rounded 20px square. They are drawn
in gold by default and in Dust when disabled.

### Named Rules
**The Chamfer Rule.** Corners are cut, never rounded. Any new StyleBoxFlat keeps `corner_detail = 1`.

## Components

### Buttons
Plain metal plates with a stencilled label that light up gold when touched.
- **Shape:** standard cut (8px), 1px border with a 2px base.
- **Default:** `background` fill, `bronze-dim` border, Chalk label in the condensed bold face, 8px by 12px padding.
- **Hover / Pressed / Focus:** the border and label turn gold. Focus has a transparent fill, so it draws only a
  gold outline over the button.
- **Disabled:** the border dims to grey (`muted` darkened 55%) and the label turns Dust.
- **PrimaryButton:** card cut (10px), bronze border that turns gold on hover and focus, 20px padding, 18px label.
  End turn uses it. Its disabled fill is `panel`.
- **TerminalButton:** terminal cut (16px), 20px padding, 22px label, for the biggest calls to action.
- **Urgent fill:** the Draw button in the screenshots has an Alarm Red fill. That fill is not a theme variant.

### Cards / Containers
- **Panel / PanelContainer:** Classroom Slate fill, bronze border, 16px margin.
- **HeaderPanel:** the same as Panel. It is the top strip in battle.
- **ModalPanel:** a gold border instead of bronze, for overlays such as the draw picker.
- **DashboardPanel:** a Locker Shadow fill with a bronze border, for recessed info areas.
- **PromptPanel:** a Midnight fill with a gold (`response`) border, for prompts aimed at the player.
- **Tooltip:** a Locker Shadow fill.
- **Industrial trim:** `UiTheme.decorate()` adds a `ui_plate.gd` overlay drawn in bronze and amber, with an
  optional hazard pattern.

### Inputs / Fields
- **Style:** Locker Shadow fill, a bronze border darkened 40%, 8px margin, standard cut.
- **Focus:** the fill goes transparent and the border turns gold. The caret is gold and the selection is crimson.
- **Read-only:** looks the same as normal. Uneditable text is Dust.

### Navigation
- **Dropdowns and popups:** OptionButton uses the button plate with a gold chevron icon. PopupMenu sits on a
  panel. A hovered row gets a crimson fill with a gold border and gold text. Separators are thin `bronze-deep`
  bars.
- **Scrollbars:** a Locker Shadow track. The grabber is bronze at rest and gold when hovered or pressed. The
  increment and decrement arrows are gold chevron icons.
- **Checks and radios:** gold check, ring and dot icons, all drawn in Dust when disabled.

### Bars
- **EnergyBar / TensionBar:** a Locker Shadow track with a bronze border. The fill uses the small cut. Energy is
  gold (`response`) and Tension is danger pink.
- **HP bars (`apply_hud`):** the player's fill is gold with its value in Locker Shadow. The enemy's fill is
  crimson with its value in Chalk. Both have an amber lag bar behind them.

### Card (signature component)
The card is a placard of its own.
- **Frame:** card cut (10px), a 4px bronze border. Response cards fill with Classroom Slate and Disaster cards
  fill with `crimson-deep`.
- **Badges:** cost at the top left, ATK at the bottom left and HP at the bottom right. Each badge is badge cut
  (9px) with a 3px bronze border. The number is in the condensed bold face and tiny ATK and HP captions sit
  beside the badges.
- **Name:** at the top right, in the condensed bold face, above a thin line in the affinity color.
- **Art window:** a dark inset well. It is empty today.
- **Affinity band:** a full-width uncut strip under the art, filled with the affinity hue darkened 60% and
  labelled in capitals (EVAC, DOUSE, CLEARANCE).
- **Hand state:** in the screenshot, the cards in the hand fan slightly and overlap, each with a gold outline.

The screenshots in `docs/notes/ui/` are older than the latest UI commits. Since they were taken, the key hints
(`[D]`, `[Esc]`, `[Space]`, the W/S camera hints) were removed, the inspect panel became one box without the
Summary/Status/Effects tabs, and card pickers became one sideways-scrolling row. Take shapes and colors from the
screenshots, but not layout or copy.

## Do's and Don'ts

### Do:
- **Do** build every new surface from `UiTheme.panel()` or a theme type variation, so it gets the bronze border,
  the 2px base and the cut corners.
- **Do** use gold for hover, focus and the player's side, and bronze for borders at rest.
- **Do** change colors in the "Game" type of `data/ui_theme.tres`, then update `tests/ui_palette_smoke.gd`.
- **Do** keep affinity colors on cards and type labels, so each disaster and its counter stay easy to match.
- **Do** use the condensed bold face for buttons and headings and keep words to a minimum. Prefer an icon from
  `UiTheme.icon()` or a symbol over a sentence.
- **Do** outline text that sits over the 3D scene with `UiTheme.outline()`.

### Don't:
- **Don't** round corners. Keep `corner_detail = 1` on every StyleBoxFlat.
- **Don't** use affinity hues or crimson for neutral UI chrome.
- **Don't** add new hard-coded `Color("...")` literals in scripts. Add a "Game" color instead.
- **Don't** put key hints, captions or explanatory sentences back on screen. They were removed on purpose.
- **Don't** ship placeholder text in place of a logo or symbol image.
- **Don't** use pure black (`#000000`) or neutral grey surfaces. The base is a warm near-black.
