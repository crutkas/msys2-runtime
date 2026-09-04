#!/bin/bash
# Full winsup/cygwin build for aarch64-pc-cygwin.
# $1 = log suffix, $2 = "werror" | "nowerror"
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
export PYTHONDONTWRITEBYTECODE=1
SUF=${1:-x}
MODE=${2:-nowerror}
LOG=/root/xc/wb-$SUF.log
cd /root/xc/bld/winsup/cygwin || exit 1
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
if [ "$MODE" = "werror" ]; then
  EXTRA=""
else
  EXTRA='CFLAGS=-g -O2 -Wno-error'
fi
if [ "$MODE" = "werror" ]; then
  timeout 3000 make -k -j12 INCLUDES="$INC" > $LOG 2>&1
else
  # NOTE: $INC is appended to CFLAGS too, because the version.cc/windres rule
  # passes only $(CFLAGS) and would otherwise fail to find <cygwin/version.h>.
  # Additionally scripts/mkvers.sh only harvests "-I" flags, never "-isystem",
  # so the -isystem dirs are restated as -I. Natively this is masked by
  # /usr/include; cross it fails. Same family as the obsolete $(INCLUDES) bug.
  IFLAGS="-I/root/xc/runtime/winsup/cygwin/include -I/root/xc/bld/newlib/targ-include -I/root/xc/runtime/newlib/libc/include"
  timeout 3000 make -k -j12 INCLUDES="$INC" \
    CFLAGS="-g -O2 -Wno-error $INC $IFLAGS" CXXFLAGS="-g -O2 -Wno-error" > $LOG 2>&1
fi
echo "MAKE EXIT $?  (log $LOG)"
echo "=== objects built ==="
find /root/xc/bld/winsup/cygwin -name '*.o' | wc -l
echo "=== distinct error: lines ==="
grep 'error:' $LOG | sed 's/^.*error: //' | sort | uniq -c | sort -rn | head -30
echo "=== total error: line count ==="
grep -c 'error:' $LOG
echo "=== failing targets ==="
grep -o "\*\*\* \[[^]]*\] Error" $LOG | sort -u | head -40
