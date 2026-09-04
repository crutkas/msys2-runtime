#!/bin/bash
# READ-ONLY verification of the reported false claim, before fixing it.
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
SRC=/mnt/c/Users/crutkasLocal/.copilot/session-state/290c9aaf-a5d1-4941-86fd-c96d0f8d2262/files

echo "=== 1. does RESULT.md contain ANY 64-hex sha256? ==="
grep -oE '\b[0-9a-f]{64}\b' "$D/RESULT.md" | wc -l

echo "=== 2. does SHA256SUMS reference /root/xc at all? ==="
grep -c 'root/xc' "$D/SHA256SUMS"

echo "=== 3. how many files does SHA256SUMS actually cover? ==="
wc -l < "$D/SHA256SUMS"

echo "=== 4. the false sentence, in context ==="
grep -n 'Sizes and SHA-256' "$D/ASSETS-README.md"

echo
echo "=== 5. source capture files present? ==="
ls -la "$SRC/built-artifact-hashes.txt" "$SRC/capture-artifact-hashes.sh" 2>&1

echo
echo "=== 6. content of built-artifact-hashes.txt ==="
cat "$SRC/built-artifact-hashes.txt" 2>/dev/null
