#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
R=/root/xc/runtime/winsup/cygwin
echo "############ the 8 non-sigfe/non-setjmp export failures ############"
for s in __alloca _ctype_ _fe_nomask_env fedisableexcept fegetexcept fegetprec fesetprec msys_dll_init; do
  echo "---- $s ----"
  echo -n "  in newlib libc.a/libm.a: "
  (aarch64-pc-cygwin-nm /root/xc/bld/newlib/libc.a /root/xc/bld/newlib/libm.a 2>/dev/null \
     | grep -E "^[0-9a-f]+ T $s\$" | head -1) || true
  echo
  echo -n "  source sites: "
  grep -rln "\b$s\b" $R --include='*.c' --include='*.cc' --include='*.S' --include='*.h' 2>/dev/null | head -3 | tr '\n' ' '
  echo
  echo -n "  x86_64-only dir? "
  grep -rln "\b$s\b" $R/x86_64 /root/xc/runtime/newlib/libm/machine/x86_64 /root/xc/runtime/newlib/libc/machine/x86_64 2>/dev/null | head -2 | tr '\n' ' '
  echo
done

echo
echo "############ EVIDENCE COLLECTION ############"
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
mkdir -p $D
cp /tmp/undef.txt              $D/undefined-references-all.txt
cp /tmp/undef_other.txt        $D/undefined-not-explained-by-autoload.txt
cp /tmp/undef_autoload.txt     $D/undefined-autoload-thunks.txt
cp /tmp/cantexport.txt         $D/cannot-export-all.txt
grep -v '^_sigfe_' /tmp/cantexport.txt > $D/cannot-export-non-sigfe.txt
cp /tmp/dll_objs_missing.txt   $D/libdll-missing-objects.txt
cp /root/xc/link1.log          $D/link-attempt-raw.log 2>/dev/null
head -c 400000 /root/xc/bld/winsup/cygwin/msys.map > $D/msys.map.head.txt
ls -la $D
