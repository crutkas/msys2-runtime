#!/bin/bash
# READ-ONLY. Verify the line-ending variance across all copies of longdouble.c.
# Does not modify any file.
S=/mnt/c/Users/crutkasLocal/.copilot/session-state
MINE="$S/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence/untracked/winsup/cygwin/math/aarch64/longdouble.c"
SEALED="$S/724ee2e9-51c7-40d7-b303-e6fcbfe78490/files/arm64-port-backup-2026-09-02"
LIVE=/root/xc/runtime/winsup/cygwin/math/aarch64/longdouble.c

probe() {
  local p="$1" label="$2"
  if [ ! -f "$p" ]; then echo "MISSING : $label"; echo "          ($p)"; return; fi
  local sz crlf lf raw norm
  sz=$(stat -c%s "$p")
  crlf=$(grep -c $'\r$' "$p")
  lf=$(wc -l < "$p")
  raw=$(sha256sum "$p" | cut -c1-64)
  norm=$(tr -d '\r' < "$p" | sha256sum | cut -c1-64)
  printf '%-42s %6s B  lines=%-4s CRLF=%-4s\n' "$label" "$sz" "$lf" "$crlf"
  printf '    raw sha256        : %s\n' "$raw"
  printf '    LF-normalised sha : %s\n' "$norm"
}

probe "$MINE"  "MY evidence copy"
echo
probe "$LIVE"  "LIVE tree /root/xc (source of truth)"
echo
echo "=== searching sealed backup for longdouble.c ==="
find "$SEALED" -name 'longdouble.c' 2>/dev/null | while read -r f; do
  probe "$f" "sealed backup: ${f#$SEALED/}"
  echo
done
echo "=== is it inside the sealed .patch instead? ==="
grep -l 'longdouble' "$SEALED"/*.patch 2>/dev/null || echo "(not referenced in any .patch - consistent with 'NOT in the patch')"
