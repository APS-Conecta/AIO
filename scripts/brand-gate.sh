#!/usr/bin/env bash
# S4's brand gate — the replayed tree must carry OUR identity on every surface the patch queue
# claims to have rebranded. Runs from THIS checkout (main, where the queue lives) against the
# REPLAYED TREE (the worktree replay.sh leaves at .aps-replay-tree — what the Images pipeline
# builds and the clinic runs).
#
# THE ROW CONTRACT — how the gate grows with the queue (and stays green while it fills, design
# slices 8-13): a row fires only when its patch is in patches/. An empty queue is an honest
# green — nothing claims to be rebranded — and every skipped row prints visibly, never silent.
# The reverse direction is replay.sh's coverage rule: a queued patch with no row anywhere
# aborts the replay before aps/main moves.
#
# WHAT LANDS NOW: the registry-ref rows — the FRD's brand contract verbatim, zero
# ghcr.io/nextcloud-releases refs including php/src. 010 owns containers.json (plus the
# fork-ref floor: the generated sed's auto-include property means the count only grows — a
# shrunken parse is the B-014 class); 080 owns php/src (the 3 string refs:
# DockerActionManager.php:788, 789, 1111 — the misparse fallback and the 90-day nag's data
# source). Patch 050's vendor-surface rows landed with slice 9: the wizard's office selection
# is ours alone (zero Collabora/OnlyOffice ids across templates and public assets, the
# dictionaries forms gone from the templates, the eurooffice card intact as the positive
# control, the dead vendor svg assets absent). Patch 060's string rows landed with slice 11:
# the operator-visible language is ours (every wizard surface carries the es-CL sweep —
# per-file sentinel pairs, English gone and es-CL present, the JS↔twig toggle words equal)
# and the changelog links point at the fork's own releases, never upstream's. 070's brand
# rows landed with slice 12 (the <title>/h1 swap is the reskin's, not the sweep's — plus the
# asset/token/font floors, the dark-toggle deletion, and the two handoff cards). 030's row
# landed with slice 13: the white-label rename is enforced at BUILD time — scripts/bake.sh
# carries the two served-file asserts the office smoke used to own (FRD S3's "smoke greps
# move to build-time"), and the renamed bytes ship inside the image where no tree grep can
# see them, so the row pins the mechanism to the fork's own script. And slice 23 extends
# this gate with the README/twig string-equality drift gate.
#
# SCOPE (measured against the mirror; grep -rl nextcloud-releases outside containers.json and
# php/src/DockerActionManager.php = 29 files): root docs (readme.md, reverse-proxy.md,
# manual-upgrade.md, develop.md, multiple-instances.md, php/README.md), the helm chart (15
# templates + update-helm.sh), manual-install/latest.yml, root compose.yaml, update-helm.yml,
# the QA harness (php/tests/compose.yaml), containers.twig's changelog link, and the two
# build-time fetches upstream keeps (whiteboard's FROM line; the GPG-verified server tarball
# in the nextcloud Dockerfile, D7) — plus, since slice 13, the fork's OWN build-time fetch:
# the Images workflow's gestion clone, the bake channel (an APS-Conecta source, VENDOR-
# sha256-gated by scripts/bake.sh, and maintainer-side like the other two — it feeds the
# builder, never the clinic's install). The count uses the BARE pattern — three of the 29 carry
# the name without the contiguous ghcr.io/ prefix (two github.com/nextcloud-releases URLs and
# update-helm.yml's registry-API paths), so the gate's own literal grep stays narrower than
# this ledger on purpose. None is install-time shipped surface: docs are slice 23's
# fork-declaration territory, the harness image is slice 18's, containers.twig's changelog
# link was 060's operator-visible territory (repointed to the fork's releases — the row landed
# with slice 11 and measures it), and the build-time fetches
# are the maintainer's build, not the clinic's install. This gate owns what the clinic's
# install actually resolves: containers.json and php/src.
#
# Usage: scripts/brand-gate.sh TREE     (TREE = the replayed tree, e.g. .aps-replay-tree)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
die() { echo "FATAL: $*" >&2; exit 1; }

queued() { compgen -G "$REPO_ROOT/patches/$1-*" >/dev/null; }

fails=0
row() {  # ID DESCRIPTION CMD... — fires iff patch ID is queued; skips print visibly
  local id="$1" desc="$2"; shift 2
  if ! queued "$id"; then
    printf '  skipped: %s not in queue — %s (nothing claims it yet)\n' "$id" "$desc"
    return 0
  fi
  if "$@"; then
    printf '  ok: %s — %s\n' "$id" "$desc"
  else
    printf 'FAIL: %s — %s\n' "$id" "$desc" >&2
    fails=$((fails+1))
  fi
}

