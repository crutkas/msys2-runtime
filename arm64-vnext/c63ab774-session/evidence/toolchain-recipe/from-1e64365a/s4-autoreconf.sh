#!/bin/bash
set -x
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SRC=/root/xc/runtime
BLD=/root/xc/bld
ls -l $SRC/install-sh $SRC/missing $SRC/compile $SRC/config.sub 2>&1

cd $SRC/winsup
autoreconf -fi -I . > /root/xc/autoreconf.log 2>&1
echo "AUTORECONF_EXIT=$?"
tail -20 /root/xc/autoreconf.log
ls -l $SRC/winsup/configure 2>&1

rm -rf $BLD && mkdir -p $BLD/newlib $BLD/winsup

# --- newlib ---
cd $BLD/newlib
$SRC/newlib/configure --host=aarch64-pc-cygwin --target=aarch64-pc-cygwin \
  --prefix=/root/xc/inst --enable-newlib-mb --enable-newlib-multithread \
  > cfg.log 2>&1
echo "NEWLIB_CFG_EXIT=$?"
tail -5 cfg.log
make stmp-targ-include > targinc.log 2>&1
echo "TARG_INCLUDE_EXIT=$?"
tail -15 targinc.log
ls targ-include 2>&1 | head
find targ-include -name '*.h' 2>/dev/null | wc -l
