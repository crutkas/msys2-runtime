#!/bin/bash
echo "=== mingw-w64 checkout layout ==="
ls /root/xc/mingw-w64 2>&1 | head -20
echo "--- crt def dirs ---"
ls -d /root/xc/mingw-w64/mingw-w64-crt/lib* 2>&1 | head -20
echo "--- kernel32/ntdll defs anywhere ---"
find /root/xc/mingw-w64 -name 'kernel32.def*' -o -name 'ntdll.def*' 2>/dev/null | head -10
echo
echo "=== winver.o / version.o ==="
ls -la /root/xc/bld/winsup/cygwin/winver.o /root/xc/bld/winsup/cygwin/version.o /root/xc/bld/winsup/cygwin/version.cc 2>&1
echo
echo "=== cygserver lib ==="
ls -la /root/xc/bld/winsup/cygserver/libcygserver.a 2>&1
echo
echo "=== gcc build dir: target libgcc present? ==="
ls -d /root/xc/build-gcc2/aarch64-pc-cygwin 2>&1
find /root/xc/build-gcc2 -name 'libgcc.a' 2>/dev/null | head
