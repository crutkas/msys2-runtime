#!/bin/bash
# Decisive test: can GCC target *-pc-msys at all?
G=/root/xc/gcc-src
echo "############ config.gcc: cygwin case exists? ############"
grep -n '\*-\*-cygwin\*\|x86_64-\*-cygwin\*\|aarch64-\*-cygwin\*' $G/gcc/config.gcc | head -10
echo
echo "############ config.gcc: ANY msys case? ############"
grep -cn 'msys' $G/gcc/config.gcc
echo "(0 == GCC has no msys target)"

echo
echo "############ live test: configure GCC for aarch64-pc-msys ############"
rm -rf /tmp/msystest && mkdir -p /tmp/msystest && cd /tmp/msystest
timeout 300 $G/configure --target=aarch64-pc-msys --prefix=/tmp/msystest/inst \
  --enable-languages=c --without-headers --with-newlib --disable-multilib \
  --disable-nls --disable-shared --disable-threads --disable-libssp \
  --disable-libgomp --disable-libatomic --disable-libquadmath \
  --disable-libstdcxx --disable-bootstrap --disable-werror > cfg.log 2>&1
echo "configure exit: $?"
echo "--- decisive lines ---"
grep -i 'not supported\|unsupported\|Unrecognized\|error' cfg.log | head -8
tail -4 cfg.log

echo
echo "############ binutils: does it know pe-aarch64 for msys? (same BFD either way) ############"
PATH=/root/xc/inst/bin:$PATH aarch64-pc-cygwin-ld -V 2>/dev/null | head -4

echo
echo "############ how does the runtime EXPECT __MSYS__ to be set? ############"
grep -rn '__MSYS__' /root/xc/w-link/runtime/winsup/cygwin/include/cygwin/version.h
echo "--- dcrt0.cc site ---"
sed -n '1096,1110p' /root/xc/w-link/runtime/winsup/cygwin/dcrt0.cc
