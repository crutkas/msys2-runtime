#!/usr/bin/bash
set -euo pipefail

out=/qualification
mkdir -p "$out"

/usr/bin/sleep 20 &
child_pid=$!

printf '%s\n' "$$" > "$out/parent-cygwin-pid.txt"
printf '%s\n' "$child_pid" > "$out/child-cygwin-pid.txt"

/usr/bin/ps > "$out/default.txt"
/usr/bin/ps -p "$$" > "$out/parent.txt"
/usr/bin/ps -p "$child_pid" > "$out/child.txt"
/usr/bin/ps -s > "$out/summary.txt"
/usr/bin/ps -W > "$out/windows.txt"

touch "$out/ready"
wait "$child_pid"
