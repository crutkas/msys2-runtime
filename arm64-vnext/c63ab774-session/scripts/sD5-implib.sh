#!/bin/bash
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"

echo "=== build the import library ==="
make libmsys-2.0.a INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error -D__MSYS__ $INC $IFLAGS" \
  CXXFLAGS="-g -O2 -Wno-error -D__MSYS__" 2>&1 | tail -8
ls -la libmsys-2.0.a 2>&1

echo
echo "=== does it contain the expected startup / libc symbols? ==="
aarch64-pc-cygwin-nm libmsys-2.0.a 2>/dev/null | grep -cE ' T | I '
for s in printf exit malloc; do
  printf '  %-8s %s\n' "$s" "$(aarch64-pc-cygwin-nm libmsys-2.0.a 2>/dev/null | grep -cw "$s")"
done
