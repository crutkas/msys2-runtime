#!/bin/bash
# Capture toolchain manifest + copy build logs into session evidence.
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/1e64365a-8e29-4b6b-80ea-34408c4d868b/files/evidence
mkdir -p $E
{
  echo "=== aarch64-pc-cygwin toolchain manifest (2026-09-02) ==="
  echo "--- gcc -v ---";        aarch64-pc-cygwin-gcc -v 2>&1 | tail -4
  echo "--- g++ present ---";   aarch64-pc-cygwin-g++ --version 2>&1 | head -1
  echo "--- ld -V ---";         aarch64-pc-cygwin-ld -V 2>&1 | head -5
  echo "--- objdump -i (first targets) ---"; aarch64-pc-cygwin-objdump -i 2>&1 | head -8
  echo "--- w32api version ---"
  grep -m1 '__MINGW64_VERSION_STR' /root/xc/inst/aarch64-pc-cygwin/include/w32api/_mingw_mac.h 2>/dev/null
  echo "--- w32api header count ---"; find /root/xc/inst/aarch64-pc-cygwin/include/w32api -name '*.h' | wc -l
  echo "--- source HEADs ---"
  echo "gcc-woarm64: $(cd /root/xc/gcc-src && git rev-parse HEAD)"
  echo "msys2-runtime: $(cd /root/xc/runtime && git rev-parse HEAD)"
  echo "mingw-w64: $(cd /root/xc/mingw-w64 && git describe --tags 2>/dev/null || git rev-parse HEAD)"
  echo "--- object counts ---"
  echo "intended .o targets: $(grep -o '[a-zA-Z0-9_./-]*\.\$(OBJEXT)' /root/xc/bld/winsup/cygwin/Makefile | sort -u | wc -l)"
  echo "built .o (final run): $(find /root/xc/bld/winsup/cygwin -name '*.o' | wc -l)"
  echo "--- LP64 probe (empty output below == PASS) ---"
  cd /root/xc/t && aarch64-pc-cygwin-gcc -c probe2.c -o /dev/null \
    -isystem /root/xc/runtime/winsup/cygwin/include \
    -isystem /root/xc/bld/newlib/targ-include \
    -isystem /root/xc/runtime/newlib/libc/include 2>&1
  echo "(end probe)"
} > $E/toolchain-manifest.txt 2>&1
cp /root/xc/winsup-build.log  $E/build1-w32api-master-unfixed.log
cp /root/xc/winsup-build3.log $E/build3-w32api-v12-win64fix.log
cp /root/xc/winsup-build4.log $E/build4-plus-target-detection-fixes.log
cp /root/xc/winsup-build5.log $E/build5-warnings-nonfatal.log
cp /root/xc/bld/winsup/cygwin/cygwin.sc $E/generated-cygwin.sc 2>/dev/null
ls -la $E
