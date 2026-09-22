#!/usr/bin/env bash
# S1's registry mechanics — the 20-image lockstep under ghcr.io/aps-conecta/*, everything the Images
# workflow (.github/workflows/images.yml) rides: the sibling list, the registry-side retag walk, the
# tag-completeness matrix, the digest manifest, and the generated sed that patch 010 reuses.
#
# WHY 20 IMAGES MUST MOVE TOGETHER. The wizard resolves every sibling's tag from the mastercontainer's
# OWN running image tag: %AIO_CHANNEL% becomes the channel (php/src/Docker/DockerActionManager.php,
# BuildImageName), which explodes the running image on ':' and takes field 2. The tag the operator
# runs IS the channel every sibling resolves by — one tag, twenty images, and a missing one is not
# "one feature down": the wizard's registry-reachability checks (isRegistryReachable) fail the start.
# That is why the matrix gates the announce, and why a tag is NEVER a raw digest: `image@sha256:...`
# explodes into a bogus channel and every sibling resolves a tag that cannot exist.
#
# WHAT MOVES AND WHAT BUILDS. 18 of the 20 are registry-side retags — `buildx imagetools create`
# copies the manifest list at the registry itself (seconds, zero runner disk, the multi-arch entries
# carried along byte-for-byte); aio-nextcloud (the apps+theme bake, patch 030) and all-in-one (the
# reskin, patch 070) are real builds the workflow's build jobs own. At S1's landing both build from
# the mirror as-is — the patched content arrives when the replay chain (S4) passes build-ref aps/main.
#
# THE SEAM 010 SHARES. Patch 010 (containers.json's org swap) is GENERATED, never hand-edited: the
# same org constants below, the same prefix rule, so upstream's next container auto-includes here
# (the sibling list is PARSED from php/containers.json, not hardcoded) and in 010's sed alike.
#
# Registry-call discipline is gestion's image-digests.sh doctrine, verbatim: THE INDEX DIGEST
# (`imagetools inspect --format {{.Manifest.Digest}}` — pinning one platform's manifest would make
# the stack unresolvable on any other), every call bounded (B-015 — a registry call that hangs is
# not a gate), one retry before failing, and the registry's own stderr kept and quoted on the way
# out (B-003: a rate limit and a deleted tag must never print the same sentence).
#
# This file is fork-infra on main (the mirror-parity allowlist — see images.yml's header): upstream
# ships no scripts/ dir, so the path itself cannot collide, and S4's parity assert excludes exactly
# these allowlisted fork-only paths while diffing everything else against upstream byte-for-byte.
#
# Usage:
#   scripts/retag.sh list                         the sibling image names, one per line (parsed, in order)
#   scripts/retag.sh sed FILE                     apply the org swap in place + verify (patch 010's generator)
#   scripts/retag.sh retag TAG [--channel CH] [--force]      the 18-image registry-side walk
#   scripts/retag.sh matrix TAG [--channel CH]    the gate: all present + the retagged match ONE snapshot
#   scripts/retag.sh manifest TAG                 the publish record, JSON on stdout
#
# Env: RETAG_CONTAINERS (default this repo's php/containers.json), RETAG_CHANNEL (default latest)
# when --channel is not given, RETAG_BUILT_REF + RETAG_BUILT_SHA (the manifest's provenance, set by
# the workflow).
set -uo pipefail

ORG_UPSTREAM="nextcloud-releases"  # the upstream namespace the retag copies FROM
ORG_FORK="aps-conecta"            # ours — 010's sed and this whole walk swap to exactly this
GHCR="ghcr.io"
BUILD_IMAGE="aio-nextcloud"        # the one sibling that is BUILT, not retagged (the bake; patch 030)
MASTER_IMAGE="all-in-one"         # the mastercontainer — not in containers.json; the operator's docker run names it
DEFAULT_CHANNEL="latest"
MIN_SIBLINGS="19"                 # shape-rot alarm (divergence's "expected 27+" precedent): a parse that
                                   # silently shrank would green a walk over fewer images than the suite has

