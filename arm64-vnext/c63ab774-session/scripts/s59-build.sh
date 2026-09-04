#!/bin/bash
# Build the COMBINED tree. Writes only under /root/xc/w-link.
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
export PYTHONDONTWRITEBYTECODE=1
L=/root/xc/w-link
LOG=/root/xc/wl-$1.log
cd $L/bld/winsup/cygwin || exit 1
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$L/runtime/winsup/cygwin/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
timeout 3000 make -k -j12 INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error $INC $IFLAGS" CXXFLAGS="-g -O2 -Wno-error" > $LOG 2>&1
echo "MAKE EXIT $?   log=$LOG"

echo "=== objects built (winsup/cygwin) ==="
find $L/bld/winsup/cygwin -name '*.o' | wc -l
echo "=== error: lines ==="
grep -c 'error:' $LOG
grep 'error:' $LOG | sed 's/^.*error: //' | sort | uniq -c | sort -rn | head -15
echo "=== failing targets ==="
grep -o "\*\*\* \[[^]]*\] Error" $LOG | sort -u
echo "=== generated artefacts ==="
ls -la sigfe.s sigfe.o msys.def autoload.o tlsoffsets cygwin.sc 2>&1
