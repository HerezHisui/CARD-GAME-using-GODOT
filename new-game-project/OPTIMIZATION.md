# October 16 optimization

The source project was reduced from 357,316,153 bytes to approximately 7.82 MB (97.8% smaller). These figures exclude generated import caches, builds and test screenshots on both sides. Git history is unchanged; earlier assets remain recoverable there.

## Assets and packaging

- Removed the two replaced classroom implementations, unused full-room conversion, Monika model/textures, unused card illustrations/backgrounds, abandoned environment scripts, old preview images and run logs from the active project.
- Kept the two still-used shaders, relocated to `assets/classroom_finish.gdshader` and `assets/board/drill_slate.gdshader`.
- Reduced `classroom_play_area.glb` from 7,330,500 to 2,023,492 bytes by referencing the 33 existing PNGs instead of embedding a second copy. The PNGs are byte-identical. All geometry buffers are byte-identical. No meshes, UVs, image dimensions, lighting features or card mechanics were reduced.
- Fresh-imported the remaining resources without the old cache. Added `.gdignore` to generated screenshots so Godot does not import them into its asset cache.
- Added a Windows export preset that includes card JSON data and excludes tests, tools, logs and documentation. The verified data pack is 7,271,788 bytes; an engine executable is additional. This is a data pack, not a standalone executable.
- `python tools/asset_audit.py` checks reachable resources, GLB external dependencies, geometry hash, all original image hashes and dimensions, and source footprint. It is read-only and fails on missing or unreferenced runtime content. The optional future title illustration deliberately falls back to the existing native title backdrop.

The follow-up whole-workspace cleanup removed `optimization-recovery-2026-10-16`, replaced classroom demo projects and texture libraries, bundled development tools, obsolete scene sources, backup files, ZIP snapshots, logs and preview images. The active classroom's editable FBX, textures and Blender scenes remain. Permanent deletion was blocked by automatic safety review, so removed items went to the Windows Recycle Bin. No recovery copies remain inside this workspace. Git history is preserved and locally recompressed; no remote changes or history rewriting were performed. Recycled items still use drive space until removed from the Recycle Bin.

## Runtime

- Shared one adapted material per imported material instead of duplicating it for every repeated desk/chair surface. Original surface materials and filtering remain intact.
- Limited fallback card-face state checks to 10 per second instead of every frame. Damage, healing and status methods still refresh immediately; dragging and animation still update each frame.
- Opponent backs now rebuild only when their displayed count changes. Sealing changes no longer trigger identical mesh reconstruction or scan the hand every frame.
- Removed unused procedural board-drawing helpers.

## Validation

Passed asset audit and fresh Godot import; `optimization`, `run`, `mechanics`, `hover_graveyard`, `notes4`, `notes5`, `final_boss`, `oct15`, `visual_quality` and `classroom_integration` suites. Graphical checks used Forward+ and retained MSAA/TAA, bloom, full rendering resolution, authored PBR maps and shared material identity. Inspected the resulting room capture. The export pack also passed the mechanics suite using the pack as its resource source.

The optimization suite verifies the actual fallback check count at simulated 120 Hz, immediate strength updates, bounded external-state updates, stable opponent backs after seal changes, and correct draw/discard counts.
