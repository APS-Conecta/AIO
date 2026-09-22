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
#   030 — the bake (slice 13): three rows. (1) The bake channel is checksum-gated at build
#         time — scripts/bake.sh re-runs gestion's VENDOR sha256 gate before any tarball
#         enters the image; the tarball BYTES are gestion-side (test.sh:63-70), so this row
#         pins the MECHANISM to the fork. (2) The suite's skeleton posture is baked —
#         NC_skeletondirectory="" ENV beside 020's store-off (the compose stack's own key,
#         compose.yaml: the wizard's admin is created before any phase can write config, and
#         the NC_ channel is read before config.php). (3) The bake's runtime half is wired —
#         the aps-bake COPY lines and the ENV_PREFIX wiring grep present in the replayed
#         Dockerfile; without this row a regenerated 030 that loses them replays green on
#         every other row and ships an unbaked image (the one silently-unbaked-green path
#         nothing else closes). The plan's fourth row — curl in the runtime apk set — was
#         dropped live per FINDINGS P6: /usr/bin/curl 8.22.0 measured PRESENT in the AIO
#         runtime (transitive apk dep; phase 07's AIA fetch already imported the GlobalSign
#         intermediate on the probe), so the premise "the AIO runtime shipped no curl" was
#         falsified and the explicit apk entry would pin a dependency that already ships.
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

row 015 "the eurooffice documentserver base pins the suite's certified pairing (DS 9.3.4 ↔ connector 11.0.5 — R3's set-certified pin; re-cut from the v0.2.0 choreography's main commit so main stays the byte-identical mirror)" \
  grep -q 'documentserver:v9.3.4' "$TREE/Containers/eurooffice/Dockerfile"

selfupdate_optin() {  # the suite's update channel is opt-in: checkbox defaults off, no watchtower POST remains
  local f="$TREE/php/templates/containers.twig"
  # both halves (test.sh:217-263 discipline): the unchecked shape PRESENT, the checked shape ABSENT
  if ! grep -q 'id="automatic_updates" name="automatic_updates">' "$f"; then
    echo "  the automatic_updates checkbox is missing or attribute-shaped differently — patch 040's default-off flip is not in the tree" >&2
    return 1
  fi
  if grep -q 'id="automatic_updates" name="automatic_updates" checked' "$f"; then
    echo "  the automatic_updates checkbox still defaults ON — the nightly chain would arm itself on first save" >&2
    return 1
  fi
  if grep -q 'api/docker/watchtower' "$f"; then
    echo "  a watchtower POST form survived — the manual mastercontainer-update trigger is still reachable from the wizard" >&2
    return 1
  fi
  if ! grep -q 'api/docker/start' "$f"; then
    echo "  the container-start forms vanished — patch 040 ate more than the watchtower arms" >&2
    return 1
  fi
}


row 040 "self-update stays opt-in — the automatic_updates checkbox defaults OFF and the wizard carries zero watchtower POST forms (the nightly chain arms only by deliberate operator choice)" \
  selfupdate_optin

desec_surfaces_gone() {  # zero deSEC refs across wizard templates and public assets (hits print).
  # PHP stays byte-identical (zero-PHP rule): index.php keeps the /desec route and the twig
  # context vars, php/src keeps DesecManager — the scan excludes PHP by construction (templates
  # carry no PHP; the public half is include-scoped to js/css).
  local hits=0
  grep -rniHE 'desec' "$TREE/php/templates" && hits=1
  grep -rniHE --include='*.js' --include='*.css' 'desec' "$TREE/php/public" && hits=1
  [ "$hits" -eq 0 ]
}


row 051 "the deSEC registration channel is gone from the wizard — zero deSEC refs across templates and public assets (the third-party domain-registration flow removed at the only layer the operator sees)" \
  desec_surfaces_gone

row 051 "the own-domain flow is intact — the domain form still present (the deletion's positive control)" \
  grep -q 'id="domain"' "$TREE/php/templates/containers.twig"

bake_checksum_gate() {  # the bake channel re-runs gestion's VENDOR gate before anything unpacks
  # (the mechanism lives on the fork — the BYTES it gates are gestion-side: test.sh:63-70)
  local f="$REPO_ROOT/scripts/bake.sh"
  [ -f "$f" ] || { echo "  scripts/bake.sh is missing on the fork — the bake channel is ungated" >&2; return 1; }
  grep -q 'sha256sum --check --status' "$f" \
    || { echo "  bake.sh no longer runs sha256sum --check against the VENDOR pins — an ungated bake ships whatever the clone carried" >&2; return 1; }
  grep -qF 'expected exactly 1' "$f" \
    || { echo "  bake.sh no longer enforces the one-tarball-per-app guard — a stale second tarball would bake silently" >&2; return 1; }
  grep -qF 'no longer applies' "$f" \
    || { echo "  bake.sh no longer carries the three-outcome abort — a drifted patch would fuzz or fail soft" >&2; return 1; }
}

bake_runtime_wired() {  # the patch's runtime half exists in the replayed tree — the COPY lines that
  # pull the bake's output into the image and the ENV_PREFIX grep that proves the NC_ channel
  # is real in the shipped server. Without this row a regenerated 030 that loses these lines
  # replays green (the three-outcome rule compares the patch to the tree it was cut from) and
  # every other row stays green while the Images build ships an unbaked image.
  local f="$TREE/Containers/nextcloud/Dockerfile"
  [ -f "$f" ] || { echo "  no Dockerfile at '$f'" >&2; return 1; }
  grep -q '^COPY aps-bake/custom_apps/ /usr/src/nextcloud/custom_apps/' "$f" \
    || { echo "  the bake's custom_apps COPY line is missing — the image builds without the app set" >&2; return 1; }
  grep -q '^COPY aps-bake/themes/apsconecta/ /usr/src/nextcloud/themes/apsconecta' "$f" \
    || { echo "  the bake's theme COPY line is missing — the image builds without the apsconecta theme" >&2; return 1; }
  grep -q 'ENV_PREFIX' "$f" \
    || { echo "  the ENV_PREFIX wiring grep is missing — a server bump that renames the NC_ harvest would silently re-enable the store" >&2; return 1; }
}

row 030 "the bake channel is checksum-gated at build time — scripts/bake.sh re-runs gestion's VENDOR sha256 gate (sha256sum --check against each tarball's VENDOR pin) before any byte enters the image; the tarball bytes themselves are gestion-side (test.sh:63-70), so this row pins the mechanism to the fork" \
  bake_checksum_gate

row 030 "the suite's skeleton posture is baked — NC_skeletondirectory="" ENV beside 020's store-off (the wizard's admin is created at install time, before any phase can write config; the NC_ channel is read before config.php)" \
  grep -q 'NC_skeletondirectory=""' "$TREE/Containers/nextcloud/Dockerfile"

row 030 "the bake's runtime half is wired — both aps-bake COPY lines and the ENV_PREFIX wiring grep present in the Dockerfile (a regeneration that drops them would otherwise replay green on every other row and ship an unbaked image — the one silently-unbaked-green path nothing else closes)" \
  bake_runtime_wired

if [ "$fails" -gt 0 ]; then
  echo "ACQUISITION GATE: *** FAIL *** — $fails check(s) failed" >&2
  exit 1
fi
echo "ACQUISITION GATE: PASS — install-time channels stay APS-Conecta-only; skipped rows listed above (visible, never silent)"
