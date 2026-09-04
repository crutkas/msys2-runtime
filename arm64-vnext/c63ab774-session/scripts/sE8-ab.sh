#!/bin/bash
# 2. What changed between the A/B binaries?
# 3. Map the captured x19/x20 to __CTOR_LIST__ / __CTOR_END__.
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest

echo "############ 2. the A/B pair ############"
printf 'pre-fix  msys-2.0-teb.dll     %s\n' "$(sha256sum $D/msys-2.0-teb.dll     | cut -c1-64)"
printf 'post-fix msys-2.0-ctorfix.dll %s\n' "$(sha256sum $D/msys-2.0-ctorfix.dll | cut -c1-64)"
echo
echo "  Between them I ran ONLY: sD1 (edit cygwin.sc.in) then sD2 (regenerate"
echo "  cygwin.sc + relink). NO objects were recompiled -- libdll.a, libc.a,"
echo "  libm.a, msys.def, sigfe.o, version.o were all reused untouched."
echo "  Verify by size: identical inputs, only the script differs."
ls -la $L/libdll.a $L/msys.def $L/sigfe.o 2>&1 | awk '{print "   ",$5,$NF}'

echo
echo "############ the two generated linker scripts ############"
printf 'cygwin.sc now: %s bytes  md5 %s\n' "$(stat -c%s $L/cygwin.sc)" "$(md5sum $L/cygwin.sc | cut -d' ' -f1)"
echo "--- its ctor block ---"
grep -n -A1 '__CTOR_LIST__' $L/cygwin.sc | head -4
echo "--- regenerate from the PRESERVED (unfixed) .in for comparison ---"
aarch64-pc-cygwin-gcc -E - -P < /root/xc/runtime/winsup/cygwin/cygwin.sc.in -o /tmp/pre.sc
printf 'pre-fix script: %s bytes  md5 %s\n' "$(stat -c%s /tmp/pre.sc)" "$(md5sum /tmp/pre.sc | cut -d' ' -f1)"
grep -n -A1 '__CTOR_LIST__' /tmp/pre.sc | head -4
echo
echo "--- the ONE-LINE DIFF that settles it ---"
diff /tmp/pre.sc $L/cygwin.sc | head -20

echo
echo "############ 3. DO x19/x20 MAP TO THE CTOR LIST BOUNDS? ############"
echo "captured at fault: x19=0x00007FFDB1287EF0  x20=0x00007FFDB1287E60"
echo "module base      : 0x00007FFDB10B0000     ImageBase 0x180040000"
X19R=$((0x00007FFDB1287EF0 - 0x00007FFDB10B0000))
X20R=$((0x00007FFDB1287E60 - 0x00007FFDB10B0000))
printf 'x19 RVA 0x%X -> file VA 0x%X\n' $X19R $((0x180040000 + X19R))
printf 'x20 RVA 0x%X -> file VA 0x%X\n' $X20R $((0x180040000 + X20R))
printf 'span x19-x20 = 0x%X bytes = %d eight-byte entries\n' $((X19R-X20R)) $(( (X19R-X20R)/8 ))
echo
echo "--- ctor/dtor symbols in the PRE-FIX image ---"
aarch64-pc-cygwin-nm $D/msys-2.0-teb.dll 2>/dev/null | grep -iE '__CTOR_LIST__|__CTOR_END__|__DTOR_LIST__|___CTOR' | sort
echo "--- ctor/dtor symbols in the POST-FIX image ---"
aarch64-pc-cygwin-nm $D/msys-2.0-ctorfix.dll 2>/dev/null | grep -iE '__CTOR_LIST__|__CTOR_END__|__DTOR_LIST__|___CTOR' | sort
