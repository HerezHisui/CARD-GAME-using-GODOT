# Janitor levitating-card pose

The right hand now supports a floating fan rather than gripping upright cards at table height.
The selected back also originates above that hand and advances toward the actual target before
the existing 0.52-second handoff. The left hand is free for the directing gesture, with a bounded
destination-facing shoulder adjustment. Card faces remain hidden on both sides.

Rebuilt the rigged GLB and editable Blender source through tools/build_janitor.py. Preserved
the original mesh, weights, textures, cloth method, card outcomes and release timing. The hands
retain the supplied bent-finger silhouette; this is a directing hand gesture, not a fully extended
index-finger pose or general-purpose finger rig revision.

Checks actually run:
- Existing janitor_smoke passed before changes. New levitation/origin assertions failed against
  the old implementation and passed after the fix.
- Blender validate_janitor.py passed all 138 poses with unchanged stretch limits.
- janitor_review_smoke passed rendered at 1280x800 Compatibility and 1440x900 Forward+.
  Includes real unit, spell and evolution actions, single spending, interruption, Continue,
  imported skin deformation, cloth and cleanup checks.
- Inspected idle, directing/release and desk-view captures. No detached sleeve spikes observed.
- Headless editor import and targeted git diff --check passed.

Captures: C:/Users/0stef/Downloads/janitor-levitation-review and
C:/Users/0stef/Downloads/janitor-levitation-review-1440.

Existing unrelated work was preserved. No commits or pushes. Long-session play remains untested.
