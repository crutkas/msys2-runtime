#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
echo "=== libgcc for target? ==="
aarch64-pc-cygwin-gcc -print-libgcc-file-name 2>&1
ls -la $(aarch64-pc-cygwin-gcc -print-libgcc-file-name 2>/dev/null) 2>&1
echo
echo "=== import libs in sysroot ==="
find /root/xc/inst -name 'libkernel32*' -o -name 'libntdll*' -o -name 'libadvapi32*' 2>/dev/null | head
echo "(none above == missing)"
echo
echo "=== mingw-w64 def files available? ==="
ls /root/xc/mingw-w64/mingw-w64-crt/lib-common/kernel32.def /root/xc/mingw-w64/mingw-w64-crt/lib-common/ntdll.def 2>&1 | head
ls -d /root/xc/mingw-w64/mingw-w64-crt/lib-arm64 2>&1
echo
echo "=== DLL_ENTRY / target_cpu from config.status ==="
grep -o 'DLL_ENTRY[^,]*' /root/xc/bld/winsup/cygwin/Makefile | head -3
grep -n '^DLL_ENTRY\|^target_cpu\|^DEF_FILE\|^LIBSERVER\|^VERSION_OFILES' /root/xc/bld/winsup/cygwin/Makefile | head
echo
echo "=== link inputs present in build dir ==="
cd /root/xc/bld/winsup/cygwin
ls -la cygwin.sc msys.def winver.o sigfe.s 2>&1
ls -la /root/xc/bld/newlib/libc.a /root/xc/bld/newlib/libm.a
echo
echo "=== object count / list head ==="
find . -name '*.o' | wc -l
