#!/bin/bash
cd ~/xc
rm -rf build-ml && mkdir build-ml && cd build-ml
../gcc-woarm64/configure --target=aarch64-pc-cygwin --prefix=$HOME/xc/inst-ml \
  --enable-languages=c --without-headers --with-newlib \
  --enable-multilib --disable-nls --disable-shared --disable-threads \
  --disable-libssp --disable-libgomp --disable-libatomic --disable-libquadmath \
  --disable-libstdcxx --disable-bootstrap --disable-werror > cfg.log 2>&1
echo "CONFIGURE_EXIT=$?"
echo "=== TM_MULTILIB_CONFIG / MULTILIB_OPTIONS in generated gcc/Makefile ==="
grep -nE "^(TM_MULTILIB_CONFIG|MULTILIB_OPTIONS|MULTILIB_DIRNAMES)\s*=" gcc/Makefile
echo "=== generated multilib.h ==="
cd gcc && make multilib.h > /dev/null 2>&1; cat multilib.h 2>/dev/null | head -20