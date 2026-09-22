#!/usr/bin/env bash
# S4's acquisition gate — the installer never reaches a non-APS-Conecta source at install time
# (the steer's channel-completeness principle). Two check classes:
#
# UNCONDITIONAL — true of upstream's own tree; our patches must never break them, and an
# upstream change that does is the drift signal, loudly:
#   - zero `git clone` across the runtime surfaces (every *.sh under Containers/ and php/ —
#     the scripts the shipped containers execute). Measured: upstream ships none. The one git
#     clone upstream does ship is talk-recording's Dockerfile — BUILD-time, in a sibling we
#     retag and never build; the *.sh scoping excludes it by construction. gestion's
#     ensure_own_app clone channel is dev-only and superseded by the bake (research-verified)
#     — that half lives in gestion, not in this repo.
#   - the entrypoint still honors the skip.update marker (honored at :185, deleted at :1154
#     today): the migration channel (slice 22) sets it, and with the store off it is
#     load-bearing for migrated clinics.
#
# ROWS — the same contract as brand-gate.sh: a row fires only when its patch is queued.
#   020 — the store-off bake: NC_appstoreenabled="0" ENV in the nextcloud Dockerfile. With the
#         store on, occ upgrade re-downloads every enabled app and no VENDOR pin can hold
#         (gestion #163); the bake + this ENV make the entrypoint's store legs fail-fast.
#   040 — self-update opt-in (slice 9): the automatic_updates checkbox defaults OFF and the
#         wizard carries zero watchtower POST forms. The update channel stays deliberate —
#         D12's one-distribution rule makes even an opted-in nightly watchtower run a no-op
#         (a published tag's digests never move) until the operator runs a new tag on purpose.
#   051 — deSEC removal (slice 10, the v0.2.0 spec): zero deSEC surfaces across templates and
#         public assets; the own-domain form stays as the positive control. The PHP routes
#         (index.php's /desec + /api/desec/register, DesecManager) stay as unreachable dead
#         code per the zero-PHP rule — unreachable because the markup that reached them is
#         what this patch deletes.
#   030 — the bake (slice 13): four rows. (1) The bake channel is checksum-gated at build
#         time — scripts/bake.sh re-runs gestion's VENDOR sha256 gate before any tarball
#         enters the image; the tarball BYTES are gestion-side (test.sh:63-70), so this row
#         pins the MECHANISM to the fork. (2) The suite's skeleton posture is baked —
#         NC_skeletondirectory="" ENV beside 020's store-off (the compose stack's own key,
#         compose.yaml: the wizard's admin is created before any phase can write config, and
#         the NC_ channel is read before config.php). (3) Phase 07's AIA fetch has its
#         runtime dependency — curl joins the runtime apk set (slice 4's routing: the AIO
#         runtime shipped no curl and the cert-chain fetch degraded to its skip-warning path
#         on every clinic). (4) The bake's runtime half is wired — the aps-bake COPY lines
#         and the ENV_PREFIX wiring grep present in the replayed Dockerfile; without this
#         row a regenerated 030 that loses them replays green on every other row and ships
#         an unbaked image (the one silently-unbaked-green path nothing else closes).
#
# ROUTED (this repo cannot see these channels — recorded so the ledger stays complete, the
# slice-4 curl→030 precedent): VENDOR sha256s are gestion-side (test.sh:63-70 already gates
# them); the host-bundle sha256 is the gestion Release page (slice 19); data-package
# checksums are slice 21. Every channel the AIO tree CAN see is checked here or in
# brand-gate.sh.
#
# Usage: scripts/acquisition-gate.sh TREE     (TREE = the replayed tree, e.g. .aps-replay-tree)
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

clone_free() {  # zero git clone in the runtime *.sh surfaces (hits print as evidence)
  local hits=0
  grep -rn --include="*.sh" "git clone" "$TREE/Containers" "$TREE/php" && hits=1
  [ "$hits" -eq 0 ]
}


TREE="${1:?usage: scripts/acquisition-gate.sh TREE (the replayed tree, e.g. .aps-replay-tree)}"
[ -d "$TREE/php" ] || die "'$TREE' does not look like the replayed tree (no php/ in it)"


if clone_free; then
  printf '  ok: zero git clone across runtime surfaces — install-time channels stay APS-Conecta-only\n'
else
  echo "FAIL: a runtime script git-clones — the installer's channels are APS-Conecta-only (see the hits above)" >&2
  fails=$((fails+1))
fi
if grep -q "skip.update" "$TREE/Containers/nextcloud/entrypoint.sh"; then
  printf '  ok: the entrypoint still honors skip.update — the migration channel (slice 22) depends on it\n'
else
  echo "FAIL: the entrypoint no longer honors skip.update — the migration channel (slice 22) depends on it; adopt upstream's rename in the migration tool first" >&2
  fails=$((fails+1))
fi


row 020 "the app store is baked off — NC_appstoreenabled=\"0\" ENV in Containers/nextcloud/Dockerfile" \
  grep -q 'NC_appstoreenabled="0"' "$TREE/Containers/nextcloud/Dockerfile"

if [ "$fails" -gt 0 ]; then
  echo "ACQUISITION GATE: *** FAIL *** — $fails check(s) failed" >&2
  exit 1
fi
echo "ACQUISITION GATE: PASS — install-time channels stay APS-Conecta-only; skipped rows listed above (visible, never silent)"
