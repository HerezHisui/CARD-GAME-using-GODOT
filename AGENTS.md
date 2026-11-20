# Midnight DRRills (Godot 4.7, GDScript)
The rules for every agent live in new-game-project/CLAUDE.md. Read it first; it wins over this file.

## The loop
- Work from new-game-project. Start with `bash prompts/state.sh`.
- "Run the next mission in prompts/QUEUE.txt": take the first line that is not a comment and not marked DONE,
  read prompts/<name>.txt and do exactly what it says. One mission per run, then report and stop.
- Edit only the files on the mission's ALLOWED: line (new tests are always allowed).
- Suites: `bash prompts/run-suites.sh reset`, then `bash prompts/run-suites.sh` until it prints DONE.
  The scripts need bash (Git Bash). Give each call a 10-minute shell timeout.
- Before committing: git add the named paths only, then `bash prompts/mission-check.sh`. Commit only on CHECK OK.
  Mark the QUEUE line `DONE <hash>`.
- Never push. Never turn a flag on unless the mission names it. No Co-Authored-By or tool names in commits.
- Report in docs/notes/<name>-report.md under DIFF, RESULTS, BY EYE, FRICTION, SHAPES.

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
