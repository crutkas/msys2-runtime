#!/bin/bash
# Land the built-artifact hash manifest into the evidence directory.
# COPY, not move. Source is read-only. /root/xc is NOT touched.
set -u
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
SRC=/mnt/c/Users/crutkasLocal/.copilot/session-state/290c9aaf-a5d1-4941-86fd-c96d0f8d2262/files

cp -p "$SRC/built-artifact-hashes.txt"  "$D/built-artifact-hashes.txt"
cp -p "$SRC/capture-artifact-hashes.sh" "$D/capture-artifact-hashes.sh"
echo "=== landed ==="
ls -la "$D/built-artifact-hashes.txt" "$D/capture-artifact-hashes.sh"

echo
echo "=== byte-identical to source? ==="
for f in built-artifact-hashes.txt capture-artifact-hashes.sh; do
  a=$(sha256sum "$SRC/$f" | cut -c1-64)
  b=$(sha256sum "$D/$f"   | cut -c1-64)
  [ "$a" = "$b" ] && echo "  $f  IDENTICAL  $b" || echo "  $f  MISMATCH"
done

echo
echo "=== cross-check landed hashes against my RESULT.md size table ==="
fail=0
check() { # path bytes
  got=$(awk -v p="$1" '$1==p {print $2}' "$D/built-artifact-hashes.txt")
  if [ "$got" = "$2" ]; then echo "  OK   $1 = $2"
  else echo "  FAIL $1 : manifest=$got expected=$2"; fail=1; fi
}
check bld/newlib/libc.a 7208392
check bld/newlib/libm.a 1632850
check build-gcc2/aarch64-pc-cygwin/libgcc/libgcc.a 6677214
check implibs/lib/libkernel32.a 1385232
check implibs/lib/libntdll.a 1898462
check implibs/lib/libadvapi32.a 745316
check implibs/lib/libuser32.a 795740
check bld/winsup/cygwin/cygwin.sc 3729
check bld/winsup/cygwin/msys.def 40698
check bld/winsup/cygwin/sigfe.s 0
check bld/winsup/cygwin/libdll.a 31160252
check bld/winsup/cygwin/msysdll.a 1114462
[ $fail = 0 ] && echo "ALL 12 SIZES CORROBORATE RESULT.md" || echo "SIZE MISMATCH FOUND"

echo
echo "=== sigfe.s hash == sha256 of empty string? ==="
EMPTY=$(printf '' | sha256sum | cut -c1-64)
GOT=$(awk '$1=="bld/winsup/cygwin/sigfe.s" {print $3}' "$D/built-artifact-hashes.txt")
echo "  empty-string sha256 : $EMPTY"
echo "  sigfe.s manifest    : $GOT"
[ "$EMPTY" = "$GOT" ] && echo "  CONFIRMED: sigfe.s is cryptographically empty" || echo "  MISMATCH"
