#!/bin/bash
set -x
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SYSINC=/root/xc/inst/aarch64-pc-cygwin/include
mkdir -p "$SYSINC"
cd /root/xc
rm -rf build-mwh && mkdir build-mwh && cd build-mwh
../mingw-w64/mingw-w64-headers/configure \
  --host=aarch64-pc-cygwin \
  --prefix=/root/xc/inst/aarch64-pc-cygwin \
  --includedir="$SYSINC/w32api" \
  --enable-sdk=all \
  --with-default-msvcrt=msvcrt \
  > cfg.log 2>&1
echo "MWH_CONFIGURE_EXIT=$?"
tail -15 cfg.log
make install > inst.log 2>&1
echo "MWH_INSTALL_EXIT=$?"
tail -10 inst.log
echo "=== w32api header count ==="
find "$SYSINC/w32api" -name '*.h' | wc -l
ls "$SYSINC/w32api" | head -20
echo "=== _mingw.h arch section ==="
grep -n 'aarch64\|_M_ARM64\|__CYGWIN__' "$SYSINC/w32api/_mingw.h" | head -20
