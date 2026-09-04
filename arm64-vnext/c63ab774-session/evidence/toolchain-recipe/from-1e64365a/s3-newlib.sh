#!/bin/bash
set -x
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root/xc
rm -rf build-newlib && mkdir build-newlib && cd build-newlib
../runtime/newlib/configure \
  --host=aarch64-pc-cygwin --target=aarch64-pc-cygwin \
  --prefix=/root/xc/inst \
  --enable-newlib-mb --enable-newlib-multithread \
  > cfg.log 2>&1
echo "NEWLIB_CONFIGURE_EXIT=$?"
tail -25 cfg.log
echo "=== newlib.h generated? ==="
find /root/xc/build-newlib -maxdepth 2 -name 'newlib.h' -o -maxdepth 2 -name '_newlib_version.h' | head
echo "=== config.log tail if failed ==="
[ -f config.log ] && tail -30 config.log
