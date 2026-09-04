#!/bin/bash
set -e
cd ~/xc
rm -rf binutils-woarm64
git -c core.autocrlf=false clone --depth 1 --branch woarm64 --single-branch \
  file:///mnt/c/Users/crutkasLocal/.copilot/repos/binutils-woarm64 binutils-woarm64 2>&1 | tail -3
cd binutils-woarm64 && git log -1 --format='BINUTILS_HEAD=%H %s'
cd ~/xc && rm -rf build-binutils && mkdir build-binutils && cd build-binutils
../binutils-woarm64/configure --target=aarch64-pc-cygwin --prefix=$HOME/xc/inst \
  --disable-nls --disable-werror --disable-gdb --disable-sim --disable-libdecnumber \
  --disable-readline --with-sysroot=$HOME/xc/inst/aarch64-pc-cygwin \
  > cfg.log 2>&1
echo "BINUTILS_CONFIGURE_EXIT=$?"
tail -5 cfg.log
make -j6 > build.log 2>&1
echo "BINUTILS_MAKE_EXIT=$?"
tail -25 build.log
make install > install.log 2>&1
echo "BINUTILS_INSTALL_EXIT=$?"
ls $HOME/xc/inst/bin/ 2>&1