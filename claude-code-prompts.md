# Prompts for Claude Code: Midnight DRRills

Work in `github-publish/new-game-project`. Send one prompt at a time, in order. Paste each report back to Claude chat before sending the next prompt.

## Before you start (you do this, not Claude Code)

1. Copy `CLAUDE.md` into the repo root, next to `AGENTS.md`.
2. Play-test the shop by hand at 1280x800: buy a card, buy heal, preview, cancel, confirm a card removal, save and resume mid-shop. Check the Errors tab (baseline 40 entries). If anything is wrong, run `git reset --hard before-run-shop`.

## Prompt A: commit CLAUDE.md

```
Goal: commit the new CLAUDE.md.
Do: check that CLAUDE.md in the repo root loads AGENTS.md (the @AGENTS.md line). Change nothing else. Commit only CLAUDE.md with the message "add Claude Code instructions".
Don't: edit any other file.
Report: max 5 lines.
```

## Prompt B: two checks, report only (no edits)

```
Goal: answer two questions. Read only. Do not edit or commit.
1. Run ui_consistency_smoke.gd headlessly. Tell me exactly what it prints: pass, fail, or skipped. My baseline says skipped.
2. Run git ls-files '*.uid' and look at .gitignore. Tell me if .uid files are tracked, which scripts have no .uid file, and whether run_shop.gd.uid, run_card_rules.gd, run_routes.gd and run_debug.gd are missing theirs.
Report: max 5 lines.
```

## Prompt C: sync the shop split to the playable copy

Send this only after your play-test passes.

```
Goal: copy the shop split from github-publish to the playable copy CARD-GAME-using-GODOT-main.
Files: copy only scripts/run_shop.gd and scripts/run_director.gd, into CARD-GAME-using-GODOT-main/new-game-project/scripts/.
Do: before copying, show me a diff of run_director.gd between the two folders. If the diff has anything besides the shop and removal wrappers, stop and tell me. After copying, run collection_shop_upgrades_and_ai_smoke.gd, run_smoke.gd and coin_rewards_smoke.gd in the playable copy.
Don't: copy any other file, any .uid file, or any asset. Do not commit unless that folder is a git repo; if it is, one commit.
Report: max 5 lines.
```

## Prompt D1: find the SubViewport error (diagnose only)

```
Goal: find the cause of the repeated red error "Path to node is invalid: '@SubViewport@...'". Read only. Do not edit.
Where it shows: run_director.gd in _card_tile, and game_3d_manager.gd in add_card_to_hand and _enemy_turn. Find the current line numbers yourself with grep.
Look at: scripts/card_3d.gd. It builds a SubViewport in _build_face(), then uses _vp.get_texture() on the art sprite and as the dissolve shader's card_face parameter. My guess is that a ViewportTexture is used before the card (or its SubViewport) is inside the scene tree, or after it was freed. Check this guess. Do not trust it.
Done when: you can say which line makes the bad path, why, and the smallest fix.
Process: show the cause and the proposed fix in a few lines. Do not edit until I say OK.
Report: max 5 lines.
```

After you paste the report to me, I write Prompt D2 for the fix.

## Prompt E: Coordinated Response visuals (plan first)

```
Goal: when Coordinated Response is armed, valid targets pulse red. Before combat, show a +1 ATK preview on the chosen ally and its nearest neighbors.
Files: scripts/contingency_rules.gd (card definition near line 6, effect near line 114), scripts/card_3d.gd, scripts/game_3d_manager.gd. Find where armed Plans are tracked yourself.
Do: visuals only. Reuse an existing highlight or pulse in card_3d.gd if there is one. Keep it short and simple.
Don't: change the card's rules, cost, text or numbers. Do not touch save formats.
Done when: contingency_plans_smoke.gd and board_targeting_plans_and_events_smoke.gd pass before and after, and I can see the pulse and preview when I play-test at 1280x800.
Process: git tag before-coordinated-response. Show the plan first and wait for my OK. One commit.
Report: max 5 lines.
```

## Prompt F: split events out of run_director.gd

Same method as the shop split.

```
Goal: move the event logic out of run_director.gd into a new run_events.gd, the same way run_shop.gd was done.
Files: scripts/run_director.gd (edit), scripts/run_events.gd (new).
Do: extends RefCounted with static functions that take director: Node first. Leave one-line wrappers with the same names and signatures in run_director.gd. Keep all state in run_director.gd, because run_save.gd reads it.
Plan first: list the exact functions you will move, check none use await or signals, and name the smoke tests that cover them (use grep). Wait for my OK.
Don't: change behavior, text, balance or save formats. Do not touch any other file.
Process: git tag before-run-events. Run the covering tests before and after. One commit.
Report: max 5 lines.
```

## Order if time runs short (trailer is Oct 30)

A, then D1 and D2, then E. Do B, C and F after the trailer.
