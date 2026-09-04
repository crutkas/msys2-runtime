#!/bin/bash
cd /root/xc/bld/winsup/cygwin
echo "=== libdll.a object variable ==="
grep -n '^libdll_a_OBJECTS\|^am_libdll_a_OBJECTS\|^libdll_a_AR\|^DLL_OFILES' Makefile | head
echo
echo "=== winver.o present? ==="
ls -la winver.o version.o 2>&1
echo
echo "=== count objects make expects for libdll.a ==="
make -n libdll.a 2>/dev/null | head -3
echo
echo "=== try make libdll.a ==="
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I/root/xc/runtime/winsup/cygwin/include -I/root/xc/bld/newlib/targ-include -I/root/xc/runtime/newlib/libc/include"
make libdll.a INCLUDES="$INC" CFLAGS="-g -O2 -Wno-error $INC $IFLAGS" CXXFLAGS="-g -O2 -Wno-error" 2>&1 | tail -15
ls -la libdll.a 2>&1
