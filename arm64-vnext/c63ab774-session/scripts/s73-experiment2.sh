#!/bin/bash
# Continue the DIAGNOSTIC EXPERIMENT: the 10th entry is an ALIAS line
#   cygwin.din:136   _alloca = __alloca NOSIGFE
# i.e. export `_alloca`, implemented by `__alloca` -- the x86 stack-probe helper,
# which has no ARM64 equivalent (AArch64 GCC emits inline sub/probe sequences).
# Still NO code added and NO symbol stubbed; only an export-list line removed.
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1

sed -i '/^_alloca = __alloca/d' $R/cygwin.din
echo "cygwin.din lines now: $(wc -l < $R/cygwin.din)  (original 1773)"

rm -f msys.def sigfe.s sigfe.o new-msys-2.0.dll
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$L/runtime/winsup/cygwin/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
make msys.def sigfe.o INCLUDES="$INC" CFLAGS="-g -O2 -Wno-error $INC $IFLAGS" \
     CXXFLAGS="-g -O2 -Wno-error" > /root/xc/exp-regen2.log 2>&1
echo "regen exit $?  sigfe.s=$(stat -c%s sigfe.s) msys.def=$(stat -c%s msys.def)"

rm -f libdll.a
xargs -a /tmp/objs_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a

aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  /root/xc/bld/newlib/libm.a /root/xc/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map \
  > /root/xc/link-experiment2.log 2>&1
RC=$?
echo "LINK EXIT $RC"
printf 'cannot export : %s\nundefined ref : %s\nreloc trunc   : %s\n' \
  "$(grep -c 'cannot export' /root/xc/link-experiment2.log)" \
  "$(grep -c 'undefined reference' /root/xc/link-experiment2.log)" \
  "$(grep -c 'relocation truncated' /root/xc/link-experiment2.log)"
echo "--- any diagnostics at all ---"
head -20 /root/xc/link-experiment2.log
echo
echo "############ DID A DLL APPEAR? ############"
ls -la new-msys-2.0.dll 2>&1
