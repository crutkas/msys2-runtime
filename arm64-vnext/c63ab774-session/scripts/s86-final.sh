#!/bin/bash
# DEFINITIVE COMBINED BUILD - everything, honest configuration, zero removed exports.
#
#  1. autoload .balign fix            (session 200edc20, already in w-link/runtime)
#  2. gendef AArch64 backend          -> use w-orphans/gendef (md5 b4e4739b, LF, SUPERSET
#                                        with conditional-block support; NOT gendef2, which
#                                        fails perl -c at line 47)
#  3. arch-conditioned cygwin.din     (w-orphans, 1793 lines, #ifndef __aarch64__ guards)
#  4. fenv_aarch64.c                  (feenableexcept/fedisableexcept/fegetexcept)
#  5. .idata 8-byte alignment         (MY fix in cygwin.sc.in -- clears the 10 reloc
#                                        truncations that blocked the orphan session)
#  6. -D__MSYS__                      (MY finding: msys FLAVOUR. Stock GCC has NO msys
#                                        TARGET, so the cygwin triple + __MSYS__ is the only
#                                        buildable combination. Resolves msys_dll_init /
#                                        msys_detach_dll, which the conditioned .din retains.)
set -u
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
export PYTHONDONTWRITEBYTECODE=1
L=/root/xc/w-link
O=/root/xc/w-orphans
R=$L/runtime/winsup/cygwin

echo "=== 2. orphan gendef (verified perl -c OK, LF-clean) ==="
cp -p $O/gendef $R/scripts/gendef; chmod +x $R/scripts/gendef
printf '   md5 %s  %s lines  CRLF=%s  ' "$(md5sum $R/scripts/gendef | cut -d' ' -f1)" \
  "$(wc -l < $R/scripts/gendef)" "$(grep -c $'\r$' $R/scripts/gendef)"
perl -c $R/scripts/gendef 2>&1 | tail -1

echo "=== 3. arch-conditioned cygwin.din ==="
cp -p $O/cygwin.din $R/cygwin.din
printf '   %s lines  md5 %s\n' "$(wc -l < $R/cygwin.din)" "$(md5sum $R/cygwin.din | cut -d' ' -f1)"

echo "=== 4. fenv_aarch64.c into the tree ==="
cp -p $O/fenv_aarch64.c $R/math/aarch64/fenv_aarch64.c
ls -la $R/math/aarch64/

echo "=== 5. confirm .idata alignment fix present ==="
grep -c 'ALIGN(8)' $R/cygwin.sc.in

echo
echo "=== FULL REBUILD with -D__MSYS__ ==="
cd $L/bld/winsup/cygwin || exit 1
find . -name '*.o' -delete
rm -f msys.def sigfe.s sigfe.o libdll.a new-msys-2.0.dll cygwin.sc
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
timeout 3000 make -k -j12 INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error -D__MSYS__ $INC $IFLAGS" \
  CXXFLAGS="-g -O2 -Wno-error -D__MSYS__" > /root/xc/wl-final.log 2>&1
echo "MAKE EXIT $?"
printf 'objects   : %s\n' "$(find . -name '*.o' | wc -l)"
printf 'error:    : %s\n' "$(grep -c 'error:' /root/xc/wl-final.log)"
grep 'error:' /root/xc/wl-final.log | sed 's/.*error: //' | sort -u | head -5
printf 'sigfe.s   : %s bytes\n' "$(stat -c%s sigfe.s 2>/dev/null)"
printf 'msys.def  : %s bytes\n' "$(stat -c%s msys.def 2>/dev/null)"
printf 'cygwin.sc : %s bytes\n' "$(stat -c%s cygwin.sc 2>/dev/null)"
echo "flavour   : $(aarch64-pc-cygwin-nm dcrt0.o 2>/dev/null | grep -oE '(msys|cygwin)_dll_init' | head -1)"
echo "EXPORTS in msys.def: $(grep -c '^  ' msys.def 2>/dev/null)"
