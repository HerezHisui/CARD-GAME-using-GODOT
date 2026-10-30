# Janitor rig and startup validation

The sleeve/finger streaks are corrected for the supplied idle, card-holding, card-playing and
Warden clips. Original mesh topology, UVs and embedded textures are retained. No commits or pushes
were made. Existing splash/title files and logo PNGs match their hashes from the start of this resume.

## Diagnosis and fix

The original failing draft was checked with animation, weights, bone transforms and cloth separated.
The saved before/after evidence is in `assets/characters/janitor/diagnosis_before.json` and `diagnosis.json`.

| Check | Finding |
| --- | --- |
| Bone placement/bind transforms | Neutral skin reproduces rest geometry within 0.00000017 model units. Rest bases have determinants near 1; shortest non-cloth bone is 0.03095 units. No singular bind transform or unexpected scale was found. |
| Skin weights | Truncating a smoothed field to eight weights made neighboring vertices lose different moving arm bones. Coordinate boxes also cut across low fingertips. Inward-facing cuff folds were partly attached to the hips. |
| Animation transforms | The draft rotated shoulders by 1.0/1.3 radians to compensate for a cropped camera view. Those lifts substantially exceeded the wrist adjustment needed at the table. |
| Cloth alone | Translating cloth bones by 6 mm did not reproduce the streaks. The original holding failure occurred in Blender without runtime cloth. |

Weights now use complete texture-identified hand regions, surface-distance cuff/sleeve transitions,
compact continuous bone support and bilinear cage weights. They fit eight influences directly, without
discarding moving bones. The original 26,959 vertices and 30,899 triangles remain. Bone locations were
not moved to conceal deformation.

The right shoulder now rotates -0.35 radians and the forearm -0.40 radians. This places the wrist near
the tabletop without the previous 75-degree shoulder lift. The left hand keeps its scanned pose before
the selecting/presenting/follow-through gesture. Desk camera height and pitch frame the whole hood
above the battlefield. Close-ups also show the full model, so framing is not used to conceal defects.

Card presentation releases at one shared 0.52-second boundary. The selected back's global center is
preserved for the authoritative board card's flight. Base cards, evolutions, utilities and scripted Warden
actions retain their existing gameplay effects. Presentation owns no resource spending or AI decisions.

## Assets and cloth method

- Runtime model: `assets/characters/janitor/janitor_rigged.glb`, one skin, 75 bones, two embedded images,
  and `idle`, `card_play`, `warden_pattern` animations. Both glTF weight sets import into Godot.
- Editable source: `assets/characters/janitor/source/janitor.blend`, with packed textures, actions,
  vertex groups and a hidden cloth-proxy reference. `.gdignore` keeps Blender out of runtime imports.
- Rebuild: run portable Blender with `--background --python-exit-code 1 --python tools/build_janitor.py`.
  The script reads the original Downloads GLB. Its SHA-256 remains
  `f6b455e40f8f2aef4ad59f82704fdc4a675b32cf941fac7b761331cfd64d862a`.
- Lower robe: runtime Verlet simulation on a closed 8-column, 5-row proxy. Upper ring pinned to hips;
  structural, shear and bend constraints; damping; body ellipsoid and floor collisions; displacement
  tethers and encounter/stall reset. `SkeletonModifier3D` applies particles after keyed animation.
- Sleeves and hands use skeletal deformation. They are not described as cloth simulation.

## Validation results

The original broad-stretch assertion remains `stretch_p99 < 2.5`. It was not weakened. Validation now
also requires `stretch_max < 4.0` and samples all 138 integer-frame poses across the three clips.

| Measurement | Result |
| --- | --- |
| Before: holding, without runtime cloth | 99th-percentile edge ratio 3.66279; maximum 23.69020; failed |
| After: all 138 Blender poses | Highest 99th percentile 1.87280; highest maximum 2.97974; passed |
| Imported rendered skin, idle/play/live cloth | 99th percentile below 1.881 and maximum below 2.954 at both target sizes; passed |
| Independent cloth after 1,200 substeps | Maximum constraint ratio 1.000047; pins, finite positions, floor and body collision checks passed |
| Applied cloth bone | Matches the simulated particle within 0.0001 units during modifier processing |

These limits detect severe stretching and spikes. They do not assert physically inextensible sleeves;
the skinned sleeve still has moderate local stretch under motion.

Godot 4.7.2 headless suites passed:

- `janitor_smoke.gd`: real skin, held-card count/back materials, exact handoff center, repeated plays,
  cloth constraints/collisions and interruption/reset.
- `janitor_review_smoke.gd`: actual base/evolution/utility plays, single resource spending, Warden
  gesture without fabricated cards, Continue and clean restored presentation.
- `startup_logo_smoke.gd`
- `menu_navigation_and_camera_smoke.gd`
- `final_boss_smoke.gd`
- `pillar_support_smoke.gd`
- `battle_engine_smoke.gd`: 63,729 comparisons.

Targeted rendered fixtures passed at 1280×800 using Compatibility and 1440×900 using Forward+.
Reviewed full-model idle/holding, selecting/presenting/playing poses, side grips, lower-robe motion,
three interrupted/restarted gesture cycles, actual unit/evolution play, Warden, desk/wide/board views,
studio splash, title and Continue. No finger streaks, detached sleeve spikes or visible proxy explosions
were observed in those captures. Hood remains below the HUD; battlefield and controls remain readable.
Unrevealed held visuals use only the card-back texture on both sides.

Rendered checks additionally read back the actual imported skinned mesh, apply the same stretch limits,
verify that the play pose moves vertices away from idle, and cancel a pending handoff during its wait.
Screenshots are in `%TEMP%/midnight-janitor-fixed-1280` and `%TEMP%/midnight-janitor-fixed-1440`.
Editor import and `git diff --check` passed; Git emitted existing line-ending normalization notices.

## Limits and manual repair

No manual topology repair was needed for these tested clips. The supplied asset is one connected,
textured surface without separate garment panels. Runtime simulation covers the lower robe only;
it does not provide full garment self-collision or simulated sleeves. The finger bones preserve the
scanned bent-hand grip; arbitrary independent finger curls and large shoulder raises are not certified.
Extending the range requires fresh deformation checks and potentially manual sleeve/underarm topology
and weight work. No general-purpose humanoid animation compatibility is claimed.

Physical controller input, prolonged play sessions and resolutions beyond the two target sizes were
not tested. Source validation, imported-skin checks and targeted captured frames are the evidence above.
