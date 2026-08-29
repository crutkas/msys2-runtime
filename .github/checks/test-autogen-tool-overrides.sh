#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
autogen="$repo_root/winsup/autogen.sh"
test_shell=${TEST_SHELL:-/bin/sh}
work=${TMPDIR:-/tmp}/autogen-tool-overrides.$$
tools="$work/tools with spaces/\$literal"
trace="$work/trace"

cleanup()
{
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

assert_default()
{
  grep -F -x "$1" "$autogen" >/dev/null || {
    echo "missing default: $1" >&2
    exit 1
  }
}

assert_trace()
{
  expected=$1
  actual=$(cat "$trace")
  test "$actual" = "$expected" || {
    echo "unexpected invocation trace:" >&2
    cat "$trace" >&2
    exit 1
  }
}

assert_default ': "${ACLOCAL:=/usr/bin/aclocal}"'
assert_default ': "${AUTOCONF:=/usr/bin/autoconf}"'
assert_default ': "${AUTOMAKE:=/usr/bin/automake}"'
assert_default ': "${RM:=/bin/rm}"'

mkdir -p "$tools" "$work/winsup with spaces/\$literal"
cp "$autogen" "$work/winsup with spaces/\$literal/autogen.sh"

cat >"$tools/mock-tool" <<'EOF'
#!/bin/sh
name=${0##*/}
printf '%s' "$name" >>"$AUTOGEN_TEST_TRACE"
for argument
do
  printf '|%s' "$argument" >>"$AUTOGEN_TEST_TRACE"
done
printf '\n' >>"$AUTOGEN_TEST_TRACE"
if test "${AUTOGEN_TEST_FAIL-}" = "$name"
then
  exit 23
fi
EOF
chmod +x "$tools/mock-tool"
for tool in aclocal autoconf automake rm
do
  cp "$tools/mock-tool" "$tools/$tool"
done

AUTOGEN_TEST_TRACE=$trace \
ACLOCAL="$tools/aclocal" \
AUTOCONF="$tools/autoconf" \
AUTOMAKE="$tools/automake" \
RM="$tools/rm" \
"$test_shell" "$work/winsup with spaces/\$literal/autogen.sh"

assert_trace 'aclocal|--force
autoconf|-f
automake|-ac
rm|-rf|autom4te.cache'

: >"$trace"
set +e
AUTOGEN_TEST_TRACE=$trace \
AUTOGEN_TEST_FAIL=autoconf \
ACLOCAL="$tools/aclocal" \
AUTOCONF="$tools/autoconf" \
AUTOMAKE="$tools/automake" \
RM="$tools/rm" \
"$test_shell" "$work/winsup with spaces/\$literal/autogen.sh"
status=$?
set -e

test "$status" -eq 23 || {
  echo "expected autoconf failure status 23, got $status" >&2
  exit 1
}
assert_trace 'aclocal|--force
autoconf|-f'
