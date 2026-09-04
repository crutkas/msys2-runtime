#!/bin/bash
set -x
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=/root/xc/runtime
BLD=/root/xc/bld
cd $BLD/winsup
$SRC/winsup/configure \
  --host=aarch64-pc-cygwin --target=aarch64-pc-cygwin \
  --prefix=/root/xc/inst \
  --with-cross-bootstrap --disable-doc --disable-dumper \
  --with-msys2-runtime-commit=d890a845e992638a6f09560efacc26d15b3ffe6a \
  > cfg.log 2>&1
echo "WINSUP_CFG_EXIT=$?"
tail -30 cfg.log
echo "=== AM_CPPFLAGS chosen ==="
grep -m1 '^AM_CPPFLAGS' cygwin/Makefile 2>/dev/null
echo "=== target_cpu / conditionals ==="
grep -m1 '^target_cpu' cygwin/Makefile 2>/dev/null
grep -m1 'TARGET_AARCH64_TRUE' cygwin/Makefile 2>/dev/null
grep -m1 'TARGET_X86_64_TRUE' cygwin/Makefile 2>/dev/null
echo "=== config.log errors ==="
grep -n 'error:' config.log 2>/dev/null | head -10
