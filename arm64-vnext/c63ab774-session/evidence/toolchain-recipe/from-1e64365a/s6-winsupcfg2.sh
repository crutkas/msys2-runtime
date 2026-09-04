#!/bin/bash
set -x
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=/root/xc/runtime
BLD=/root/xc/bld
rm -rf $BLD/winsup && mkdir -p $BLD/winsup && cd $BLD/winsup
# Pre-seed the two AC_CHECK_LIB results that msys2-runtime performs unconditionally
# (for the 'dumper' utility's BFD_LIBS) -- they are link tests and therefore illegal
# after AC_NO_EXECUTABLES in a cross-bootstrap configuration.
ac_cv_lib_sframe_sframe_decode=no \
ac_cv_lib_zstd_ZSTD_isError=no \
$SRC/winsup/configure \
  --host=aarch64-pc-cygwin --target=aarch64-pc-cygwin \
  --prefix=/root/xc/inst \
  --with-cross-bootstrap --disable-doc --disable-dumper \
  --with-msys2-runtime-commit=d890a845e992638a6f09560efacc26d15b3ffe6a \
  > cfg.log 2>&1
echo "WINSUP_CFG_EXIT=$?"
tail -20 cfg.log
echo "=== generated makefiles ==="
ls cygwin/Makefile 2>&1
grep -m1 '^AM_CPPFLAGS' cygwin/Makefile 2>/dev/null
grep -m1 '^target_cpu' cygwin/Makefile 2>/dev/null
grep -m1 'TARGET_AARCH64_TRUE = ' cygwin/Makefile 2>/dev/null
grep -m1 'TARGET_X86_64_TRUE = ' cygwin/Makefile 2>/dev/null