upstream_refs() {  # PATH... — zero ghcr.io/nextcloud-releases refs; every hit prints as evidence
  local f hits=0
  for f in "$@"; do
    [ -e "$f" ] || { echo "upstream_refs: no such path: $f" >&2; return 1; }
    grep -rnH "ghcr.io/nextcloud-releases" "$f" && hits=$((hits+1))
  done
  [ "$hits" -eq 0 ]
}

fork_ref_floor() {  # FILE MIN — at least MIN ghcr.io/aps-conecta/ refs (line-counted)
  local n
  n="$(grep -c "ghcr.io/aps-conecta/" "$1")"
  [ "$n" -ge "$2" ] \
    || { echo "  only $n aps-conecta refs in $1 (floor $2) — the sed's prefix rule missed a ref shape, or the list shrank" >&2; return 1; }
}


TREE="${1:?usage: scripts/brand-gate.sh TREE (the replayed tree, e.g. .aps-replay-tree)}"
[ -d "$TREE/php" ] || die "'$TREE' does not look like the replayed tree (no php/ in it)"


row 010 "containers.json carries zero upstream registry refs (the generated sed's post-state)" \
  upstream_refs "$TREE/php/containers.json"

row 010 "containers.json carries at least 19 aps-conecta image refs (the floor — the auto-include property grows it, never shrinks it)" \
  fork_ref_floor "$TREE/php/containers.json" 19

row 080 "php/src carries zero upstream registry refs (the 3 string refs swapped: DockerActionManager.php:788, 789, 1111)" \
  upstream_refs "$TREE/php/src"

office_ids_absent() {  # PATH... — zero office-collabora/office-onlyoffice ids (hits print)
  local f hits=0
  for f in "$@"; do
    [ -e "$f" ] || { echo "office_ids_absent: no such path: $f" >&2; return 1; }
    grep -rnHE 'office-collabora|office-onlyoffice' "$f" && hits=$((hits+1))
  done
  [ "$hits" -eq 0 ]
}

collabora_forms_gone() {  # the dictionaries/additional-options forms are gone from the TEMPLATES (hits print).
  # Templates-scoped on purpose: index.php:135-136 passes collabora_dictionaries/collabora_additional_options
  # into the twig context and STAYS byte-identical (zero-PHP rule) — the deleted section was their only consumer.
  local hits=0
  grep -rnHE 'collabora_dictionaries|collabora_additional_options' "$TREE/php/templates" && hits=1
  [ "$hits" -eq 0 ]
}

office_floor() {  # FILE... — the eurooffice surface present in each (patch 050's positive control)
  local f
  for f in "$@"; do
    grep -q 'office-eurooffice' "$f" || { echo "  no eurooffice ref in $f — patch 050 ate the suite's own card" >&2; return 1; }
  done
}

files_absent() {  # PATH... — none may exist (a deletion post-state; survivors print)
  local f
  for f in "$@"; do
    if [ -e "$f" ]; then echo "  still present: $f" >&2; return 1; fi
  done
}


row 050 "the wizard carries zero Collabora/OnlyOffice vendor ids — cards, JS refs, CSS selectors gone from templates and public assets" \
  office_ids_absent "$TREE/php/templates" "$TREE/php/public"

row 050 "the Collabora dictionaries/additional-options forms are gone from the templates (the PHP context pass-through at index.php:135-136 stays, zero-PHP rule)" \
  collabora_forms_gone

row 050 "the eurooffice card is intact — radio id, CSS selector, JS guard all present (the deletion's positive control)" \
  office_floor "$TREE/php/templates/includes/optional-containers.twig" "$TREE/php/public/style.css" "$TREE/php/public/disable-containers.js"

row 050 "the vendor logo assets are gone — img/collabora.svg, img/onlyoffice.svg (dead bytes post-deletion)" \
  files_absent "$TREE/php/public/img/collabora.svg" "$TREE/php/public/img/onlyoffice.svg"

if [ "$fails" -gt 0 ]; then
  echo "BRAND GATE: *** FAIL *** — $fails row(s) failed" >&2
  exit 1
fi
echo "BRAND GATE: PASS — every queued patch's brand guarantee measured; skipped rows listed above (visible, never silent)"
