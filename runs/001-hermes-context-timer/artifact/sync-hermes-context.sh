#!/usr/bin/env bash
# sync-hermes-context.sh — host->workspace one-way mirror of HERMES context.
# Standalone (no systemd dependency). Laws: A1–A21 of hcdl register.
set -u

# ---- 1a. flags + env resolution (A17) ---------------------------------------
DRYRUN=0
VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    --verify)  VERIFY=1 ;;
    *) echo "refused: A1: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

SRC="${HERMES_CONTEXT_SRC:-/opt/data/workspace/hermes-context/}"
DST="${HERMES_CONTEXT_DST:-/workspace/hermes-context/}"

# canonicalize trailing slashes ONCE; all mutation via canonical paths (ledger 7)
SRC="${SRC%/}"
DST="${DST%/}"

refuse() { echo "refused: $1: $2" >&2; exit 1; }

# ---- 1b. guards BEFORE any write (zero writes on refusal) -------------------
# A18 degenerate paths: component tests, never slash-suffix strings
case "$SRC" in
  ""|"/"|"."|"/."|".") refuse "A18" "degenerate SRC path: '$SRC'" ;;
esac
case "$DST" in
  ""|"/"|"."|"/."|".") refuse "A18" "degenerate DST path: '$DST'" ;;
esac

RSRC="$(realpath -m -- "$SRC")" || refuse "A18" "SRC unresolvable"
RDST_RAW="$(realpath -m -- "$DST")" || refuse "A18" "DST unresolvable"
case "$RSRC" in
  ""|"/"|"."|"/."|".") refuse "A18" "degenerate SRC realpath: '$RSRC'" ;;
esac
case "$RDST_RAW" in
  ""|"/"|"."|"/."|".") refuse "A18" "degenerate DST realpath: '$RDST_RAW'" ;;
esac

