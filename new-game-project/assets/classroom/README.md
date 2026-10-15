# Midnight Classroom game integration

Native room and shared PBR maps from the standalone classroom-assets pack. Runtime adaptation is in scripts/classroom_environment.gd. Decorative physics and the asset preview camera/controller are excluded from gameplay. Furniture batches are trimmed around the card table and fixed cameras. Source Blender files and the full modular kit remain in the separate classroom-assets folder.

## Validation

Run `res://tests/classroom_integration_smoke.gd` with a graphical Godot renderer to check furniture placement, overhead-camera ceiling clearance, all eight slot-picking rays, battle startup, map toggle, deck menu, and title. It passed on Godot 4.7.2 Compatibility and Forward+. The existing hover/graveyard smoke test also passes. Regression scripts use disposable saves, leaving the real unfinished run intact.
