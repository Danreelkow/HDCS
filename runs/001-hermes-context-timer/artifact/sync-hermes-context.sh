#!/usr/bin/env bash
# sync-hermes-context.sh — one-way (A2) host->workspace mirror of the hermes context.
# rsync primary, cp fallback; stage -> verify -> touch DST (A11/A13); refusals cite A-numbers only (A19).
set -euo pipefail

die() { printf '%s\n' "$1" >&2; exit 1; }

MODE="sync"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry" ;;
    --verify) MODE="verify" ;;
    *) die "usage: sync-hermes-context.sh [--dry-run|--verify]" ;;
  esac
done

# --- A23: unset -> mandated production defaults; set-but-empty -> refuse ---
if [ -z "${HERMES_CONTEXT_SRC+x}" ]; then
  SRC="/opt/data/workspace/hermes-context"
elif [ -z "${HERMES_CONTEXT_SRC}" ]; then
  die "A23: HERMES_CONTEXT_SRC is set but empty"
else
  SRC="${HERMES_CONTEXT_SRC}"
fi
if [ -z "${HERMES_CONTEXT_DST+x}" ]; then
  DST="/workspace/hermes-context"
elif [ -z "${HERMES_CONTEXT_DST}" ]; then
  die "A23: HERMES_CONTEXT_DST is set but empty"
else
  DST="${HERMES_CONTEXT_DST}"
fi

# canonicalize trailing slashes once; all later mutations use canonical paths
while [ "${SRC%/}" != "${SRC}" ]; do SRC="${SRC%/}"; done
while [ "${DST%/}" != "${DST}" ]; do DST="${DST%/}"; done

# --- A18: degenerate paths (component test) ---
if [ -z "${SRC}" ] || [ "${SRC}" = "." ] || [ "${SRC}" = "/" ]; then
  die "A18: degenerate HERMES_CONTEXT_SRC='${SRC}'"
fi
if [ -z "${DST}" ] || [ "${DST}" = "." ] || [ "${DST}" = "/" ]; then
  die "A18: degenerate HERMES_CONTEXT_DST='${DST}'"
fi

