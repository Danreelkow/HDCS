#!/usr/bin/env bash
# gate.sh — 004: anti-fabrication — every register row re-observed, route claims must match reality. exit 0 = GATE PASS.
set -u; cd "$(dirname "$0")" || exit 1
fail() { echo "GATE FAIL: $1"; exit 1; }
[ -f artifact/DOSSIER.md ] || fail "artifact/DOSSIER.md missing"
[ -f source/urls.txt ] || fail "source/urls.txt missing (register of record)"
D=artifact/DOSSIER.md
dead=0; checked=0
while IFS=$'\t' read -r url claimed; do
  [ -n "$url" ] || continue
  checked=$((checked+1))
  grep -qF "$url" "$D" || fail "register URL not documented: $url"
  observed=$(node -e "
    const c = new AbortController(); const t = setTimeout(() => c.abort(), 15000);
    fetch('$url', { redirect: 'follow', signal: c.signal, headers: { 'user-agent': 'Mozilla/5.0 hdcs-gate' } })
      .then(r => { clearTimeout(t); const s = r.status;
        process.stdout.write(s >= 500 || s === 404 ? 'dead' : [401,403,418,429].includes(s) ? 'botwall' : 'open'); })
      .catch(() => { clearTimeout(t); process.stdout.write('dead'); });
  " 2>/dev/null) || observed=dead
  [ "$observed" = "dead" ] && dead=$((dead+1))
  grep -E "^.*${url}.*" "$D" | grep -qF "$observed" || fail "route claim mismatch for $url: gate observed '$observed', dossier does not state it"
done < source/urls.txt
[ "$checked" -eq 15 ] || fail "register must hold exactly 15 URLs (found $checked)"
[ "$dead" -le 1 ] || fail "more than one dead URL: $dead"
echo "GATE PASS (checked=$checked dead=$dead)"
