#!/usr/bin/env bash

set -euo pipefail

if test "$#" -gt 1; then
  echo "usage: $0 [C-PREPROCESSOR]" >&2
  exit 2
fi

cc="${1:-gcc}"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/include/sys"
for header in signal.h sched.h time.h; do
  : > "$work/include/$header"
done
: > "$work/include/sys/types.h"

dump_macros()
{
  name="$1"
  shift
  "$cc" \
    -E \
    -dM \
    -nostdinc \
    -I"$work/include" \
    -I"$repo_root/winsup/cygwin/include" \
    "$@" \
    -include pthread.h \
    -x c /dev/null \
    > "$work/$name.macros"
}

check_symbol_macros()
{
  macros="$1"
  grep -Eq '^#define PTHREAD_ONCE_INIT \{ PTHREAD_MUTEX_INITIALIZER, 0 \}$' \
    "$macros"
  grep -Eq '^#define PTHREAD_COND_INITIALIZER \(&__pthread_cond_initializer\)$' \
    "$macros"
  grep -Eq '^#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP \(&__pthread_recursive_mutex_initializer_np\)$' \
    "$macros"
  grep -Eq '^#define PTHREAD_NORMAL_MUTEX_INITIALIZER_NP \(&__pthread_normal_mutex_initializer_np\)$' \
    "$macros"
  grep -Eq '^#define PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP \(&__pthread_errorcheck_mutex_initializer_np\)$' \
    "$macros"
  grep -Eq '^#define PTHREAD_RWLOCK_INITIALIZER \(&__pthread_rwlock_initializer\)$' \
    "$macros"
}

check_numeric_macros()
{
  macros="$1"
  grep -Eq '^#define PTHREAD_COND_INITIALIZER \(pthread_cond_t\)21$' \
    "$macros"
  grep -Eq '^#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP \(pthread_mutex_t\)18$' \
    "$macros"
  grep -Eq '^#define PTHREAD_NORMAL_MUTEX_INITIALIZER_NP \(pthread_mutex_t\)19$' \
    "$macros"
  grep -Eq '^#define PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP \(pthread_mutex_t\)20$' \
    "$macros"
  grep -Eq '^#define PTHREAD_RWLOCK_INITIALIZER \(pthread_rwlock_t\)22$' \
    "$macros"
}

dump_macros aarch64 -D__aarch64__ -U__x86_64__ -U__i386__
check_symbol_macros "$work/aarch64.macros"

dump_macros aarch64-internal \
  -D__aarch64__ -U__x86_64__ -U__i386__ \
  -D__INSIDE_CYGWIN__ -D__cplusplus
check_symbol_macros "$work/aarch64-internal.macros"

dump_macros x86_64 -D__x86_64__ -U__aarch64__ -U__i386__
check_symbol_macros "$work/x86_64.macros"

dump_macros x86_64-internal \
  -D__x86_64__ -U__aarch64__ -U__i386__ \
  -D__INSIDE_CYGWIN__ -D__cplusplus
check_numeric_macros "$work/x86_64-internal.macros"

dump_macros i686 -D__i386__ -U__aarch64__ -U__x86_64__
check_symbol_macros "$work/i686.macros"

dump_macros i686-internal \
  -D__i386__ -U__aarch64__ -U__x86_64__ \
  -D__INSIDE_CYGWIN__ -D__cplusplus
check_numeric_macros "$work/i686-internal.macros"

grep -Fq 'defined(__x86_64__) || defined(__aarch64__)' \
  "$repo_root/newlib/libc/ctype/ctype_.c"
grep -Fxq '_ctype_ DATA' "$repo_root/winsup/cygwin/aarch64/cygwin.din"
grep -Fxq '_ctype_ DATA' "$repo_root/winsup/cygwin/x86_64/cygwin.din"
