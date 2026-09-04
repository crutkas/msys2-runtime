#!/bin/bash
# Build the COMBINED tree /root/xc/w-link from both fix trees.
# Preserved assets /root/xc/{inst,runtime,bld} are NOT touched (read-only sources).
set -u
A=/root/xc/w-autoload
G=/root/xc/w-gendef
L=/root/xc/w-link

rm -rf $L
mkdir -p $L
echo "=== copying w-autoload (full tree: runtime + bld) ==="
cp -a $A/runtime $L/runtime
cp -a $A/bld     $L/bld
echo "copied."

echo
echo "=== install the gendef AArch64 backend from w-gendef ==="
cp -p $G/gendef $L/runtime/winsup/cygwin/scripts/gendef
chmod +x $L/runtime/winsup/cygwin/scripts/gendef
printf 'gendef now: %s lines\n' "$(wc -l < $L/runtime/winsup/cygwin/scripts/gendef)"
grep -c 'aarch64' $L/runtime/winsup/cygwin/scripts/gendef

echo
echo "=== install the CORRECT tlsoffsets (59-line; the generated one is broken on AArch64) ==="
printf 'before: %s bytes / %s lines\n' "$(stat -c%s $L/bld/winsup/cygwin/tlsoffsets)" "$(wc -l < $L/bld/winsup/cygwin/tlsoffsets)"
cp -p $G/tlsoffsets $L/bld/winsup/cygwin/tlsoffsets
printf 'after : %s bytes / %s lines\n' "$(stat -c%s $L/bld/winsup/cygwin/tlsoffsets)" "$(wc -l < $L/bld/winsup/cygwin/tlsoffsets)"

echo
echo "=== sanity: combined tree carries BOTH fixes ==="
printf 'autoload.cc .balign sites : %s\n' "$(grep -c 'balign' $L/runtime/winsup/cygwin/autoload.cc)"
printf 'autoload.cc .align 16 left: %s (want 0)\n' "$(grep -c '\.align\s*16' $L/runtime/winsup/cygwin/autoload.cc)"
printf 'gendef aarch64 branch     : %s\n' "$(grep -c 'aarch64' $L/runtime/winsup/cygwin/scripts/gendef)"

echo
echo "=== baseline object count in the copied build dir ==="
find $L/bld/winsup/cygwin -name '*.o' | wc -l

echo
echo "=== confirm preserved assets untouched ==="
for p in /root/xc/inst /root/xc/runtime /root/xc/bld; do
  printf '  %-18s %s\n' "$p" "$([ -d "$p" ] && echo present || echo MISSING)"
done
du -sh $L
