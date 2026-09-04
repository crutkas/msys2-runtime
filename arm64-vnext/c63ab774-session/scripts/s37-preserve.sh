#!/bin/bash
# PRESERVATION ONLY. Reads /root/xc/runtime; writes only into the session evidence dir.
# --no-optional-locks so git does not even refresh the index in the source tree.
set -u
R=/root/xc/runtime
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
mkdir -p "$D/untracked"
G="git --no-optional-locks -C $R"

echo "=== HEAD ==="
$G rev-parse HEAD | tee "$D/runtime-HEAD.txt"
$G log --oneline -1

echo
echo "=== 1. status inventory ==="
$G status --porcelain --untracked-files=all > "$D/runtime-git-status.txt"
echo -n "entries: "; wc -l < "$D/runtime-git-status.txt"
echo -n "  modified (M): "; grep -c '^ M\|^M ' "$D/runtime-git-status.txt"
echo -n "  untracked (??): "; grep -c '^??' "$D/runtime-git-status.txt"

echo
echo "=== 2a. diff written DIRECTLY via --output (no pipeline) ==="
# HEAD..worktree captures staged + unstaged together.
$G diff HEAD --output="$D/runtime-uncommitted.diff"
echo "wrote $D/runtime-uncommitted.diff"
ls -la "$D/runtime-uncommitted.diff"

echo
echo "=== 2b. VERIFICATION: shortstat vs. actual file contents ==="
$G diff HEAD --shortstat | tee "$D/runtime-diff-shortstat.txt"
SS=$($G diff HEAD --shortstat)
SS_FILES=$(echo "$SS" | grep -oE '[0-9]+ files? changed' | grep -oE '[0-9]+')
SS_INS=$(echo   "$SS" | grep -oE '[0-9]+ insertions?' | grep -oE '[0-9]+')
SS_DEL=$(echo   "$SS" | grep -oE '[0-9]+ deletions?'  | grep -oE '[0-9]+')
SS_INS=${SS_INS:-0}; SS_DEL=${SS_DEL:-0}

F=$(grep -c '^diff --git ' "$D/runtime-uncommitted.diff")
I=$(grep -c '^+[^+]' "$D/runtime-uncommitted.diff")
I2=$(grep -cx '+' "$D/runtime-uncommitted.diff")   # bare '+' = inserted blank line
E=$(grep -c '^-[^-]' "$D/runtime-uncommitted.diff")
E2=$(grep -cx '-' "$D/runtime-uncommitted.diff")
INS=$((I + I2)); DEL=$((E + E2))

printf 'shortstat : %s files, %s insertions, %s deletions\n' "$SS_FILES" "$SS_INS" "$SS_DEL"
printf 'diff file : %s "diff --git" headers, %s insertions, %s deletions\n' "$F" "$INS" "$DEL"
OK=1
[ "$F"   = "$SS_FILES" ] || { echo "MISMATCH: file count"; OK=0; }
[ "$INS" = "$SS_INS"   ] || { echo "MISMATCH: insertions"; OK=0; }
[ "$DEL" = "$SS_DEL"   ] || { echo "MISMATCH: deletions";  OK=0; }
[ "$OK" = 1 ] && echo "VERIFY: PASS - diff file is complete and unmangled" || echo "VERIFY: FAIL"

echo
echo "=== 2c. untracked files copied verbatim ==="
$G status --porcelain --untracked-files=all | sed -n 's/^?? //p' | while read -r u; do
  if [ -f "$R/$u" ]; then
    mkdir -p "$D/untracked/$(dirname "$u")"
    cp -p "$R/$u" "$D/untracked/$u"
    printf '  %-60s %8s bytes\n' "$u" "$(stat -c%s "$R/$u")"
  fi
done
find "$D/untracked" -type f | sed "s|$D/||"
