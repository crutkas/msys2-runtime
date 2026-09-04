#!/bin/bash
# READ-ONLY. Focused comment audit on port-relevant sources only.
R=/root/xc/runtime
echo "############ exact line numbers of the misleading comments ############"
echo "--- exception.h ---"
grep -n 'every architecture\|_DISPATCHER_CONTEXT_ARM64\|P19_DISPATCHER_CONTEXT\|w32api (v12' \
  $R/winsup/cygwin/local_includes/exception.h
echo "--- cygtls.h ---"
grep -n 'names the struct\|_DISPATCHER_CONTEXT_ARM64\|P19_DISPATCHER_CONTEXT\|x86-only directive' \
  $R/winsup/cygwin/local_includes/cygtls.h

echo
echo "############ sibling's three diagnostics: comments present? ############"
for f in winsup/cygwin/math/fabsl.c winsup/cygwin/cygwin.sc.in \
         winsup/cygwin/local_includes/cygmalloc.h newlib/libc/include/sys/config.h; do
  echo "---- $f ----"
  grep -n -i 'aarch64\|MALLOC_ALIGNMENT\|pei-aarch64' $R/$f 2>/dev/null | head -8
done

echo
echo "############ my own newlib diagnostics: comments present? ############"
for f in newlib/libc/machine/aarch64/asmdefs.h newlib/libc/machine/aarch64/setjmp.S \
         newlib/libc/machine/aarch64/rawmemchr.S newlib/configure.host winsup/cygwin/thread.cc; do
  echo "---- $f ----"
  grep -n '__aarch64_pe_asmdefs__\|__pe_asm_fixed__\|libm_machine_dir\|yield' $R/$f 2>/dev/null | head -4
done

echo
echo "############ INDEPENDENT CHECK: three winnt.h header sets ############"
probe() { [ -f "$1" ] && printf '%-46s %8s bytes   _DISPATCHER_CONTEXT_ARM64 x%-3s  struct _DISPATCHER_CONTEXT x%s\n' \
  "$2" "$(stat -c%s "$1")" "$(grep -c '_DISPATCHER_CONTEXT_ARM64' "$1")" \
  "$(grep -c 'struct _DISPATCHER_CONTEXT\b' "$1")" || echo "MISSING: $2 ($1)"; }
probe /root/xc/inst/aarch64-pc-cygwin/include/w32api/winnt.h "build sysroot w32api v12.0.0"
probe /root/xc/mingw-w64/mingw-w64-tools/widl/include/winnt.h "mingw-w64-tools/widl"
C=$(ls -d /mnt/c/Users/crutkasLocal/AppData/Local/github-copilot-git-*/clangarm64/include/winnt.h 2>/dev/null | head -1)
[ -n "$C" ] && probe "$C" "CLANGARM64 toolchain" || echo "CLANGARM64 winnt.h not located from here"
