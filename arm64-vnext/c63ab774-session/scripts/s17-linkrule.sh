#!/bin/bash
cd /root/xc/bld/winsup/cygwin
echo "=== dll link rule in Makefile.am ==="
grep -n -B4 -A30 'new-msys-2.0.dll:' /root/xc/runtime/winsup/cygwin/Makefile.am | head -60
echo
echo "=== LDFLAGS / DLL_LDFLAGS in generated Makefile ==="
grep -n '^DLL_LDFLAGS\|^msys_2_0_dll\|^new_msys\|^LIBS =\|^DLL_IMPORTS' Makefile | head -20
