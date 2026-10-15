# Supplied classroom and marked play area

The complete supplied FBX conversion remains unchanged in `classroom.glb`. The active game now uses `classroom_play_area.glb`, derived from the same source specifically for the annotated rear area.

Eight chairs in the two rear rows are removed; all 12 chairs outside that strip remain in their authored positions. Two central rear desks are cleared where they overlap the dedicated table. The other desks, bookshelf, lockers, windows, walls and props retain their original layout and PBR materials.

`GameTable` reuses a full authored student desk, including its UVs, wood texture, bevels and steel frame, enlarged and centred in the drawn table area. The playmat sits at y=1 and all eight existing game slots retain their gameplay coordinates.

The room is oriented around the gameplay board so `SchoolEnvironment/PlayerPosition` is on the left in the reference room view and `SchoolEnvironment/OpponentPosition` (the janitor) is on the right. Both are empty, facing markers, as requested earlier. Monika and replacement character models are not spawned. The normal camera looks across the board toward the janitor position and windows. S backs away to a nearby wider view on the same player-facing side; it no longer swings across the classroom. W returns toward the normal/overhead views. The overhead layout and character positions are unchanged. Camera transitions and W/S input are covered by `tests/camera_controls_smoke.gd`.

Darker lighting, window-beam attenuation and soft material reflections remain active. The surrounding classroom is not redesigned.

Editable source: `classroom-assets/supplied-classroom/Classroom_Play_Area.blend` in the workspace. Rebuild script: `classroom-assets/source/build_play_area.py`. `play_area_manifest.json` records the eight removed chair names, the two cleared desks, the dedicated table, the remaining mesh count, and runtime checksum. `source_manifest.json` retains the original full-room provenance and texture checksums.

Regression coverage: `tests/classroom_integration_smoke.gd` checks chair counts and cleared bounds, table alignment and fit, player/janitor sides, camera paths and aspect ratios, eight slot raycasts, battle startup, map and deck controls. `tests/visual_quality_smoke.gd` checks model integrity and rendering; `tests/hover_graveyard_smoke.gd` checks existing card input and graveyards. Regression runs use disposable saves.
