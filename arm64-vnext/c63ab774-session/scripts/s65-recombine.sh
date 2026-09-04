#!/bin/bash
# REBUILD the combined tree, correcting MY OWN error.
#
# What went wrong: s58 repointed srcdir with
#     grep -rl '/root/xc/runtime' $L/bld | while read f; do sed -i ... "$f"; done
# `grep -rl` matches BINARY files too -- object files embed their source paths in
# DWARF debug info -- so sed rewrote 2855 files including .o archives members,
# corrupting them (+84 bytes each: sed re-terminated lines inside binary data).
# Symptom was `ar: bad string table size 0`.
#
# FIX: use `grep -rIl` (capital I = skip binary files) so only text config/Makefiles
# are repointed. Object files keep their old embedded debug paths, which is harmless
# for linking.
set -u
A=/root/xc/w-autoload
G=/root/xc/w-gendef
L=/root/xc/w-link

rm -rf $L
mkdir -p $L
echo "=== re-copying pristine trees ==="
cp -a $A/runtime $L/runtime
cp -a $A/bld     $L/bld

echo "=== install gendef AArch64 backend, LF-normalised ==="
sed 's/\r$//' $G/gendef > $L/runtime/winsup/cygwin/scripts/gendef
chmod +x $L/runtime/winsup/cygwin/scripts/gendef
perl -c $L/runtime/winsup/cygwin/scripts/gendef 2>&1 | tail -1

echo "=== install correct 59-line tlsoffsets ==="
cp -p $G/tlsoffsets $L/bld/winsup/cygwin/tlsoffsets
wc -l < $L/bld/winsup/cygwin/tlsoffsets

echo
echo "=== repoint srcdir: TEXT FILES ONLY (grep -rIl) ==="
TXT=$(grep -rIl '/root/xc/runtime' $L/bld 2>/dev/null | wc -l)
ALL=$(grep -rl  '/root/xc/runtime' $L/bld 2>/dev/null | wc -l)
echo "text files: $TXT   (all matches incl. binary: $ALL  <- the trap)"
grep -rIl '/root/xc/runtime' $L/bld 2>/dev/null \
  | while read -r f; do sed -i 's|/root/xc/runtime|/root/xc/w-link/runtime|g' "$f"; done
grep -rIl '/root/xc/w-autoload' $L/bld 2>/dev/null \
  | while read -r f; do sed -i 's|/root/xc/w-autoload|/root/xc/w-link|g' "$f"; done
grep -m2 '^srcdir = \|^abs_srcdir = ' $L/bld/winsup/cygwin/Makefile

echo
echo "=== VERIFY no object file was harmed ==="
export PATH=/root/xc/inst/bin:$PATH
cd $L/bld/winsup/cygwin
bad=0; good=0
for o in $(find . -name '*.o'); do
  if aarch64-pc-cygwin-objdump -f "$o" >/dev/null 2>&1; then good=$((good+1)); else bad=$((bad+1)); echo "  BAD: $o"; fi
done
echo "readable objects: $good   corrupt: $bad"

echo
echo "=== force regeneration of gendef outputs ==="
rm -f msys.def sigfe.s sigfe.o autoload.o
echo done
