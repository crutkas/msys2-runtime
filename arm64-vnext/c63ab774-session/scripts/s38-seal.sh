#!/bin/bash
# Reseal SHA256SUMS over the evidence directory. Run in the SAME turn as the edits.
set -u
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
cd "$D" || exit 1
rm -f SHA256SUMS
find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort \
  | while read -r f; do sha256sum "$f"; done > SHA256SUMS
echo "=== SHA256SUMS ($(wc -l < SHA256SUMS) files) ==="
while read -r h f; do printf '%-46s %10s  %s\n' "$f" "$(stat -c%s "$f")" "$h"; done < SHA256SUMS
echo
echo "=== self-verify ==="
sha256sum -c SHA256SUMS --quiet && echo "ALL FILES VERIFY OK"
echo
echo "=== SHA256SUMS itself ==="
sha256sum SHA256SUMS