# resolve EXISTING DST symlink for path law (A12); A18 replacement happens later
if [ -L "$DST" ]; then
  RDST="$(realpath -- "$DST")" || refuse "A12" "DST symlink unresolvable"
  if [ "$RDST" = "$RSRC" ] || case "$RDST/" in "$RSRC"/*) true;; *) false;; esac; then
    refuse "A12" "DST symlink resolves into SRC"
  fi
  # DST symlink resolving OUTSIDE SRC is ACCEPTED here; replaced with real tree at 1g (A18)
else
  RDST="$RDST_RAW"
fi

# A12: identity / ancestor / descendant, either direction (realpath, component-safe)
[ "$RSRC" = "$RDST" ] && refuse "A12" "realpath(SRC) == realpath(DST)"
case "$RDST/" in "$RSRC"/*) refuse "A12" "DST inside SRC";; esac
case "$RSRC/" in "$RDST"/*) refuse "A12" "SRC inside DST (DST is ancestor of SRC)";; esac

# ---- owned concrete paths (A14/A15): computed pure, validated before creation
# Every owned path is REALPATH-RESOLVED before comparison (A15: concrete
# instantiated paths, symlink targets resolved), never raw-string compared.
LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/hermes-context"

# resolve the log dir (and any log env var) THROUGH existing symlinks, purely:
# realpath -m performs no filesystem writes, so the zero-write guard holds.
LOGDIR_R="$(realpath -m -- "$LOGDIR")" || refuse "A14" "log dir unresolvable: $LOGDIR"
LOGFILE="$LOGDIR/sync.log"           # log ALWAYS outside DST (A8)
STAGEPARENT="$LOGDIR"                # stage under script-owned cache dir, never TMPDIR root
STAGE="$STAGEPARENT/stage.$$"        # A20: PURE string, no mktemp/mkdir yet
STAGE_R="$LOGDIR_R/stage.$$"
# if the log FILE itself already exists as a symlink, resolve where it points:
LOGFILE_R="$LOGDIR_R/sync.log"
if [ -L "$LOGFILE" ] || [ -e "$LOGFILE" ]; then
  LOGFILE_R="$(realpath -m -- "$LOGFILE")" || refuse "A8" "log file unresolvable: $LOGFILE"
fi
ENTRYDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || ENTRYDIR=""

# ledger 8: any log-related env var resolved (through symlinks) into the
# mirror tree -> refuse, write nothing
LOGENV_CANDIDATES=()
[ -n "${HERMES_CTX_LOG:-}" ] && LOGENV_CANDIDATES+=("$(realpath -m -- "$(dirname -- "$HERMES_CTX_LOG")")")
[ -n "${LOG_DIR:-}" ] && LOGENV_CANDIDATES+=("$(realpath -m -- "$LOG_DIR")")

for owned in "$LOGDIR_R" "$STAGEPARENT" "$STAGE_R" "$LOGFILE_R" "$ENTRYDIR" "${LOGENV_CANDIDATES[@]}"; do
  [ -n "$owned" ] || continue
  case "$owned/" in "$RDST"/*) refuse "A14" "log/owned path inside mirror tree: $owned";; esac
  case "$owned/" in "$RSRC"/*) refuse "A14" "log/owned path inside SRC: $owned";; esac
  case "$RDST/" in "$owned"/*) refuse "A15" "DST inside owned path: $owned";; esac
  case "$RSRC/" in "$owned"/*) refuse "A15" "SRC inside owned path: $owned";; esac
done
[ "$STAGE_R" != "$RSRC" ] && [ "$STAGE_R" != "$RDST" ] || refuse "A14" "stage collides with SRC/DST"

# ---- --verify mode (ledger 12): FAIL nonzero when DST absent; OK only on exact mirror
if [ "$VERIFY" = "1" ]; then
  if [ -L "$DST" ] || [ ! -e "$DST" ]; then
    echo "FAIL: verify: DST absent (or still a symlink): $DST" >&2
    exit 1
  fi
  if diff -r --no-dereference -- "$SRC" "$DST" >/dev/null 2>&1; then
    echo "OK: DST is an exact MIRROR of SRC"
    exit 0
  fi
  echo "FAIL: verify: DST does not exactly mirror SRC" >&2
  exit 1
fi

# ---- 1c. dry-run: stdout plan ONLY; zero writes incl. logs (A6/A16) ---------
if [ "$DRYRUN" = "1" ]; then
  echo "dry-run plan (no writes performed):"
  echo "  SRC=$SRC"
  echo "  DST=$DST"
  echo "  would: mkdir -p $LOGDIR"
  echo "  would: stage copy of SRC into $STAGE"
  if command -v rsync >/dev/null 2>&1; then
    echo "  primary: rsync -a --delete '$SRC/' -> stage/"
  else
    echo "  fallback: tar pipe SRC -> stage, then recursive stale reconcile"
  fi
  echo "  would: content-verify stage vs SRC (MIRROR class: contents+dirs+symlinks)"
  echo "  would: replace DST (rm existing incl. symlink, A18) with verified stage"
  echo "  would: append result to $LOGFILE"
  exit 0
fi

# ---- 1d. real run: only now may we create anything (A16) --------------------
mkdir -p -- "$LOGDIR" || { echo "FAIL: cannot create log dir $LOGDIR" >&2; exit 1; }
mkdir -p -- "$STAGE" || { echo "FAIL: cannot create stage $STAGE" >&2; exit 1; }

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOGFILE"; }

cleanup_fail() { rm -rf -- "$STAGE" 2>/dev/null; log "FAIL: $1"; echo "FAIL: $1" >&2; exit 1; }

# ---- 1e. copy SRC contents into stage (no nesting, A4) ----------------------
if command -v rsync >/dev/null 2>&1; then
  # plain -a: symlinks copied as symlinks (MIRROR class), no =no-form options
  rsync -a --delete "$SRC/" "$STAGE/" || cleanup_fail "rsync staging failed"
else
  tar -C "$SRC" -cf - . | tar -C "$STAGE" -xf - \
    || cleanup_fail "tar-pipe staging failed"
  # A7 fallback reconcile: delete stale entries at ALL depths + fix type changes.
  # Reserved namespace .prunelist* under stage (A20); newline-separated paths
  # (exotic control-char filenames are KNOWN_LIMITATIONS, A21).
  PRUNELIST="$(mktemp "$STAGE/.prunelist.XXXXXX")" || cleanup_fail "prunelist mktemp failed"
  ( cd "$STAGE" && find . -mindepth 1 ! -name '.prunelist*' -print ) \
    | LC_ALL=C sort > "$PRUNELIST" || cleanup_fail "prunelist build failed"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rel="${rel#./}"
    s="$STAGE/$rel"; o="$SRC/$rel"
    if [ ! -e "$o" ] && [ ! -L "$o" ]; then
      rm -rf -- "$s"                                  # stale at any depth (A7)
    elif [ -L "$s" ] || [ -L "$o" ]; then
      if [ ! -L "$s" ] || [ ! -L "$o" ] \
         || [ "$(readlink -- "$s")" != "$(readlink -- "$o")" ]; then
        rm -rf -- "$s"; cp -a -- "$o" "$s" || cleanup_fail "fallback recopy failed: $rel"
      fi
    elif [ -d "$s" ] && [ -d "$o" ]; then
      :                                               # both dirs: recurse via find walk
    elif [ -e "$s" ] && [ -e "$o" ]; then
      rm -rf -- "$s"; cp -a -- "$o" "$s" || cleanup_fail "fallback recopy failed: $rel"
    else
      cp -a -- "$o" "$s" || cleanup_fail "fallback copy failed: $rel"
    fi
  done < "$PRUNELIST"
  rm -f -- "$PRUNELIST"
fi

# ---- 1f. content-verify stage vs SRC (A9/A13, MIRROR class) -----------------
# diff -r --no-dereference covers files, recursive dirs, and symlinks (link targets)
if diff -r --no-dereference -- "$SRC" "$STAGE" >/dev/null 2>&1; then
  :
else
  cleanup_fail "staged copy failed MIRROR verification against SRC"
fi
# VERIFIED_COPY now exists outside DST (A11 satisfied)

# ---- 1g. replace DST with the verified real tree (A11/A18) ------------------
if [ -L "$DST" ]; then
  rm -f -- "$DST"          # remove the LINK itself; outside target untouched
elif [ -e "$DST" ]; then
  rm -rf -- "$DST"
fi
if ! mv -- "$STAGE" "$DST" 2>/dev/null; then
  # cross-filesystem: converge then clean stage (DST freshly removed -> exact mirror)
  mkdir -p -- "$DST"
  rsync -a --delete "$STAGE/" "$DST/" 2>/dev/null || cp -a "$STAGE/." "$DST/" \
    || cleanup_fail "cross-fs install into DST failed"
  rm -rf -- "$STAGE"
fi

# final A18/A9 assertion: DST is now the real tree, exact mirror
[ -L "$DST" ] && refuse "A18" "DST still a symlink after sync (internal error)"
diff -r --no-dereference -- "$SRC" "$DST" >/dev/null 2>&1 \
  || cleanup_fail "post-install mirror verification failed"

log "OK: mirror verified"
exit 0

