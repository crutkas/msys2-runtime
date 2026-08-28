#!/usr/bin/env bash

set -euo pipefail

base=${1:?base commit is required}
revoked=${2:?revoked commit is required}
head=${3:?head commit is required}
session=${4:?Copilot session id is required}
dco=${5:?DCO identity is required}

test "$(git rev-parse "$head^{commit}")" = "$(git rev-parse HEAD)"
test "$(git merge-base "$base" "$head")" = "$base"
test -z "$(git rev-list --min-parents=2 "$base..$head")"

if git merge-base --is-ancestor "$revoked" "$head"; then
  echo "revoked commit $revoked is an ancestor of $head" >&2
  exit 1
fi

coauthor='Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>'
session_trailer="Copilot-Session: $session"
signoff="Signed-off-by: $dco"
expected=$(printf '%s\n%s\n%s' "$signoff" "$coauthor" "$session_trailer")

while read -r commit; do
  message=$(git log -1 --format=%B "$commit")
  if test "$(printf '%s\n' "$message" | grep -Fxc "$signoff")" -ne 1 \
      || test "$(printf '%s\n' "$message" | grep -Fxc "$coauthor")" -ne 1 \
      || test "$(printf '%s\n' "$message" | grep -Fxc "$session_trailer")" -ne 1 \
      || test "$(printf '%s\n' "$message" | tail -n 3)" != "$expected"; then
    echo "invalid terminal trailer pair on $commit" >&2
    exit 1
  fi
done < <(git rev-list --reverse "$base..$head")

printf 'classification=diagnostic\nconsumable=false\nbase=%s\nhead=%s\ntree=%s\n' \
  "$base" "$head" "$(git rev-parse "$head^{tree}")"
