#!/bin/bash
echo "=== libgcc/config.host : cygwin cases ==="
grep -n -B6 -A14 'cygwin\*' /root/xc/gcc-src/libgcc/config.host | head -70
echo
echo "=== aarch64 cases in libgcc/config.host ==="
grep -n 'aarch64' /root/xc/gcc-src/libgcc/config.host | head -20
