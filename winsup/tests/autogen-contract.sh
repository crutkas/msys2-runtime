#!/bin/sh
set -eu

test_dir=$(cd "$(dirname "$0")" && pwd)
autogen=$test_dir/../autogen.sh
tmp_root=${TMPDIR:-/tmp}/autogen-contract.$$
case_dir=$tmp_root/'script dir $literal'
tool_dir=$tmp_root/'tool dir $literal'
log=$tmp_root/commands.log

cleanup ()
{
  rm -rf "$tmp_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$case_dir" "$tool_dir"
case_dir=$(cd "$case_dir" && pwd)
tool_dir=$(cd "$tool_dir" && pwd)
cp "$autogen" "$case_dir/autogen.sh"

cp "$autogen" "$tmp_root/fake-tool"
cat > "$tmp_root/fake-tool" <<'EOF'
#!/bin/sh
name=${0##*/}
printf '%s|%s' "$name" "$PWD" >> "$COMMAND_LOG"
for arg
do
  printf '|%s' "$arg" >> "$COMMAND_LOG"
done
printf '\n' >> "$COMMAND_LOG"

if test "${FAIL_TOOL-}" = "$name"
then
  exit "${FAIL_STATUS-1}"
fi
EOF

for tool in aclocal autoconf automake rm
do
  cp "$tmp_root/fake-tool" "$tool_dir/$tool tool \$literal"
done

run_autogen ()
{
  COMMAND_LOG=$log \
  ACLOCAL=$tool_dir/'aclocal tool $literal' \
  AUTOCONF=$tool_dir/'autoconf tool $literal' \
  AUTOMAKE=$tool_dir/'automake tool $literal' \
  RM=$tool_dir/'rm tool $literal' \
    "${TEST_SHELL:-/bin/sh}" "$case_dir/autogen.sh"
}

run_autogen
cat > "$tmp_root/expected.log" <<EOF
aclocal tool \$literal|$case_dir|--force
autoconf tool \$literal|$case_dir|-f
automake tool \$literal|$case_dir|-ac
rm tool \$literal|$case_dir|-rf|autom4te.cache
EOF
cmp "$tmp_root/expected.log" "$log"

: > "$log"
set +e
FAIL_TOOL='autoconf tool $literal' FAIL_STATUS=47 run_autogen
status=$?
set -e
test "$status" -eq 47
cat > "$tmp_root/expected-failure.log" <<EOF
aclocal tool \$literal|$case_dir|--force
autoconf tool \$literal|$case_dir|-f
EOF
cmp "$tmp_root/expected-failure.log" "$log"
