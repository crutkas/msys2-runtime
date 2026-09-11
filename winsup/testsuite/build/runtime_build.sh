#!/usr/bin/env bash
# Host-only build plumbing regressions; no target executable is run.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
cleanup ()
{
    for record in "$work"/result.dll.link.* "$work"/failed.dll.link.*; do
        test -d "$record" || continue
        rm -f -- "$record/command.sh" "$record/argv" "$record/stdout" \
            "$record/stderr" "$record/exit-status" "$record/output.sha256"
        rmdir -- "$record"
    done
    rm -f -- "$work/compiler" "$work/actual-argv" "$work/expected-argv" \
        "$work/actual-library-path" "$work/result.dll" "$work/windres" \
        "$work/windres-argv" "$work/winver.o" "$work/version.cc" "$work/version.log"
    rmdir -- "$work/includes" "$work"
}
trap cleanup EXIT
cd "$work"
mkdir includes
cat > compiler <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" > actual-argv
printf '%s' "${LIBRARY_PATH-unset}" > actual-library-path
if [[ ${1-} == --fail ]]; then
    echo 'intentional link failure' >&2
    exit 37
fi
printf 'linked output\n' > "$1"
EOF
chmod +x compiler
export LIBRARY_PATH='a path:second'
args=('result.dll' 'space argument' 'single'"'"'quote' '$literal' '-Lsearch path')
bash "$source_dir/cygwin/scripts/link-runtime" result.dll ./compiler "${args[@]}"
printf '%s\0' "${args[@]}" > expected-argv
cmp actual-argv expected-argv
records=(result.dll.link.*)
test "${#records[@]}" -eq 1
test "$(cat "${records[0]}/exit-status")" = 0
sha256sum -c "${records[0]}/output.sha256"
unset LIBRARY_PATH
bash "${records[0]}/command.sh"
cmp actual-argv expected-argv
test "$(cat actual-library-path)" = 'a path:second'
status=0
bash "$source_dir/cygwin/scripts/link-runtime" failed.dll ./compiler --fail || status=$?
test "$status" -eq 37
failed=(failed.dll.link.*)
test "$(cat "${failed[0]}/exit-status")" = 37
test ! -e "${failed[0]}/output.sha256"
grep -q 'intentional link failure' "${failed[0]}/stderr"

cat > windres <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > windres-argv
for flag in '-Iincludes' '-Isystem-headers' '-Iquote-headers' '-Iafter-headers' '-D__MSYS__'; do
    grep -Fx -- "$flag" windres-argv >/dev/null
done
printf 'resource output\n' > winver.o
EOF
chmod +x windres
CC=cc SOURCE_DATE_EPOCH=1788224411 \
    bash "$source_dir/cygwin/scripts/mkvers.sh" \
    "$source_dir/cygwin/include/cygwin/version.h" "$source_dir/cygwin/winver.rc" \
    ./windres -I includes -isystem system-headers -iquote quote-headers \
    -idirafter after-headers -D__MSYS__ \
    > version.log
test -s winver.o
echo 'PASS runtime link recording, replay, failure propagation and resource flags'
