#!/bin/bash
# READ-ONLY audit. No edits to /root/xc.
R=/root/xc/runtime
echo "############ A. exception.h — the comment my token swap installed ############"
sed -n '8,30p' $R/winsup/cygwin/local_includes/exception.h | cat -n | sed 's/^/   /'

echo
echo "############ B. cygtls.h — comment vs code contradiction ############"
sed -n '360,380p' $R/winsup/cygwin/local_includes/cygtls.h | cat -n | sed 's/^/   /'

echo
echo "############ C. every ADDED comment line in the uncommitted diff ############"
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
grep -n '^+' $D/runtime-uncommitted.diff \
  | grep -E '/\*|\*/|^\+[0-9]*:?\+?[[:space:]]*\*|//|#[[:space:]]*[A-Z]' \
  | grep -viE '^\+\+\+|#include|#ifdef|#ifndef|#endif|#else|#elif|#define|#error|#if ' \
  | head -60

echo
echo "############ D. sibling's three diagnostics — do they carry comments? ############"
for f in winsup/cygwin/math/fabsl.c winsup/cygwin/cygwin.sc.in winsup/cygwin/local_includes/cygmalloc.h newlib/libc/include/sys/config.h; do
  echo "---- $f ----"
  grep -n 'aarch64\|__aarch64__' $R/$f 2>/dev/null | head -6
done

echo
echo "############ E. INDEPENDENT CHECK of the three winnt.h header sets ############"
for h in \
  /root/xc/inst/aarch64-pc-cygwin/include/w32api/winnt.h \
  /root/xc/mingw-w64/mingw-w64-tools/widl/include/winnt.h \
  ; do
  if [ -f "$h" ]; then
    printf '%-72s %8s bytes  _DISPATCHER_CONTEXT_ARM64 x%s\n' \
      "$h" "$(stat -c%s "$h")" "$(grep -c '_DISPATCHER_CONTEXT_ARM64' "$h")"
  else
    echo "MISSING: $h"
  fi
done
for h in $(ls /mnt/c/Users/crutkasLocal/AppData/Local/github-copilot-git-*/clangarm64/include/winnt.h 2>/dev/null | head -1); do
  printf '%-72s %8s bytes  _DISPATCHER_CONTEXT_ARM64 x%s\n' \
    "CLANGARM64 winnt.h" "$(stat -c%s "$h")" "$(grep -c '_DISPATCHER_CONTEXT_ARM64' "$h")"
done
