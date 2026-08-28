#!/usr/bin/env bash

set -euo pipefail

if test "$#" -lt 11; then
  echo "usage: $0 BASE LEGACY_HEAD LEGACY_SESSION INVALID_HEAD" \
    "INVALID_RECORDED_SESSION PRE_ERRATUM_HEAD PRE_ERRATUM_SESSION" \
    "HEAD SESSION DCO REVOKED..." >&2
  exit 1
fi

checks_dir=$(cd "$(dirname "$0")" && pwd)

# Every check lives in the Python auditor. It reads raw commit bytes, handles
# each git exit status explicitly, and never lets a failing command collapse
# into an empty shell substitution that would silently satisfy a test.
exec python3 "$checks_dir/audit-commit-trailers.py" "$@"
