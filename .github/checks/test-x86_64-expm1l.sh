#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=${RUNNER_TEMP:-/tmp}/x86_64-expm1l.$$

cleanup()
{
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$work"

case "$(uname -m)" in
x86_64) ;;
*)
  echo "x86_64 expm1l regression requires an x86_64 MSYS process" >&2
  exit 1
  ;;
esac

gcc -O2 -Wall -Wextra -Werror -fno-builtin-expm1l \
  "$repo_root/winsup/cygwin/math/expm1l.c" \
  "$repo_root/.github/checks/x86_64-expm1l.c" \
  -lm -o "$work/x86_64-expm1l.exe"
"$work/x86_64-expm1l.exe"
