#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root/xc/runtime
echo "=== AC_PREREQ / AM_INIT ==="
grep -n 'AC_PREREQ\|AM_INIT_AUTOMAKE\|AC_NO_EXECUTABLES\|AC_PROG_CC\|AC_PROG_CXX\|LT_INIT' winsup/configure.ac | head -20
echo "=== host autotools ==="
for t in autoconf automake autoreconf aclocal libtoolize m4 perl makeinfo; do printf '%s: ' $t; (command -v $t && $t --version 2>/dev/null | head -1) || echo MISSING; done
echo "=== targ-include from our newlib configure ==="
ls /root/xc/build-newlib/targ-include 2>&1 | head
find /root/xc/build-newlib -maxdepth 3 -name 'targ-include' 2>/dev/null | head
echo "=== Makefile.am.common cflags_common ==="
grep -n 'cflags_common\|cxxflags_common' winsup/Makefile.am.common | head -20
