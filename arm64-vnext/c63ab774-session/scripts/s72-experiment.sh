#!/bin/bash
# ============================================================================
# DIAGNOSTIC EXPERIMENT -- NOT A FIX, NOT A SHIPPABLE CONFIGURATION.
#
# QUESTION IT ANSWERS: are the 10 remaining symbols the LAST blocker, or is
# something else hiding behind them?
#
# METHOD: remove ONLY the 10 EXPORT-LIST ENTRIES from cygwin.din. NO code is
# added, NO symbol is stubbed, NO implementation is faked. If a DLL appears it
# is DEFICIENT BY 10 EXPORTS and is NOT a real msys-2.0.dll.
#
# The 10, with why each is absent (measured):
#   msys_dll_init, msys_detach_dll  -- dcrt0.cc:1101 guards them with #ifdef __MSYS__,
#                                      undefined because we configure the CYGWIN triple
#   feenableexcept, fedisableexcept,
#   fegetexcept                     -- newlib has these for libm/machine/arm but NOT aarch64
#   fegetprec, fesetprec,
#   _fe_nomask_env                  -- libm/machine/shared_x86 only; x87 precision control,
#                                      meaningless on ARM64
#   _ctype_                         -- not emitted into libc.a under this newlib config
#   __alloca                        -- x86-only alias, no source anywhere in winsup
# ============================================================================
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1

cp -p $R/cygwin.din $R/cygwin.din.bak
for s in __alloca _ctype_ _fe_nomask_env fedisableexcept feenableexcept \
         fegetexcept fegetprec fesetprec msys_dll_init msys_detach_dll; do
  sed -i "/^${s}\([ \t]\|$\)/d" $R/cygwin.din
done
echo "cygwin.din lines: $(wc -l < $R/cygwin.din.bak) -> $(wc -l < $R/cygwin.din)"

rm -f msys.def sigfe.s sigfe.o
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$L/runtime/winsup/cygwin/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
make msys.def sigfe.o INCLUDES="$INC" CFLAGS="-g -O2 -Wno-error $INC $IFLAGS" \
     CXXFLAGS="-g -O2 -Wno-error" > /root/xc/exp-regen.log 2>&1
echo "regen exit $?  sigfe.s=$(stat -c%s sigfe.s 2>/dev/null) msys.def=$(stat -c%s msys.def 2>/dev/null)"

rm -f libdll.a new-msys-2.0.dll
xargs -a /tmp/objs_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a
echo "libdll.a = $(stat -c%s libdll.a)"

aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  /root/xc/bld/newlib/libm.a /root/xc/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map \
  > /root/xc/link-experiment.log 2>&1
echo "LINK EXIT $?"

echo
echo "=== remaining diagnostics ==="
printf 'cannot export : %s\n' "$(grep -c 'cannot export' /root/xc/link-experiment.log)"
printf 'undefined ref : %s\n' "$(grep -c 'undefined reference' /root/xc/link-experiment.log)"
printf 'reloc trunc   : %s\n' "$(grep -c 'relocation truncated' /root/xc/link-experiment.log)"
head -25 /root/xc/link-experiment.log

echo
echo "=== DID A DLL APPEAR? ==="
ls -la new-msys-2.0.dll 2>&1
