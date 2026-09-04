#!/bin/bash
# Copy sources into WSL ext4 (fast) from the Windows-side local clones.
set -x
cd /root/xc
rm -rf gcc-src
git -c core.autocrlf=false clone --no-hardlinks --depth 1 --branch woarm64 --single-branch \
  file:///mnt/c/Users/crutkasLocal/.copilot/repos/gcc-woarm64 gcc-src 2>&1 | tail -3
cd gcc-src && git log -1 --format='GCC_HEAD=%H %s'
du -sh /root/xc/gcc-src
