#!/bin/bash
# Build newlib (libc.a / libm.a) for aarch64-pc-cygwin.
export PATH=/root/xc/inst/bin:$PATH
cd /root/xc/bld/newlib || exit 1
timeout 2400 make -j12 > /root/xc/newlib-build.log 2>&1
echo "MAKE EXIT $?"
echo "=== error lines ==="
grep -n 'Error\|error:' /root/xc/newlib-build.log | head -40
echo "=== libs ==="
find /root/xc/bld/newlib -name 'lib*.a' -exec ls -la {} \;