# inside(root, candidate): 0 if candidate == root or candidate under root (component boundary)
is_within() {
  if [ "$2" = "$1" ]; then return 0; fi
  case "$2" in "$1"/*) return 0 ;; esac
  return 1
}

RS="$(realpath -m -- "${SRC}")"
RD="$(realpath -m -- "${DST}")"

# --- A12: identity / ancestor / descendant, realpath-based ---
if [ "${RS}" = "${RD}" ]; then
  die "A12: SRC and DST resolve to the same path (${RS})"
fi
if is_within "${RD}" "${RS}"; then
  die "A12: DST is an ancestor of SRC (${RD} contains ${RS})"
fi
if is_within "${RS}" "${RD}"; then
  die "A12: DST resolves inside SRC (${RD} under ${RS})"
fi

# --- A22: DST itself is a symlink -> refuse, never replace ---
if [ -L "${DST}" ]; then
  die "A22: DST is a symlink (${DST} -> $(readlink -- "${DST}" 2>/dev/null || echo '?')); refusing to replace a user-placed symlink"
fi

# --- log target + owned concrete paths (A8/A14/A15) ---
if [ -z "${HERMES_CTX_LOG+x}" ]; then
  LOGF="${HOME}/.cache/hermes-context/sync.log"
elif [ -z "${HERMES_CTX_LOG}" ]; then
  die "A23: HERMES_CTX_LOG is set but empty"
else
  LOGF="${HERMES_CTX_LOG}"
fi
LOG_DIR_OWNED=""
if [ -z "${LOG_DIR+x}" ]; then
  :
elif [ -z "${LOG_DIR}" ]; then
  die "A23: LOG_DIR is set but empty"
else
  LOGF="${LOG_DIR}/sync.log"
  LOG_DIR_OWNED="${LOG_DIR}"
fi

ENTRYPOINT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

declare -a OWNED=()
OWNED+=("$(realpath -m -- "$(dirname -- "${LOGF}")")")
OWNED+=("${ENTRYPOINT_DIR}")
if [ -n "${LOG_DIR_OWNED}" ]; then
  OWNED+=("$(realpath -m -- "${LOG_DIR_OWNED}")")
  OWNED+=("$(realpath -m -- "$(dirname -- "${LOG_DIR_OWNED}")")")
fi

# --- A14/A15: DST must not overlap any owned concrete path (component-boundary) ---
for o in "${OWNED[@]}"; do
  if is_within "${o}" "${RD}" || is_within "${RD}" "${o}"; then
    die "A14/A15: DST (${RD}) overlaps owned path (${o})"
  fi
done
LOGF_REAL="$(realpath -m -- "${LOGF}")"
if is_within "${RD}" "${LOGF_REAL}"; then
  die "A14/A15: log file (${LOGF_REAL}) is inside DST"
fi

# --- A9-class compare: contents + recursive structure + symlinks (lstat-based, never dereferences) ---
trees_equal() {
  local s="$1" d="$2" out p rel dd
  if command -v rsync >/dev/null 2>&1; then
    out="$(rsync -rlcn --itemize-changes --delete -- "${s}/" "${d}/")" || return 1
    if [ -n "${out}" ]; then return 1; fi
  fi
  while IFS= read -r -d '' p; do
    rel="${p#"$s"}"
    dd="${d}${rel}"
    if [ -L "$p" ]; then
      if [ ! -L "$dd" ]; then return 1; fi
      if [ "$(readlink -- "$p")" != "$(readlink -- "$dd")" ]; then return 1; fi
    elif [ -d "$p" ]; then
      if [ -d "$dd" ] && [ ! -L "$dd" ]; then :; else return 1; fi
    elif [ -f "$p" ]; then
      if [ ! -f "$dd" ] || [ -L "$dd" ]; then return 1; fi
      cmp -s -- "$p" "$dd" || return 1
    else
      if [ ! -e "$dd" ] && [ ! -L "$dd" ]; then return 1; fi
    fi
  done < <(find "$s" -mindepth 0 -print0)
  while IFS= read -r -d '' p; do
    rel="${p#"$d"}"
    if [ ! -e "${s}${rel}" ] && [ ! -L "${s}${rel}" ]; then return 1; fi
  done < <(find "$d" -mindepth 1 -print0 2>/dev/null)
  return 0
}

# --- cp fallback mirror: recursive reconcile (delete stale, copy missing/differing, never follow DST symlinks) ---
mirror_fallback() {
  local s="$1" d="$2" p rel dd
  while IFS= read -r -d '' p; do
    rel="${p#"$d"}"
    if [ ! -e "${s}${rel}" ] && [ ! -L "${s}${rel}" ]; then
      rm -rf -- "$p"
    fi
  done < <(find "$d" -mindepth 1 -print0 2>/dev/null)
  while IFS= read -r -d '' p; do
    rel="${p#"$s"}"
    dd="${d}${rel}"
    if [ -L "$p" ]; then
      rm -rf -- "$dd"
      ln -s -- "$(readlink -- "$p")" "$dd"
    elif [ -d "$p" ]; then
      if [ -d "$dd" ] && [ ! -L "$dd" ]; then :; else rm -rf -- "$dd"; mkdir -p -- "$dd"; fi
      mirror_fallback "$p" "$dd"
    elif [ -f "$p" ]; then
      if [ -f "$dd" ] && [ ! -L "$dd" ] && cmp -s -- "$p" "$dd"; then :; else rm -rf -- "$dd"; cp -p -- "$p" "$dd"; fi
    else
      rm -rf -- "$dd"
      cp -a -- "$p" "$dd" 2>/dev/null || true
    fi
  done < <(find "$s" -mindepth 1 -print0)
}

# --- verify mode: read-only; fails when DST absent or not an exact A9 mirror ---
if [ "${MODE}" = "verify" ]; then
  if [ ! -d "${DST}" ]; then
    die "verify: DST does not exist (${DST})"
  fi
  trees_equal "${SRC}" "${DST}" || die "verify: DST is not an exact A9 mirror of SRC"
  exit 0
fi

# --- dry-run: zero writes of any kind, no stage, absent DST stays absent (A6/A16) ---
if [ "${MODE}" = "dry" ]; then
  S=0; D=0
  if command -v rsync >/dev/null 2>&1; then
    out="$(rsync -an --delete --itemize-changes -- "${SRC}/" "${DST}/")" || die "dry-run: rsync planning failed"
    read -r S D < <(printf '%s\n' "${out}" | awk '$1 ~ /^\*deleting/ {d++; next} $1 ~ /^\./ {next} NF {s++} END{print s+0, d+0}')
  else
    while IFS= read -r -d '' p; do
      rel="${p#"$SRC"}"; dd="${DST}${rel}"
      if [ -L "$p" ]; then
        if [ ! -L "$dd" ] || [ "$(readlink -- "$p")" != "$(readlink -- "$dd")" ]; then S=$((S+1)); fi
      elif [ -d "$p" ]; then
        if [ ! -d "$dd" ] || [ -L "$dd" ]; then S=$((S+1)); fi
      elif [ -f "$p" ]; then
        if [ ! -f "$dd" ] || [ -L "$dd" ] || ! cmp -s -- "$p" "$dd"; then S=$((S+1)); fi
      fi
    done < <(find "$SRC" -mindepth 1 -print0)
    while IFS= read -r -d '' p; do
      rel="${p#"$DST"}"
      if [ ! -e "${SRC}${rel}" ] && [ ! -L "${SRC}${rel}" ]; then D=$((D+1)); fi
    done < <(find "$DST" -mindepth 1 -print0 2>/dev/null)
  fi
  printf 'dry-run: sync=%s delete=%s\n' "${S}" "${D}"
  exit 0
fi

# --- A20: validate the stage PARENT as a string BEFORE mktemp; nothing descends into protected paths ---
CAND="${TMPDIR:-/tmp}"
while [ "${CAND%/}" != "${CAND}" ]; do CAND="${CAND%/}"; done
if [ -z "${CAND}" ]; then CAND="/"; fi
CR="$(realpath -m -- "${CAND}")"
if is_within "${RD}" "${CR}"; then
  die "A14/A15: stage parent (${CR}) is inside DST — refusing before any write"
fi
if is_within "${RS}" "${CR}"; then
  die "A14/A15: stage parent (${CR}) is inside SRC"
fi
for o in "${OWNED[@]}"; do
  if is_within "${o}" "${CR}"; then
    die "A14/A15: stage parent (${CR}) is inside owned path (${o})"
  fi
done

STAGE="$(mktemp -d -- "${CR}/hermes-context-stage.XXXXXX")" || die "stage creation failed under ${CR}"
SREAL="$(realpath -- "${STAGE}")"
if is_within "${RD}" "${SREAL}" || is_within "${RS}" "${SREAL}"; then
  rm -rf -- "${STAGE}"
  die "A14/A15: instantiated stage resolves inside a protected path"
fi
for o in "${OWNED[@]}"; do
  if is_within "${o}" "${SREAL}"; then
    rm -rf -- "${STAGE}"
    die "A14/A15: instantiated stage inside owned path (${o})"
  fi
done

# --- fill the stage (A11: stage before touching DST; no rm -rf of DST before verification) ---
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "${SRC}/" "${STAGE}/" || mirror_fallback "${SRC}" "${STAGE}"
else
  mirror_fallback "${SRC}" "${STAGE}"
fi

# --- A13: A9-class verify stage vs SRC; on mismatch DST is untouched ---
if ! trees_equal "${SRC}" "${STAGE}"; then
  rm -rf -- "${STAGE}"
  die "A13: staged copy failed A9 verification; DST left untouched"
fi

# --- touch DST: exact recursive mirror ---
if [ ! -d "${DST}" ]; then mkdir -p -- "${DST}"; fi
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete -- "${STAGE}/" "${DST}/" || mirror_fallback "${STAGE}" "${DST}"
else
  mirror_fallback "${STAGE}" "${DST}"
fi

# --- final A9 verification: mismatch -> exit nonzero, never warn-and-exit-0 ---
if ! trees_equal "${SRC}" "${DST}"; then
  rm -rf -- "${STAGE}"
  die "A5/A9: post-sync verification failed; DST is not a mirror of SRC"
fi

# --- one-line UTC log (real runs only; parent outside DST per A8) ---
mkdir -p -- "$(dirname -- "${LOGF}")" 2>/dev/null || true
printf '%s sync ok src=%s dst=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SRC}" "${DST}" >> "${LOGF}" 2>/dev/null || true

rm -rf -- "${STAGE}"
exit 0

