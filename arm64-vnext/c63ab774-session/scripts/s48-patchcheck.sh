#!/bin/bash
# READ-ONLY. Does the sealed arm64-port.patch actually CONTAIN longdouble.c,
# or does it only mention it (e.g. in Makefile.am)?
P=/mnt/c/Users/crutkasLocal/.copilot/session-state/724ee2e9-51c7-40d7-b303-e6fcbfe78490/files/arm64-port-backup-2026-09-02/arm64-port.patch
echo "=== does the patch create longdouble.c as a file? ==="
grep -n 'diff --git.*longdouble' "$P" || echo "NO 'diff --git' header for longdouble.c -> the patch does NOT create the file"
echo
echo "=== every mention of 'longdouble' in the patch ==="
grep -n 'longdouble' "$P"
echo
echo "=== patch shape, for the record ==="
printf 'files (diff --git headers) : %s\n' "$(grep -c '^diff --git ' "$P")"
printf 'insertions                 : %s\n' "$(( $(grep -c '^+[^+]' "$P") + $(grep -cx '+' "$P") ))"
printf 'deletions                  : %s\n' "$(( $(grep -c '^-[^-]' "$P") + $(grep -cx '-' "$P") ))"
