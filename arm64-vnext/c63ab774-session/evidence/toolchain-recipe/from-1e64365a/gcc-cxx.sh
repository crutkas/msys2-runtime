#!/bin/bash
# Stage A: rebuild the cross GCC with C++ enabled so we get cc1plus.
# winsup/cygwin is overwhelmingly C++ (.cc), so a C-only cross cannot compile it.
# We deliberately keep --without-headers --with-newlib (the proven-good config from
# the prior session) and only build all-gcc: that yields cc1/cc1plus + drivers
# without needing a target libc.
set -o pipefail
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root/xc
rm -rf build-gcc2 && mkdir -p build-gcc2 && cd build-gcc2
TGT=aarch64-pc-cygwin
PREFIX=/root/xc/inst
../gcc-src/configure \
  --target=$TGT --prefix="$PREFIX" \
  --enable-languages=c,c++ \
  --without-headers --with-newlib \
  --disable-multilib --disable-nls --disable-shared --disable-threads \
  --disable-libssp --disable-libgomp --disable-libatomic --disable-libquadmath \
  --disable-libstdcxx --disable-bootstrap --disable-werror \
  > configure.log 2>&1
echo "CONFIGURE_EXIT=$?"
tail -15 configure.log
ulimit -u 4096
time make -j12 all-gcc > build.log 2>&1
echo "MAKE_ALLGCC_EXIT=$?"
tail -30 build.log
echo "=== cc1plus present? ==="
find /root/xc/build-gcc2/gcc -maxdepth 1 -name 'cc1*' -o -maxdepth 1 -name 'xg++' | head
