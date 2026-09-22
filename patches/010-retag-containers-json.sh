#!/usr/bin/env bash
# Patch 010 — containers.json registry org swap, GENERATED (never hand-edited). The whole
# patch is one call to the shared generator, scripts/retag.sh sed — the same org constants,
# the same prefix rule the retag walk uses — so upstream's next container auto-includes the
# day it lands (the sibling list is PARSED from containers.json, never hardcoded) and the
# one-rule doctrine holds: fix the generator, never the file.
#
# Queue contract (scripts/replay.sh, the script-patch channel): this runs with cwd = the
# replay worktree (upstream tip + the queue so far) and APS_TOOLS_ROOT = the main checkout
# that carries scripts/ — the worktree is upstream + patch effects, nothing else. The
# generator's own verify IS this patch's outcome: zero surviving ghcr.io/nextcloud-releases
# refs and a fork-ref count equal to the parsed sibling list, or it dies and the replay run
# reds naming this patch.
#
# Idempotent by contract — a second run swaps nothing and re-verifies, which is the script
# patch's "already applied" outcome under the three-outcome rule.
set -euo pipefail

exec "${APS_TOOLS_ROOT:?APS_TOOLS_ROOT must name the main checkout carrying scripts/ (scripts/replay.sh sets it)}/scripts/retag.sh" \
  sed php/containers.json
