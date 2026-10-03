#!/usr/bin/env bash
# patch 240 — the suite's containers are named aps-conecta-* (D9, installer L4 S5).
#
# A GENERATED patch, like 010: a .patch could not survive upstream's churn on the nextcloud-aio-* lines.
# It runs last in the queue, so it renames what every other patch left. The rename itself, its data-derived
# name list, its keep-list and its verify live in scripts/rename-containers.py; its verify IS this patch's
# outcome.
#
# Queue contract (scripts/replay.sh): cwd is the replay worktree; APS_TOOLS_ROOT names the main checkout
# carrying scripts/. Idempotent by contract: a second run renames nothing and re-verifies.
#
# Fresh installs only. An instance installed with nextcloud-aio-* siblings keeps them; it is reinstalled,
# never migrated (gestion's INSTALLER.md §12).
#
# Only the mastercontainer and aio-nextcloud are built from this tree; the other siblings run upstream's
# images, retagged, which learn their peers' names from the *_HOST values the PHP sets. One does not:
# docker-socket-proxy's image resolves nextcloud-aio-nextcloud itself (its Dockerfile ENV and start.sh),
# so under these names it would wait forever. It cannot run on a fresh install — upstream deprecated it,
# and ConfigurationManager's setter only ever moves it towards off.
set -euo pipefail

exec python3 "${APS_TOOLS_ROOT:?APS_TOOLS_ROOT must name the main checkout carrying scripts/ (scripts/replay.sh sets it)}/scripts/rename-containers.py"
