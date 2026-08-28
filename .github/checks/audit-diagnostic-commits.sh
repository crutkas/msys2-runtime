#!/usr/bin/env bash

set -euo pipefail

base=${1:?base commit is required}
legacy_head=${2:?legacy diagnostic head is required}
legacy_session=${3:?legacy Copilot session id is required}
prior_head=${4:?prior diagnostic head is required}
prior_session=${5:?prior Copilot session id is required}
head=${6:?head commit is required}
session=${7:?Copilot session id is required}
dco=${8:?DCO identity is required}
shift 8

if test "$#" -lt 4; then
  echo "at least four revoked commits are required, received $#" >&2
  exit 1
fi

checks_dir=$(cd "$(dirname "$0")" && pwd)

# Resolve an object id, failing when it is empty, absent, or not a commit.
# Every ancestry check below runs against a resolved id, so nothing is
# vacuously satisfied by a missing object.
resolve () {
  local candidate=$1
  local resolved

  if test -z "$candidate"; then
    echo "empty object id supplied" >&2
    return 1
  fi
  if ! resolved=$(git rev-parse --verify --quiet "$candidate^{commit}"); then
    echo "object $candidate is absent or is not a commit" >&2
    return 1
  fi
  if test -z "$resolved"; then
    echo "object $candidate resolved to nothing" >&2
    return 1
  fi
  printf '%s\n' "$resolved"
}

base=$(resolve "$base")
legacy_head=$(resolve "$legacy_head")
prior_head=$(resolve "$prior_head")
head=$(resolve "$head")

test "$head" = "$(git rev-parse HEAD)"
test "$(git merge-base "$base" "$head")" = "$base"
test "$(git merge-base "$base" "$legacy_head")" = "$base"
test "$(git merge-base "$legacy_head" "$prior_head")" = "$legacy_head"
test "$(git merge-base "$prior_head" "$head")" = "$prior_head"
# Assigned separately so a failing git invocation aborts under set -e instead
# of collapsing into an empty substitution that would satisfy the test.
merge_commits=$(git rev-list --min-parents=2 "$base..$head")
test -z "$merge_commits"

revoked_tested=0
for candidate in "$@"; do
  revoked=$(resolve "$candidate")
  if git merge-base --is-ancestor "$revoked" "$head"; then
    echo "revoked commit $revoked is an ancestor of $head" >&2
    exit 1
  fi
  revoked_tested=$((revoked_tested + 1))
  printf 'revoked_absent=%s\n' "$revoked"
done

test "$revoked_tested" -eq "$#"

python3 "$checks_dir/audit-commit-trailers.py" \
  "$base" "$head" "$dco" "$session" \
  "$legacy_head=$legacy_session" "$prior_head=$prior_session"

tree=$(git rev-parse "$head^{tree}")
test -n "$tree"

printf 'classification=diagnostic\nconsumable=false\n'
printf 'base=%s\nlegacy_head=%s\nprior_head=%s\nhead=%s\ntree=%s\n' \
  "$base" "$legacy_head" "$prior_head" "$head" "$tree"
printf 'revoked_tested=%d\n' "$revoked_tested"
