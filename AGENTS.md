# Midnight DRRills (Godot 4.7, GDScript)
- Treat the repo as the source of truth; docs may be outdated.
- Save usage: do NOT run rendered/viewport/screenshot audits unless I ask. Run only the headless smoke tests that cover files you touched.
- Edit narrowly: no whole-file rewrites, no reformatting, no balance or card-number changes during refactors.
- Refactors must be behavior-preserving; tests/*_smoke.gd must pass before and after.
- Style: typed GDScript, short functions, lines under 120 chars, plain comments, no giant one-liners.
- One commit per finished step with a plain-English message.
- Final report: max 5 lines (what changed, tests run, what's next).
- Stop and tell me if a step fails twice or context passes ~70%.

## Godot notes for this project
- Godot 4.7 (tested with 4.7.2), GDScript only. The game is 3D (card_3d.gd, game_3d_manager.gd)
  with a 2D UI on top (run_director.gd).
- If a @tool script reads another script's static vars in the editor, that script must be @tool too
  (scripts/ui_theme.gd). Otherwise its static vars stay empty in the editor.
- Colors live in data/ui_theme.tres: the "Game" type is the palette, the other types are control styles.
  Edit them there; ui_theme.gd only keeps fallbacks. After a recolor, update the frozen list in
  tests/ui_palette_smoke.gd. A few hard-coded Color("...") literals are still in code.
- Commit the .uid files. The UI icon .png.import files keep process/fix_alpha_border=false.
- project.godot has 2d/snap/snap_2d_transforms_to_pixel=true (sharper moving UI text).
