#!/bin/bash
I=/root/xc/gcc-src/libstdc++-v3/include
L=/root/xc/gcc-src/libstdc++-v3/libsupc++
echo "=== does bits/version.h exist pre-generated? ==="
ls -la $I/bits/version.h $I/bits/version.tpl $I/bits/version.def 2>&1
echo
echo "=== bits/exception.h source ==="
ls -la $L/exception.h 2>&1
echo
echo "=== c++config template @VARS@ ==="
grep -o '@[A-Za-z_][A-Za-z0-9_]*@' $I/bits/c++config | sort -u
echo
echo "=== how include/Makefile.am builds c++config.h ==="
grep -n -A40 '^\${host_builddir}/c++config.h' $I/Makefile.am | head -50
