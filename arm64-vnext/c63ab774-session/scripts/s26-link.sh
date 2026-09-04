#!/bin/bash
# DIAGNOSTIC LINK ATTEMPT for a native ARM64 msys-2.0.dll.
#
# HONESTY NOTE: nothing is stubbed. libdll.a is built from ONLY the object files
# that genuinely compiled. Objects that do not exist (autoload.o, the 10
# aarch64/*.S routines, an empty sigfe.s) are simply ABSENT, so every symbol they
# would have defined shows up in the undefined list. That list is the deliverable.
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
cd /root/xc/bld/winsup/cygwin || exit 1

LIBGCC_DIR=/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc
IMPLIB=/root/xc/implibs/lib
NEWLIB=/root/xc/bld/newlib

# --- 1. expand the object list automake intended for libdll.a ---
make --eval='print-objs: ; @echo $(libdll_a_OBJECTS)' print-objs 2>/dev/null \
  | tr ' ' '\n' | grep -v '^$' | sort -u > /tmp/dll_objs_all.txt
TOTAL=$(wc -l < /tmp/dll_objs_all.txt)

: > /tmp/dll_objs_have.txt
: > /tmp/dll_objs_missing.txt
while read -r o; do
  if [ -f "$o" ]; then echo "$o" >> /tmp/dll_objs_have.txt
  else echo "$o" >> /tmp/dll_objs_missing.txt; fi
done < /tmp/dll_objs_all.txt
HAVE=$(wc -l < /tmp/dll_objs_have.txt)
MISS=$(wc -l < /tmp/dll_objs_missing.txt)

echo "=== libdll.a object accounting ==="
echo "intended : $TOTAL"
echo "present  : $HAVE"
echo "MISSING  : $MISS"
echo "--- missing objects ---"
cat /tmp/dll_objs_missing.txt

# --- 2. archive only the real objects ---
rm -f libdll.a
xargs -a /tmp/dll_objs_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a
echo
echo "=== libdll.a ==="; ls -la libdll.a

# --- 3. the real link recipe from Makefile.am:651-663 ---
echo
echo "=== LINK ATTEMPT ==="
set -x
aarch64-pc-cygwin-g++ -g -O2 \
  -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o \
  ../cygserver/libcygserver.a \
  $NEWLIB/libm.a \
  $NEWLIB/libc.a \
  -L$LIBGCC_DIR -L$IMPLIB \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map \
  > /root/xc/link1.log 2>&1
RC=$?
set +x
echo "LINK EXIT $RC"
echo
echo "=== raw linker diagnostics (first 40) ==="
head -40 /root/xc/link1.log
echo
echo "=== undefined symbol count ==="
grep -o "undefined reference to \`[^']*'" /root/xc/link1.log \
  | sed "s/.*\`//; s/'//" | sort -u > /tmp/undef.txt
wc -l < /tmp/undef.txt
echo "=== undefined symbols (unique, sorted) ==="
cat /tmp/undef.txt
echo
echo "=== resulting DLL, if any ==="
ls -la new-msys-2.0.dll 2>&1
