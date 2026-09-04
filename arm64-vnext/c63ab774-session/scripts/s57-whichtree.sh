#!/bin/bash
# Which runtime tree actually carries the autoload fix?
# Does the PRESERVED /root/xc/runtime appear to have been modified?
echo "############ autoload.cc .balign counts by tree ############"
for t in /root/xc/runtime /root/xc/w-autoload/runtime /root/xc/w-link/runtime; do
  f=$t/winsup/cygwin/autoload.cc
  printf '%-34s balign=%-3s  align16=%-3s  sha=%s\n' \
    "$t" "$(grep -c 'balign' $f 2>/dev/null)" "$(grep -c '\.align\s*16' $f 2>/dev/null)" \
    "$(sha256sum $f 2>/dev/null | cut -c1-16)"
done

echo
echo "############ gendef by tree ############"
for t in /root/xc/runtime /root/xc/w-autoload/runtime /root/xc/w-link/runtime; do
  f=$t/winsup/cygwin/scripts/gendef
  printf '%-34s lines=%-5s aarch64hits=%-3s sha=%s\n' \
    "$t" "$(wc -l < $f 2>/dev/null)" "$(grep -c aarch64 $f 2>/dev/null)" \
    "$(sha256sum $f 2>/dev/null | cut -c1-16)"
done

echo
echo "############ Did the preserved runtime change since I sealed it? ############"
echo "sealed diff shape was: 43 files, 1693 insertions, 760 deletions"
git --no-optional-locks -C /root/xc/runtime diff HEAD --shortstat

echo
echo "############ w-autoload/bld srcdir points where? ############"
grep -m2 '^srcdir = \|^abs_srcdir = ' /root/xc/w-autoload/bld/winsup/cygwin/Makefile

echo
echo "############ w-autoload/runtime own git shape ############"
git --no-optional-locks -C /root/xc/w-autoload/runtime diff HEAD --shortstat
