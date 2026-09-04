#!/bin/bash
# Generate aarch64 PE import libraries for kernel32 and ntdll from mingw-w64's
# lib-common/*.def.in, using exactly the preprocessing rule mingw-w64-crt uses
# for libarm64 (Makefile.am:3807-3808), then dlltool.
# Output goes to /root/xc/implibs -- /root/xc/inst is NOT touched.
set -e
export PATH=/root/xc/inst/bin:$PATH
M=/root/xc/mingw-w64/mingw-w64-crt
OUT=/root/xc/implibs
mkdir -p $OUT/def $OUT/lib

echo "=== dlltool supported machines ==="
aarch64-pc-cygwin-dlltool --help 2>&1 | grep -i 'machine\|arm64\|possible' | head -5

for d in kernel32 ntdll advapi32 user32; do
  if [ ! -f $M/lib-common/$d.def.in ]; then echo "SKIP $d (no def.in)"; continue; fi
  cpp -x c $M/lib-common/$d.def.in -Wp,-w -undef -P \
      -I$M/def-include -DDEF_ARM64 > $OUT/def/$d.def
  aarch64-pc-cygwin-dlltool -m arm64 \
      -d $OUT/def/$d.def -l $OUT/lib/lib$d.a
  echo "built lib$d.a  ($(grep -c . $OUT/def/$d.def) def lines)"
done

echo
echo "=== results ==="
ls -la $OUT/lib
echo
echo "=== sanity: object format inside libkernel32.a ==="
aarch64-pc-cygwin-objdump -f $OUT/lib/libkernel32.a 2>/dev/null | head -6
