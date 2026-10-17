# Midnight DRRills (Godot 4.7, GDScript)
- Treat the repo as the source of truth; docs may be outdated.
- Save usage: do NOT run rendered/viewport/screenshot audits unless I ask. Run only the headless smoke tests that cover files you touched.
- Edit narrowly: no whole-file rewrites, no reformatting, no balance or card-number changes during refactors.
- Refactors must be behavior-preserving; tests/*_smoke.gd must pass before and after.
- Style: typed GDScript, short functions, lines under 120 chars, plain comments, no giant one-liners.
- One commit per finished step with a plain-English message.
- Final report: max 5 lines (what changed, tests run, what's next).
- Stop and tell me if a step fails twice or context passes ~70%.