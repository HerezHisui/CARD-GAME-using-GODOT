# CARD-GAME-using-GODOT

## Midnight DRRills

Open `new-game-project/project.godot` in Godot 4.7 and run the main scene. The game is a singleplayer card roguelike. Multiplayer is listed in the menu but is not playable yet.

### Design documents

- [Singleplayer design and development history](docs/singleplayer.md): rules, card and buff catalogs, balance changes, and remaining work.
- [Singleplayer Word document](docs/Singleplayer.docx)
- [Multiplayer design and deck builder](docs/multiplayer.md): proposed deck construction, asymmetric economies, match flow, and implementation stages.
- [Singleplayer Google Doc](https://docs.google.com/document/d/10zsNwhLedizfDTOK4vlviINSWIs5Ac2iJCXESA2Og0c/edit)
- [Multiplayer Google Doc](https://docs.google.com/document/d/1lyxR52jlt4Z28vOycWLNDVeqEhnon1TOcE0jDcJ0EQo/edit)
- [Player guide](new-game-project/RUN_GUIDE.md)

The singleplayer reference is updated through 16 October 2026, including notes `/5`, the supplied classroom, presentation changes and optimization. The multiplayer proposal remains dated 14 October. The linked Google Docs are separate editable copies and have not been updated by this local document revision.

### Latest playable update

- Procedural maps climb upward through eleven stages with mandatory combat before each boss.
- Plans, direct board targeting, additional events, an actual hidden enemy hand, separate graveyards, and a predictable final boss.
- Updated title screen, Continue and Abandon Run, recent-card sorting, and live card stats.
- Preparedness energy and protection limits, temporary cost disruption, sacrifice rewards, and major evolution entry effects.
- Heads/Tails calls, centered rewards, enlarged card inspection and the supplied classroom with a framed slate board.
- Resource cleanup with original geometry and texture quality preserved.

The source folder is the current version. Obsolete ZIP snapshots and the unused standalone drag-script sample have been removed. The active project is approximately 7.82 MB, with unused environments removed and all active classroom geometry and textures preserved. See [optimization details](new-game-project/OPTIMIZATION.md) for measurements and validation. The whole-workspace cleanup also removed bundled tools, replaced asset projects, caches and recovery folders; removed local files went to the Windows Recycle Bin.

### Verification

Run Godot with `--headless --path new-game-project --script res://tests/<suite>_smoke.gd`. Gameplay suites include `run`, `mechanics`, `expansion`, `improvements`, `variety`, `hover_graveyard`, `final_boss`, `plans_notes`, `notes3`, `notes4`, `notes5`, `oct15` and `optimization`. Use a graphical renderer for `classroom_integration`, `camera_controls` and `visual_quality` captures. Run `python new-game-project/tools/asset_audit.py` for dependency and lossless asset verification.
