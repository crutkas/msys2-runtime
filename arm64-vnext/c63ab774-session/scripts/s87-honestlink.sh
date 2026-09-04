#!/bin/bash
# HONEST LINK: zero removed exports, arch-conditioned .din, msys flavour.
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1

echo "=== regenerate msys.def + sigfe.o from the reconciled .din ==="
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
make msys.def sigfe.o INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error -D__MSYS__ $INC $IFLAGS" \
  CXXFLAGS="-g -O2 -Wno-error -D__MSYS__" 2>&1 | tail -3
printf 'msys.def %s B   sigfe.s %s B   sigfe.o %s B\n' \
  "$(stat -c%s msys.def 2>/dev/null)" "$(stat -c%s sigfe.s 2>/dev/null)" "$(stat -c%s sigfe.o 2>/dev/null)"

echo "=== compile fenv external definitions ==="
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"
sed 's/\r$//' /mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/fenv_extern_aarch64.c \
  > $R/math/aarch64/fenv_extern_aarch64.c
aarch64-pc-cygwin-gcc -c -g -O2 -D__MSYS__ $INC $IFLAGS \
  $R/math/aarch64/fenv_extern_aarch64.c -o fenv_aarch64.o 2>&1 | head -8
printf 'fenv_aarch64.o : %s bytes\n' "$(stat -c%s fenv_aarch64.o 2>/dev/null)"
aarch64-pc-cygwin-nm fenv_aarch64.o 2>/dev/null | grep ' T '

echo
echo "=== assemble the object list ==="
make --eval='po: ; @echo $(libdll_a_OBJECTS)' po 2>/dev/null \
  | tr ' ' '\n' | grep -v '^$' | sort -u > /tmp/f_all.txt
: > /tmp/f_have.txt; : > /tmp/f_miss.txt
while read -r o; do [ -f "$o" ] && echo "$o" >> /tmp/f_have.txt || echo "$o" >> /tmp/f_miss.txt; done < /tmp/f_all.txt
echo "fenv_aarch64.o" >> /tmp/f_have.txt
printf 'intended %s  present %s (+fenv)  missing %s\n' \
  "$(wc -l < /tmp/f_all.txt)" "$(wc -l < /tmp/f_have.txt)" "$(wc -l < /tmp/f_miss.txt)"
cat /tmp/f_miss.txt

rm -f libdll.a new-msys-2.0.dll
xargs -a /tmp/f_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a
printf 'libdll.a : %s bytes\n' "$(stat -c%s libdll.a)"

echo
echo "############ HONEST LINK -- NOTHING REMOVED, NOTHING STUBBED ############"
aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  /root/xc/bld/newlib/libm.a /root/xc/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map \
  > /root/xc/link-honest.log 2>&1
echo "LINK EXIT $?"
printf 'cannot export : %s\n' "$(grep -c 'cannot export' /root/xc/link-honest.log)"
printf 'undefined ref : %s\n' "$(grep -c 'undefined reference' /root/xc/link-honest.log)"
printf 'reloc trunc   : %s\n' "$(grep -c 'relocation truncated' /root/xc/link-honest.log)"
echo "--- diagnostics ---"; head -20 /root/xc/link-honest.log
echo
echo "############ DLL? ############"
ls -la new-msys-2.0.dll 2>&1
