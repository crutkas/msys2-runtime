#!/bin/bash
# Scratch clone of msys2-runtime at the pinned commit + apply the sealed ARM64 port patch.
set -x
BK=/mnt/c/Users/crutkasLocal/.copilot/session-state/724ee2e9-51c7-40d7-b303-e6fcbfe78490/files/arm64-port-backup-2026-09-02
cd /root/xc
rm -rf runtime
git -c core.autocrlf=false clone --no-hardlinks --no-checkout \
  file:///mnt/c/Users/crutkasLocal/.copilot/repos/msys2-runtime runtime 2>&1 | tail -3
cd runtime
git -c core.autocrlf=false checkout -q d890a845e992638a6f09560efacc26d15b3ffe6a 2>&1 | tail -3
echo "RUNTIME_HEAD=$(git rev-parse HEAD)"
# strip CR from the patch defensively, then apply
tr -d '\r' < "$BK/arm64-port.patch" > /root/xc/arm64-port.lf.patch
git -c core.autocrlf=false apply --stat /root/xc/arm64-port.lf.patch | tail -5
git -c core.autocrlf=false apply -v /root/xc/arm64-port.lf.patch 2>&1 | tail -20
echo "PATCH_APPLY_EXIT=$?"
mkdir -p winsup/cygwin/math/aarch64
tr -d '\r' < "$BK/untracked/winsup/cygwin/math/aarch64/longdouble.c" > winsup/cygwin/math/aarch64/longdouble.c
ls -l winsup/cygwin/math/aarch64/
git -c core.autocrlf=false diff --stat | tail -5
