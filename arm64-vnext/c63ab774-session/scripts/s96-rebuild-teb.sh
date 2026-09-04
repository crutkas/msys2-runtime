#!/bin/bash
# Rebuild + relink after the Windows-ARM64 TEB fix (tpidr_el0 -> x18).
set -u
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
export PYTHONDONTWRITEBYTECODE=1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1

find . -name '*.o' -delete
rm -f msys.def sigfe.s sigfe.o libdll.a new-msys-2.0.dll
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
timeout 3000 make -k -j12 INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error -D__MSYS__ $INC $IFLAGS" \
  CXXFLAGS="-g -O2 -Wno-error -D__MSYS__" > /root/xc/wl-teb.log 2>&1
echo "MAKE EXIT $?  objects=$(find . -name '*.o' | wc -l)  errors=$(grep -c 'error:' /root/xc/wl-teb.log)"
grep 'error:' /root/xc/wl-teb.log | sed 's/.*error: //' | sort -u | head -5

aarch64-pc-cygwin-gcc -c -g -O2 -D__MSYS__ $INC $IFLAGS \
  $R/math/aarch64/fenv_extern_aarch64.c -o fenv_aarch64.o 2>&1 | head -3

make --eval='po: ; @echo $(libdll_a_OBJECTS)' po 2>/dev/null | tr ' ' '\n' | grep -v '^$' | sort -u > /tmp/t_all.txt
: > /tmp/t_have.txt
while read -r o; do [ -f "$o" ] && echo "$o" >> /tmp/t_have.txt; done < /tmp/t_all.txt
echo "fenv_aarch64.o" >> /tmp/t_have.txt
rm -f libdll.a
xargs -a /tmp/t_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a

aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  /root/xc/bld/newlib/libm.a /root/xc/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map > /root/xc/link-teb.log 2>&1
echo "LINK EXIT $?  diagnostics=$(wc -c < /root/xc/link-teb.log) bytes"
cat /root/xc/link-teb.log | head -5

echo "=== verification ==="
printf 'tpidr_el0 left in DLL : %s (want 0)\n' "$(aarch64-pc-cygwin-objdump -d new-msys-2.0.dll 2>/dev/null | grep -c tpidr_el0)"
printf 'mov xN, x18 sites     : %s\n' "$(aarch64-pc-cygwin-objdump -d new-msys-2.0.dll 2>/dev/null | grep -cE 'mov\s+x[0-9]+, x18')"
ls -la new-msys-2.0.dll
sha256sum new-msys-2.0.dll | cut -c1-64

cp new-msys-2.0.dll /mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest/msys-2.0-teb.dll
echo "copied to Windows."
