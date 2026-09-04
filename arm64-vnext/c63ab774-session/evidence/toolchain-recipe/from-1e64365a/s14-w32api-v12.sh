#!/bin/bash
set -x
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SYSINC=/root/xc/inst/aarch64-pc-cygwin/include
cd /root/xc
rm -rf mingw-w64
git -c core.autocrlf=false clone --no-hardlinks --branch v12.0.0 --single-branch \
  file:///mnt/c/Users/crutkasLocal/.copilot/repos/mingw-w64 mingw-w64 2>&1 | tail -3
cd mingw-w64
git log -1 --format='MINGW_V12_HEAD=%H %s'
echo "=== v12.0.0 corecrt.h mbstate_t (should be absent) ==="
grep -c 'mbstate_t' mingw-w64-headers/crt/corecrt.h || echo "0 (absent - good)"

# The ONE aarch64-specific mingw-w64 change needed:
sed -i 's|^#ifdef __x86_64__$|#if defined(__x86_64__) \|\| defined(__aarch64__)|' mingw-w64-headers/crt/_cygwin.h
grep -n -A2 'defined(__aarch64__)' mingw-w64-headers/crt/_cygwin.h
# and the POINTER_64_INT width in basetsd.h
sed -i 's|^#if (defined (__x86_64__) \|\| defined (__ia64__)) \&\& !(defined (__WIDL__) \|\| defined (RC_INVOKED))$|#if (defined (__x86_64__) \|\| defined (__ia64__) \|\| defined (__aarch64__)) \&\& !(defined (__WIDL__) \|\| defined (RC_INVOKED))|' mingw-w64-headers/crt/basetsd.h
sed -n '10p' mingw-w64-headers/crt/basetsd.h

rm -rf $SYSINC/w32api
cd /root/xc && rm -rf build-mwh && mkdir build-mwh && cd build-mwh
../mingw-w64/mingw-w64-headers/configure --host=aarch64-pc-cygwin \
  --prefix=/root/xc/inst/aarch64-pc-cygwin --includedir="$SYSINC/w32api" \
  --enable-sdk=all --with-default-msvcrt=msvcrt > cfg.log 2>&1
echo "MWH_CFG_EXIT=$?"
make install > inst.log 2>&1
echo "MWH_INSTALL_EXIT=$?"
find $SYSINC/w32api -name '*.h' | wc -l
grep -n 'mbstate_t' $SYSINC/w32api/corecrt.h | head || echo "corecrt.h has no mbstate_t - good"
