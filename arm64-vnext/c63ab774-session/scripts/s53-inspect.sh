#!/bin/bash
# READ-ONLY. Exactly what does each tree contribute?
A=/root/xc/w-autoload
G=/root/xc/w-gendef

echo "################ w-gendef contents ################"
ls -la $G
echo
echo "--- is w-gendef/gendef different from w-gendef/gendef.orig? ---"
diff -q $G/gendef $G/gendef.orig && echo "IDENTICAL(!)" || echo "differs (expected)"
echo "--- gendef.orig vs preserved /root/xc/runtime version ---"
diff -q $G/gendef.orig /root/xc/runtime/winsup/cygwin/scripts/gendef && echo "orig == preserved runtime copy" || echo "orig DIFFERS from preserved runtime copy"
echo "--- sizes ---"
wc -l $G/gendef $G/gendef.orig
wc -c $G/sigfe.s $G/msys.def $G/tlsoffsets

echo
echo "################ w-autoload: what is modified vs its own HEAD ################"
git --no-optional-locks -C $A/runtime rev-parse HEAD 2>/dev/null
git --no-optional-locks -C $A/runtime status --porcelain --untracked-files=all 2>/dev/null | head -60

echo
echo "################ does w-autoload's tree already carry the gendef fix? ################"
grep -n "is_x86_64\|aarch64" $A/runtime/winsup/cygwin/scripts/gendef 2>/dev/null | head -10

echo
echo "################ autoload.cc: balign present? ################"
grep -n 'balign\|\.align' $A/runtime/winsup/cygwin/autoload.cc 2>/dev/null | head -12

echo
echo "################ w-autoload build state ################"
find $A/bld -name '*.o' 2>/dev/null | wc -l
ls -la $A/bld/winsup/cygwin/sigfe.s $A/bld/winsup/cygwin/msys.def $A/bld/winsup/cygwin/tlsoffsets 2>&1
