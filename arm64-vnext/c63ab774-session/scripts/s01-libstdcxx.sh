#!/bin/bash
# Configure freestanding libstdc++-v3 for aarch64-pc-cygwin.
# Installs ONLY into /root/xc/sysroot-cxx  (NOT /root/xc/inst) per coordinator guardrail.
set -x
export PATH=/root/xc/inst/bin:$PATH
rm -rf /root/xc/build-libstdcxx
mkdir -p /root/xc/build-libstdcxx
cd /root/xc/build-libstdcxx
/root/xc/gcc-src/libstdc++-v3/configure \
  --host=aarch64-pc-cygwin --build=aarch64-unknown-linux-gnu \
  --prefix=/root/xc/sysroot-cxx \
  --disable-hosted-libstdcxx --disable-shared --disable-nls \
  --disable-libstdcxx-verbose --disable-multilib --with-newlib \
  > cfg.log 2>&1
echo "CONFIGURE EXIT $?"
tail -20 cfg.log
ls -la include 2>/dev/null | head
