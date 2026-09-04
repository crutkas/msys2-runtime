#!/bin/bash
# Rebuild malloc_wrapper.o with the AArch64 import-thunk decode, relink, retest.
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
IFLAGS="-I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include"

echo "=== rebuild mm/malloc_wrapper.o ==="
rm -f mm/malloc_wrapper.o
make mm/malloc_wrapper.o INCLUDES="$INC" \
  CFLAGS="-g -O2 -Wno-error -D__MSYS__ $INC $IFLAGS" \
  CXXFLAGS="-g -O2 -Wno-error -D__MSYS__" 2>&1 | tail -5
ls -la mm/malloc_wrapper.o 2>&1

echo
echo "=== rebuild libdll.a and relink ==="
rm -f libdll.a new-msys-2.0.dll
make --eval='po: ; @echo $(libdll_a_OBJECTS)' po 2>/dev/null | tr ' ' '\n' | grep -v '^$' | sort -u > /tmp/q_all.txt
: > /tmp/q_have.txt
while read -r o; do [ -f "$o" ] && echo "$o" >> /tmp/q_have.txt; done < /tmp/q_all.txt
echo "fenv_aarch64.o" >> /tmp/q_have.txt
xargs -a /tmp/q_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a

# NOTE: -Wl,--no-insert-timestamp is REQUIRED for a byte-reproducible link.
# Without it two identical relinks differ in 3 bytes (the PE timestamp).
# The upstream Makefile applies it via ${SOURCE_DATE_EPOCH:+...}.
aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--no-insert-timestamp \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  $L/bld/newlib/libm.a $L/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map > /root/xc/link-import.log 2>&1
echo "LINK EXIT $?  diagnostics bytes: $(wc -c < /root/xc/link-import.log)"
head -3 /root/xc/link-import.log

echo
echo "=== verify the new decode is in the image ==="
aarch64-pc-cygwin-objdump -d new-msys-2.0.dll 2>/dev/null \
  | grep -cE 'mov\s+w[0-9]+, #0x9000|9f00001f|movk' >/dev/null
printf 'malloc_wrapper.o size: %s\n' "$(stat -c%s mm/malloc_wrapper.o)"
printf 'DLL sha256: %s\n' "$(sha256sum new-msys-2.0.dll | cut -c1-64)"

cp new-msys-2.0.dll $D/msys-2.0.dll
cp new-msys-2.0.dll $D/msys-2.0-importfix.dll
echo "staged."
