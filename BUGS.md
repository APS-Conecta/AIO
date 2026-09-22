# Bugs — APS Conecta AIO (the fork's own tooling)

Fix log for this fork's infrastructure: what went wrong while building the patch queue, the
gates and the replay engine, and why each fix is right. **What is open right now lives in the
issue tracker** — this file is the durable record of the ones that are fixed and gated.

Each row names the cause and where the fix lives. The reasoning that made a fix non-obvious is
a comment beside the code it protects, not here — a second copy desyncs the day it is written.

| # | Symptom | Cause | Fix |
|---|---|---|---|
| A-001 | a replay run would have published main's tip instead of the worktree's replay commit | the one-patch push ran `git push` from the main checkout's cwd | `git -C "$WT" push` in `scripts/replay.sh` (design slice 7's de-risk) |
| A-002 | parity stayed green while an upstream file silently went missing at its path | git's default rename detection reports a byte-identical fork-side `git mv` as a single R status that BOTH diff-filter arms exclude | `--no-renames` on both parity diffs (design slice 7's verifier find) |
| A-003 | upstream's own codespell validator exits 65 over the es-CL sweep — on BOTH CI surfaces | the sweep puts 16 correct Spanish words (momento, comando, …) into the tree AND into patches/*.patch's bytes on main | `.codespellrc` (skip-self + the 16-word ignore list) riding patch 060 AND main as byte-coupled copies (design slice 11) |
| A-004 | the .codespellrc extension silently vanished from a regenerated patch while main's copy kept it — both CI surfaces stayed green | the tree reset between two regenerations and the build script did not own the edit | the extension is owned by the authoring build script, so no regeneration can drop it (design slice 12's R1) |
| A-005 | a dropped big view (7−2=5 refs) stayed green under the brand gate's `<use>` floor | the floor was set at 5 while the tree carries 7 refs — the documented protection failed | floor ≥ 7 with both drop-arms (−2 and −1) red (design slice 12's R1) |
| A-006 | brand-gate patterns beginning with `--` (e.g. `--color-nextcloud-blue`) silently matched nothing | grep parses a leading `--…` pattern as options | `grep -e` for every pattern that can begin with a dash (design slice 12) |
| A-007 | .codespellrc skip entries with a path prefix silently failed to skip | codespell matches skip entries against the path-prefixed name in some positions and the basename in others | basename globs (`070-*.patch`), per-file on purpose — never path-prefixed (design slice 12) |
| A-008 | the first font subsets shipped without the OFL §2 copyright/license records | subsetting dropped the name records; both upstream OFLs declare NO Reserved Font Name, so the subsets legally keep the family names | re-subset with name IDs 0 + 13 (design slice 12) |
| A-009 | bake.sh applied a MUTATED patch context "with fuzz 1" — a drifted patch shipped | GNU patch fuzz-matches by design | `git apply` at bake time — no fuzzy context, ever (design slice 13's de-risk) |
| A-010 | two bake.sh negative arms were VACUOUS — a missing worktree fell through the `\|\|` and the arms never ran | the half-state class | verified-landing re-staging: every arm proves its own red before it counts (design slice 13's de-risk) |
| A-011 | a replace() in the 090 authoring silently changed nothing | `str.replace` returns a new string; the result was discarded | every replace asserts its occurrence count — now the rule (design slice 18's de-risk) |
| A-012 | both playwright workflow invokers still ran the deleted deSEC specs — run.sh's file guard would exit 1 on every step | the deletion covered php/tests but not the workflow descs (the half-state class again) | both de-desc'd in the patch; suite_desec_absent greps BOTH scopes so "every reference" is true (design slice 18's R1) |

## Reporting a new one

Add a row. Put the reasoning that makes the fix non-obvious in a comment beside the code, and
the gate that stops it recurring in `scripts/brand-gate.sh`, `scripts/acquisition-gate.sh` or
`scripts/replay.sh`.

