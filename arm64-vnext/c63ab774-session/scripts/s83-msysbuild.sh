#!/bin/bash
# PRIORITY 1 RESOLUTION: build the MSYS flavour.
#
# Stock GCC 15.0.1 has NO msys target (config.gcc: 0 msys cases; configuring
# --target=aarch64-pc-msys leaves the gcc subdir unconfigured, so no compiler is
# produced). MSYS2 obtains __MSYS__ from their DOWNSTREAM GCC patches. Since
# __MSYS__ is only a preprocessor macro, define it directly: this yields msys
# FLAVOUR on the cygwin TRIPLE, which is the only combination buildable today.
set -u
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
export PYTHONDONTWRITEBYTECODE=1
L=/root/xc/w-link
LOG=/root/xc/wl-msys.log
cd $L/bld/winsup/cygwin || exit 1

# full rebuild: __MSYS__ changes 40 sites across 20 files
find . -name '*.o' -delete
rm -f msys.def sigfe.s sigfe.o libdll.a new-msys-2.0.dll

INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$L/runtime/winsup/cygwin/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
timeout 3000 make -k -j12 INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error -D__MSYS__ $INC $IFLAGS" \
  CXXFLAGS="-g -O2 -Wno-error -D__MSYS__" > $LOG 2>&1
echo "MAKE EXIT $?  log=$LOG"

echo "=== objects ==="; find . -name '*.o' | wc -l
echo "=== error: lines ==="; grep -c 'error:' $LOG
grep 'error:' $LOG | sed 's/^.*error: //' | sort | uniq -c | sort -rn | head -10
echo "=== failing targets ==="; grep -o "\*\*\* \[[^]]*\] Error" $LOG | sort -u
echo "=== artefacts ==="; ls -la sigfe.s sigfe.o msys.def autoload.o 2>&1 | tail -4

echo
echo "=== flavour check: which init symbol? ==="
aarch64-pc-cygwin-nm dcrt0.o 2>/dev/null | grep -iE ' T (msys|cygwin)_dll_init'