die() { echo "FATAL: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }
usage() {
  cat >&2 <<'EOF'
usage: scripts/retag.sh <command> [args]
  list                                  the sibling image names parsed from php/containers.json
  sed FILE                              apply the org swap in place + verify (patch 010's generator)
  retag TAG [--channel CH] [--force]    the registry-side walk (every sibling except the baked one)
  matrix TAG [--channel CH]             the gate: all images present + the retagged match one snapshot
  manifest TAG                          the publish record, JSON on stdout
EOF
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINERS="${RETAG_CONTAINERS:-$REPO_ROOT/php/containers.json}"

# Registry stderr lands here so a failure can quote it. Removed on any exit, which is why it is a
# trap and not an rm at the end (image-digests.sh's own pattern).
ERRF="$(mktemp)"; trap 'rm -f "$ERRF"' EXIT

list() { # print the sibling image names — the basename of each image ref, containers.json order
  [ -f "$CONTAINERS" ] || { echo "FATAL: no containers.json at $CONTAINERS" >&2; return 1; }
  python3 - "$CONTAINERS" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        services = json.load(fh)["aio_services_v1"]
except Exception as exc:
    sys.exit(f"cannot parse {sys.argv[1]}: {exc}")
for entry in services:
    image = entry.get("image", "")
    if not image:
        sys.exit(f"an aio_services_v1 entry has no image field — schema surprise; inspect {sys.argv[1]}")
    print(image.rsplit("/", 1)[-1])
PY
}

SIBS=()
siblings_load() { # fill SIBS once per run, floor-guarded — a shrunken parse must never green a walk (B-014)
  [ "${#SIBS[@]}" -gt 0 ] && return 0
  mapfile -t SIBS < <(list)
  [ "${#SIBS[@]}" -ge "$MIN_SIBLINGS" ] \
    || die "only ${#SIBS[@]} siblings parsed from $CONTAINERS — expected at least $MIN_SIBLINGS; a green walk over a shrunken set would be green without looking"
}

tag_valid() { # TAG — a channel-valid Docker tag. ':' and '@' are excluded BY the charset itself; the
  #              moving channel names are refused on purpose: the suite tag IS the gestion release tag
  #              (D12), and a fork-side 'latest' would let the update nag chase our own :latest and
  #              silently diverge from the release the clinic pinned.
  local t="$1"
  case "$t" in
    latest|latest-arm64|latest-aio) return 1 ;;
  esac
  [[ "$t" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || return 1
  return 0
}

digest() { # REF — print the index digest; non-zero (with the registry's own words on stderr) if
  #          unresolvable. One retry, 3s apart — the observed failure class is transient throttling,
  #          not drift (image-digests.sh, 2026-08-05). Bounded on every attempt (B-015).
  local out
  out="$(timeout 120 docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>"$ERRF")"
  case "$out" in
    sha256:*) printf '%s\n' "$out"; return 0 ;;
  esac
  sleep 3
  out="$(timeout 120 docker buildx imagetools inspect "$1" --format '{{.Manifest.Digest}}' 2>"$ERRF")"
  case "$out" in
    sha256:*) printf '%s\n' "$out"; return 0 ;;
  esac
  sed 's/^/       registry said: /' "$ERRF" >&2
  return 1
}

retag_one() { # FORK_REF UPSTREAM_REF — the registry-side copy, bounded (B-015)
  timeout 300 docker buildx imagetools create -t "$1" "$2" 2>"$ERRF" \
    || { sed 's/^/       registry said: /' "$ERRF" >&2; return 1; }
}

cmd_list() { list || die "cannot list the siblings"; }

cmd_sed() { # FILE — apply the org swap in place and verify. THE GENERATOR patch 010 replays (S4's
  #           queue): never hand-edit containers.json — upstream's next container must auto-include,
  #           which only a generated rule gives. Idempotent by construction: a second run is a no-op,
  #          which is 010's own "already applied" outcome under the three-outcome rule.
  [ $# -ge 1 ] || { usage; die "sed needs FILE"; }
  local f="$1"
  [ -f "$f" ] || die "no such file: $f"
  sed -i "s|$GHCR/$ORG_UPSTREAM/|$GHCR/$ORG_FORK/|g" "$f"
  # The verify is the gate, not a courtesy: a bare-form upstream ref (no trailing slash) survives the
  # sed — die loudly so the GENERATOR gets fixed, never the file (the one-rule doctrine).
  if grep -q "$GHCR/$ORG_UPSTREAM" "$f"; then
    die "$f still names $GHCR/$ORG_UPSTREAM — the sed's prefix rule missed a ref shape; fix the generator, never the file"
  fi
  siblings_load
  local n
  n="$(grep -c "$GHCR/$ORG_FORK/" "$f")"
  [ "$n" -eq "${#SIBS[@]}" ] \
    || die "$f carries ${n} $ORG_FORK refs but containers.json names ${#SIBS[@]} images — the file and the list disagree"
  say "sed applied and verified: ${n} image refs now $GHCR/$ORG_FORK/; upstream refs: 0; %AIO_CHANNEL% untouched"
}

cmd_retag() { # TAG [--channel CH] [--force] — the lockstep walk
  [ $# -ge 1 ] || { usage; die "retag needs TAG"; }
  local tag="$1"; shift
  local channel="$DEFAULT_CHANNEL" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --channel) [ $# -ge 2 ] || die "--channel needs a value"; channel="$2"; shift 2 ;;
      --force)   force=1; shift ;;
      *)         die "unknown argument to retag: $1" ;;
    esac
  done
  tag_valid "$tag" \
    || die "suite tag '$tag' is not a channel-valid tag — charset [A-Za-z0-9._-] (':' and '@' excluded BY construction: the wizard resolves the channel by exploding the running image on ':', and a digest-style ref parses as a bogus channel); 'latest*' names are reserved because the suite tag IS the gestion release tag (D12)"
  siblings_load
  local total=$(( ${#SIBS[@]} + 1 ))
  # Immutability pre-check, the published-tag rule made mechanical: a FULLY present set means a prior
  # run announced this tag, and a published tag's digests never move. A PARTIAL set is a failed or
  # interrupted run — completing it is what a retry is for (the matrix below is the arbiter of whether
  # the completed set is coherent). --force is the deliberate re-publish: repairing a set that failed
  # verification, or refreshing a throwaway CI tag. Never a green, published release tag.
  local existing=0 img
  for img in "${SIBS[@]}" "$MASTER_IMAGE"; do
    if digest "$GHCR/$ORG_FORK/$img:$tag" >/dev/null 2>&1; then existing=$((existing+1)); fi
  done
  if [ "$existing" -eq "$total" ] && [ "$force" = 0 ]; then
    die "tag '${tag}' is already fully published (${existing}/${total}) — a published tag's digests never move. If the previous run FAILED verification (a mixed set), or this is a throwaway CI tag, re-run with --force to rebuild the set from one snapshot."
  fi
  [ "$existing" = 0 ] || say "note: ${existing}/${total} images already carry '${tag}' — completing the set"
  local n=0
  for img in "${SIBS[@]}"; do
    if [ "$img" = "$BUILD_IMAGE" ]; then
      say "  skip $img — built by the workflow's build job (the bake, patch 030's slot), never retagged"
      continue
    fi
    retag_one "$GHCR/$ORG_FORK/$img:$tag" "$GHCR/$ORG_UPSTREAM/$img:$channel" \
      || die "retag failed: $GHCR/$ORG_UPSTREAM/$img:$channel -> $GHCR/$ORG_FORK/$img:$tag"
    say "  retagged $img"
    n=$((n+1))
  done
  say "retag walk done: ${n} images now carry :${tag} (built separately: $BUILD_IMAGE, $MASTER_IMAGE)"
}

cmd_matrix() { # TAG [--channel CH] — THE GATE. Existence is only half of it: a suite tag assembled
  #              across an upstream release would mix two upstream snapshots inside one tag — every
  #              retagged image must still equal upstream :<channel> NOW, so a mid-walk upstream
  #              release reds the matrix and forces one clean re-run of the whole pipeline.
  [ $# -ge 1 ] || { usage; die "matrix needs TAG"; }
  local tag="$1"; shift
  local channel="$DEFAULT_CHANNEL"
  while [ $# -gt 0 ]; do
    case "$1" in
      --channel) [ $# -ge 2 ] || die "--channel needs a value"; channel="$2"; shift 2 ;;
      *)         die "unknown argument to matrix: $1" ;;
    esac
  done
  tag_valid "$tag" || die "suite tag '$tag' is not a channel-valid tag (see retag's message)"
  siblings_load
  local total=$(( ${#SIBS[@]} + 1 ))
  local missing=0 mixed=0 unprovable=0 present=0 img d u
  echo "== matrix: ${total} images must resolve under $GHCR/$ORG_FORK/:${tag} =="
  for img in "${SIBS[@]}" "$MASTER_IMAGE"; do
    if ! d="$(digest "$GHCR/$ORG_FORK/$img:$tag")"; then
      printf '  %-26s MISSING\n' "$img"
      missing=$((missing+1))
      continue
    fi
    present=$((present+1))
    printf '  %-26s %s\n' "$img" "$d"
    case "$img" in
      "$BUILD_IMAGE"|"$MASTER_IMAGE") continue ;;  # built images have no upstream counterpart to match
    esac
    if ! u="$(digest "$GHCR/$ORG_UPSTREAM/$img:$channel")"; then
      printf '  %-26s cannot prove the snapshot: upstream :%s unresolvable\n' "$img" "$channel"
      unprovable=$((unprovable+1))
      continue
    fi
    if [ "$d" != "$u" ]; then
      printf '  %-26s MIXED: %s != upstream :%s (%s)\n' "$img" "$d" "$channel" "$u"
      mixed=$((mixed+1))
    fi
  done
  echo
  if [ "$missing" -gt 0 ] || [ "$mixed" -gt 0 ] || [ "$unprovable" -gt 0 ]; then
    echo "MATRIX: *** FAIL *** — of ${total}: ${missing} missing, ${mixed} mixed, ${unprovable} unprovable" >&2
    echo "  missing     = the wizard's start would fail on this tag (registry-reachability checks)" >&2
    echo "  mixed       = the suite tag spans more than one upstream :${channel} snapshot — re-run the whole pipeline (--force)" >&2
    echo "  unprovable  = upstream could not be read; a matrix that cannot look is not a matrix" >&2
    exit 1
  fi
  local retagged=$(( ${#SIBS[@]} - 1 ))
  echo "MATRIX: PASS — ${present}/${total} images present; the ${retagged} retagged match upstream :${channel} (one snapshot); built: $BUILD_IMAGE + $MASTER_IMAGE from build-ref"
  exit 0
}

cmd_manifest() { # TAG — the publish record: every image's index digest, JSON on stdout. The registry
  #                is the hand-off (gestion's release-manifest.sh --emit resolves its own copy at tag
  #                time, v0.2.0); this record is the LEDGER of what the walk produced — same tool,
  #                same digest format, so the two are diffable against each other.
  [ $# -ge 1 ] || { usage; die "manifest needs TAG"; }
  local tag="$1"
  tag_valid "$tag" || die "suite tag '$tag' is not a channel-valid tag (see retag's message)"
  siblings_load
  RETAG_MANIFEST_TAG="$tag" \
  RETAG_MANIFEST_CHANNEL="${RETAG_CHANNEL:-$DEFAULT_CHANNEL}" \
  RETAG_MANIFEST_PREFIX="$GHCR/$ORG_FORK" \
  RETAG_MANIFEST_IMAGES="$(printf '%s\n' "${SIBS[@]}" "$MASTER_IMAGE")" \
  RETAG_MANIFEST_REF="${RETAG_BUILT_REF:-}" \
  RETAG_MANIFEST_SHA="${RETAG_BUILT_SHA:-}" \
  python3 - <<'PY'
import json, os, subprocess, sys

def digest(ref):
    # THE INDEX DIGEST — the exact tool and format gestion's release-manifest.sh --emit resolves
    # with at tag time (v0.2.0). Bounded (B-015); unreachable is FATAL, never silently omitted:
    # a record that cannot name a digest is a record of nothing.
    out = subprocess.run(["docker", "buildx", "imagetools", "inspect", "--format",
                           "{{.Manifest.Digest}}", ref], capture_output=True, text=True, timeout=120)
    if out.returncode == 0 and out.stdout.strip().startswith("sha256:"):
        return out.stdout.strip()
    sys.exit(f"FATAL: {ref} did not resolve — the manifest cannot record what the registry cannot see: {out.stderr.strip()}")

env = os.environ
manifest = {
    "suite_tag": env["RETAG_MANIFEST_TAG"],
    "upstream_channel": env["RETAG_MANIFEST_CHANNEL"],
    "images": {},
}
for name in env["RETAG_MANIFEST_IMAGES"].splitlines():
    if name:
        manifest["images"][name] = digest(f'{env["RETAG_MANIFEST_PREFIX"]}/{name}:{env["RETAG_MANIFEST_TAG"]}')
if env.get("RETAG_MANIFEST_REF") and env.get("RETAG_MANIFEST_SHA"):
    manifest["built_from"] = {"ref": env["RETAG_MANIFEST_REF"], "sha": env["RETAG_MANIFEST_SHA"]}
json.dump(manifest, sys.stdout, indent=2, sort_keys=True)
print()
PY
}

case "${1:-}" in
  list)     shift; cmd_list "$@" ;;
  sed)      shift; cmd_sed "$@" ;;
  retag)    shift; cmd_retag "$@" ;;
  matrix)   shift; cmd_matrix "$@" ;;
  manifest) shift; cmd_manifest "$@" ;;
  *)        usage; exit 1 ;;
esac
