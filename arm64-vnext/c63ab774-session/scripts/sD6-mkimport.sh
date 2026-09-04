#!/bin/bash
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1

echo "=== LIBCOS the rule wants ==="
make --eval='pl: ; @echo $(LIBCOS)' pl 2>/dev/null | tr ' ' '\n' | grep -v '^$' | sort -u > /tmp/libcos.txt
wc -l < /tmp/libcos.txt
: > /tmp/libcos_have.txt
while read -r o; do [ -f "$o" ] && echo "$o" >> /tmp/libcos_have.txt; done < /tmp/libcos.txt
echo "present: $(wc -l < /tmp/libcos_have.txt)"
echo "missing:"; comm -23 /tmp/libcos.txt <(sort /tmp/libcos_have.txt)

echo
echo "=== NEW_FUNCTIONS / toolopts ==="
NEWF=$(make --eval='pn: ; @echo $(NEW_FUNCTIONS)' pn 2>/dev/null)
echo "NEW_FUNCTIONS count: $(echo $NEWF | wc -w)"

echo
echo "=== run mkimport directly ==="
rm -f libmsys-2.0.a
$R/scripts/mkimport --cpu=aarch64 \
  --ar=aarch64-pc-cygwin-ar --as=aarch64-pc-cygwin-as \
  --nm=aarch64-pc-cygwin-nm --objcopy=aarch64-pc-cygwin-objcopy \
  $NEWF libmsys-2.0.a msysdll.a $(cat /tmp/libcos_have.txt) 2>&1 | tail -6
echo "exit $?"
ls -la libmsys-2.0.a 2>&1
echo
echo "=== sanity: symbols ==="
for s in printf exit malloc main cygwin_crt0; do
  printf '  %-14s %s\n' "$s" "$(aarch64-pc-cygwin-nm libmsys-2.0.a 2>/dev/null | grep -cw "$s")"
done
