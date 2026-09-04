#!/bin/bash
# READ-ONLY. What is in the evidence dir now vs what I last sealed (15 files)?
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
cd "$D" || exit 1
echo "=== current files (excluding SHA256SUMS) ==="
find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | nl
echo
echo "=== does the CURRENT SHA256SUMS still verify? ==="
sha256sum -c SHA256SUMS --quiet 2>&1 | head -20
echo "rc=$?"
echo
echo "=== entries in SHA256SUMS: ==="
wc -l < SHA256SUMS
