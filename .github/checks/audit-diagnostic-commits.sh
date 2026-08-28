#!/usr/bin/env bash

set -euo pipefail

base=${1:?base commit is required}
revoked=${2:?revoked commit is required}
head=${3:?head commit is required}
legacy_head=${4:?legacy diagnostic head is required}
legacy_session=${5:?legacy Copilot session id is required}
session=${6:?Copilot session id is required}
dco=${7:?DCO identity is required}

test "$(git rev-parse "$head^{commit}")" = "$(git rev-parse HEAD)"
test "$(git merge-base "$base" "$head")" = "$base"
test "$(git merge-base "$base" "$legacy_head")" = "$base"
test "$(git merge-base "$legacy_head" "$head")" = "$legacy_head"
test -z "$(git rev-list --min-parents=2 "$base..$head")"

if git merge-base --is-ancestor "$revoked" "$head"; then
  echo "revoked commit $revoked is an ancestor of $head" >&2
  exit 1
fi

coauthor='Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>'
signoff="Signed-off-by: $dco"

while read -r commit; do
  commit_session=$session
  if git merge-base --is-ancestor "$commit" "$legacy_head"; then
    commit_session=$legacy_session
  fi
  session_trailer="Copilot-Session: $commit_session"
  expected=$(printf '%s\n%s\n%s' "$signoff" "$coauthor" "$session_trailer")
  message=$(git log -1 --format=%B "$commit")
  if test "$(printf '%s\n' "$message" | grep -Fxc "$signoff")" -ne 1 \
      || test "$(printf '%s\n' "$message" | grep -Fxc "$coauthor")" -ne 1 \
      || test "$(printf '%s\n' "$message" | grep -Fxc "$session_trailer")" -ne 1 \
      || test "$(printf '%s\n' "$message" | tail -n 3)" != "$expected"; then
    echo "invalid terminal trailer pair on $commit" >&2
    exit 1
  fi
done < <(git rev-list --reverse "$base..$head")

printf 'classification=diagnostic\nconsumable=false\nbase=%s\nlegacy_head=%s\nhead=%s\ntree=%s\n' \
  "$base" "$legacy_head" "$head" "$(git rev-parse "$head^{tree}")"
