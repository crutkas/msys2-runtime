#!/bin/bash
set -x
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /root/xc/build-gcc2
make install-gcc > install.log 2>&1
echo "INSTALL_GCC_EXIT=$?"
tail -5 install.log
ls /root/xc/inst/bin | grep -E 'g\+\+|gcc$|cpp'
/root/xc/inst/bin/aarch64-pc-cygwin-g++ -v 2>&1 | tail -3

cd /root/xc
rm -rf mingw-w64
git -c core.autocrlf=false clone --no-hardlinks --depth 1 \
  file:///mnt/c/Users/crutkasLocal/.copilot/repos/mingw-w64 mingw-w64 2>&1 | tail -3
cd mingw-w64 && git log -1 --format='MINGW_HEAD=%H %s'
grep -n 'AC_NO_EXECUTABLES\|AC_PROG_CC\|AC_CANONICAL' mingw-w64-headers/configure.ac | head
