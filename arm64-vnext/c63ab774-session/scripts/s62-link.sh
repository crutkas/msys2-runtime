#!/bin/bash
# LINK ATTEMPT in the COMBINED tree (both gendef + autoload fixes).
# Nothing stubbed: libdll.a is built from ONLY objects that genuinely compiled.
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
cd $L/bld/winsup/cygwin || exit 1

LIBGCC_DIR=/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc
IMPLIB=/root/xc/implibs/lib
NEWLIB=/root/xc/bld/newlib

make --eval='print-objs: ; @echo $(libdll_a_OBJECTS)' print-objs 2>/dev/null \
  | tr ' ' '\n' | grep -v '^$' | sort -u > /tmp/objs_all.txt
: > /tmp/objs_have.txt; : > /tmp/objs_missing.txt
while read -r o; do
  [ -f "$o" ] && echo "$o" >> /tmp/objs_have.txt || echo "$o" >> /tmp/objs_missing.txt
done < /tmp/objs_all.txt

echo "=== libdll.a object accounting ==="
printf 'intended : %s\npresent  : %s\nMISSING  : %s\n' \
  "$(wc -l < /tmp/objs_all.txt)" "$(wc -l < /tmp/objs_have.txt)" "$(wc -l < /tmp/objs_missing.txt)"
echo "--- missing ---"; cat /tmp/objs_missing.txt

rm -f libdll.a
xargs -a /tmp/objs_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a
echo; echo "=== libdll.a ==="; ls -la libdll.a

echo
echo "=== does libdll.a include sigfe.o? ==="
aarch64-pc-cygwin-ar t libdll.a | grep -c '^sigfe.o$'

echo
echo "=== LINK ==="
rm -f new-msys-2.0.dll
aarch64-pc-cygwin-g++ -g -O2 \
  -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o \
  /root/xc/bld/winsup/cygserver/libcygserver.a \
  $NEWLIB/libm.a $NEWLIB/libc.a \
  -L$LIBGCC_DIR -L$IMPLIB \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map \
  > /root/xc/link-combined.log 2>&1
echo "LINK EXIT $?"

echo
echo "=== diagnostics summary ==="
printf 'cannot export        : %s\n' "$(grep -c 'cannot export' /root/xc/link-combined.log)"
printf 'undefined reference  : %s\n' "$(grep -c 'undefined reference' /root/xc/link-combined.log)"
grep -o "undefined reference to \`[^']*'" /root/xc/link-combined.log | sed "s/.*\`//; s/'//" | sort -u > /tmp/undef_c.txt
grep -o "cannot export [A-Za-z0-9_@]*" /root/xc/link-combined.log | awk '{print $3}' | sort -u > /tmp/cantexp_c.txt
printf 'unique undefined     : %s\n' "$(wc -l < /tmp/undef_c.txt)"
printf 'unique cannot-export : %s\n' "$(wc -l < /tmp/cantexp_c.txt)"
echo "--- first 40 raw diagnostics ---"
head -40 /root/xc/link-combined.log
echo
echo "=== DID A DLL APPEAR? ==="
ls -la new-msys-2.0.dll 2>&1
