#!/bin/bash
# Can we get msys FLAVOUR without an msys TRIPLE, by defining __MSYS__?
# __MSYS__ is only a preprocessor macro; stock GCC has no msys target, so MSYS2
# must predefine it via their downstream GCC patches. Test the direct route.
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
cd $L/bld/winsup/cygwin || exit 1

echo "############ every __MSYS__ site and what it controls ############"
grep -rn '#ifdef __MSYS__\|#if defined *(__MSYS__)\|#ifndef __MSYS__' $L/runtime/winsup \
  --include=*.cc --include=*.c --include=*.h --include=*.in 2>/dev/null \
  | sed "s|$L/runtime/winsup/||" | head -30

echo
echo "############ does -D__MSYS__ change DLL naming / ABI? ############"
sed -n '508,520p' $L/runtime/winsup/cygwin/include/cygwin/version.h
sed -n '530,540p' $L/runtime/winsup/cygwin/include/cygwin/version.h

echo
echo "############ TEST BUILD: dcrt0.o with -D__MSYS__ ############"
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$L/runtime/winsup/cygwin/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
cp -p dcrt0.o /tmp/dcrt0.cygwin.o 2>/dev/null
rm -f dcrt0.o
make dcrt0.o INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error $INC $IFLAGS" \
  CXXFLAGS="-g -O2 -Wno-error -D__MSYS__" > /tmp/msysbuild.log 2>&1
echo "exit $?"
grep -c 'error:' /tmp/msysbuild.log
grep 'error:' /tmp/msysbuild.log | head -5
echo "--- does it now define msys_dll_init? ---"
aarch64-pc-cygwin-nm dcrt0.o 2>/dev/null | grep -i 'msys_dll_init\|cygwin_dll_init'
