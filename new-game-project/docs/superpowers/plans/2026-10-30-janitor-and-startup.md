# Janitor and startup implementation checklist

Goal: integrate the supplied mesh as a skinned opponent with actual cloth simulation and card gestures;
show the supplied studio and game logos at startup. User authorized implementation without further
design approvals. No commits, pushes, or substantial downloads without permission.

Architecture: presentation remains separate from battle rules. A reusable character owns its skeleton,
grips, cloth and animation state. Battle decisions trigger gestures without taking ownership of resources
or outcomes. A launch scene owns a one-shot splash before the existing game and title menu.

- [x] Inspect both GLBs, texture backgrounds, existing battle hooks and available tools.
- [x] Preserve supplied files and take copies of overlapping uncommitted files before edits.
- [x] Create editable character source, weighted skeleton and animation resources; inspect deformation.
- [x] Identify cloth topology; use a stable runtime or baked simulation with pins and collisions.
- [x] Integrate character at opponent position; hide faces on all unrevealed held cards.
- [x] Connect base, evolution, utility and Warden gestures to actual decisions; test cancellation and cleanup.
- [x] Add proportional logo derivatives, studio splash, fades and input dismissal without click-through.
- [x] Verify affected headless suites and targeted rendered checks at 1280×800 and 1440×900.
- [x] Record cloth method, repairs, observed checks and unresolved limitations in a validation report.

Completed within the bounded clips and lower-robe simulation described in
`docs/janitor-validation-2026-10-30.md`. No claim of arbitrary humanoid motion or full garment physics.

Review focus: interrupted gestures, stale card visuals, repeated encounters, Warden without a deck,
camera movement revealing cards, cloth recovery, Continue, splash input leakage and responsive logo bounds.
