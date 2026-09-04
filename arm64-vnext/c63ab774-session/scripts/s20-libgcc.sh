#!/bin/bash
# Build target libgcc for aarch64-pc-cygwin.
# IMPORTANT: builds INSIDE /root/xc/build-gcc2 only. No `make install`, so
# /root/xc/inst is NOT modified (coordinator guardrail).
export PATH=/root/xc/inst/bin:$PATH
cd /root/xc/build-gcc2 || exit 1
timeout 2400 make -j12 all-target-libgcc > /root/xc/libgcc-build.log 2>&1
echo "MAKE EXIT $?"
grep -c 'Error\|error:' /root/xc/libgcc-build.log
tail -20 /root/xc/libgcc-build.log
echo "=== libgcc.a ==="
find /root/xc/build-gcc2 -name 'libgcc.a' -exec ls -la {} \;
