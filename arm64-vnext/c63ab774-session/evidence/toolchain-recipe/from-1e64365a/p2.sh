#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root/xc/runtime
echo "=== toplevel configure present? ==="
ls -l configure configure.ac 2>&1
echo "=== winsup ==="
ls -l winsup/configure winsup/configure.ac 2>&1
echo "=== newlib ==="
ls -l newlib/configure newlib/configure.ac 2>&1
echo "=== newlib.hin defines that get set (grep newlib/configure.ac for AC_DEFINE) ==="
grep -c 'AC_DEFINE' newlib/configure.ac 2>&1
echo "=== does newlib configure.ac / config.sub accept aarch64-pc-cygwin? ==="
./config.sub aarch64-pc-cygwin 2>&1
echo "CONFIG_SUB_EXIT=$?"
echo "=== newlib/configure.host cygwin/aarch64 handling ==="
grep -n 'cygwin' newlib/libc/sys/configure.host 2>/dev/null | head
grep -n 'aarch64' newlib/configure.host 2>/dev/null | head
grep -n 'cygwin' newlib/configure.host 2>/dev/null | head
echo "=== winsup/configure.ac target cases ==="
grep -n 'x86_64\|aarch64\|target_cpu\|TARGET_X86_64' winsup/configure.ac | head -20
