#!/bin/bash
# The DLL link uses -nostdlib and only needs -lgcc, not crtbegin/crtend.
# all-target-libgcc failed building extra_parts (crtbegin.o from
# config/i386/cygming-crtbegin.c).  Build just the archive.
export PATH=/root/xc/inst/bin:$PATH
cd /root/xc/build-gcc2/aarch64-pc-cygwin/libgcc || exit 1
timeout 1800 make -j12 libgcc.a > /root/xc/libgcc-a.log 2>&1
echo "MAKE EXIT $?"
echo "=== error summary ==="
grep 'error:' /root/xc/libgcc-a.log | sed 's/^.*error: //' | sort | uniq -c | sort -rn | head -15
echo "=== failing files ==="
grep -o "\*\*\* \[[^]]*\] Error" /root/xc/libgcc-a.log | sort -u | head
echo "=== libgcc.a ==="
ls -la libgcc.a 2>&1
