#!/bin/bash
# The copied bld/ still points at /root/xc/w-autoload/runtime. Repoint it at w-link.
L=/root/xc/w-link
echo "=== how many files reference the old tree? ==="
grep -rl '/root/xc/w-autoload' $L/bld 2>/dev/null | wc -l
echo "=== sample references in the cygwin Makefile ==="
grep -m5 -n '/root/xc/w-autoload' $L/bld/winsup/cygwin/Makefile

echo
echo "=== repointing bld/ from w-autoload -> w-link ==="
grep -rl '/root/xc/w-autoload' $L/bld 2>/dev/null \
  | while read -r f; do sed -i 's|/root/xc/w-autoload|/root/xc/w-link|g' "$f"; done
echo "remaining references (want 0): $(grep -rl '/root/xc/w-autoload' $L/bld 2>/dev/null | wc -l)"

echo
echo "=== verify srcdir now resolves into the combined tree ==="
grep -m3 -n 'srcdir = \|abs_srcdir' $L/bld/winsup/cygwin/Makefile
echo -n "gendef seen by the build is the FIXED one? lines = "
wc -l < $L/runtime/winsup/cygwin/scripts/gendef

echo
echo "=== does bld reference the preserved /root/xc/bld/newlib? (it must NOT write there) ==="
grep -m5 -n 'newlib_build\|target_builddir' $L/bld/winsup/cygwin/Makefile
