#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link/bld/winsup/cygwin
D=$L/new-msys-2.0.dll
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
cp $D /tmp/honest-stripped.dll; aarch64-pc-cygwin-strip /tmp/honest-stripped.dll

{
echo "# ARM64 vNext -- HONEST LINK RESULT (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   tree: /root/xc/w-link"
echo "# ZERO exports removed. ZERO symbols stubbed. ZERO linker diagnostics."
echo
echo "## PRECONDITIONS"
printf '_cygwin.h aarch64 _WIN64 : %s\n' "$(grep -q '#if defined(__x86_64__) || defined(__aarch64__)' /root/xc/inst/aarch64-pc-cygwin/include/w32api/_cygwin.h && echo PRESENT || echo ABSENT)"
printf 'w32api                   : %s (%s)\n' "$(git --no-optional-locks -C /root/xc/mingw-w64 describe --tags)" "$(git --no-optional-locks -C /root/xc/mingw-w64 rev-parse HEAD)"
printf 'mbstate_t in corecrt.h   : %s\n' "$(grep -c mbstate_t /root/xc/inst/aarch64-pc-cygwin/include/w32api/corecrt.h)"
printf 'autoload.cc md5          : %s\n' "$(md5sum /root/xc/w-link/runtime/winsup/cygwin/autoload.cc | cut -d' ' -f1)"
printf 'gendef md5 (orphan, LF)  : %s\n' "$(md5sum /root/xc/w-link/runtime/winsup/cygwin/scripts/gendef | cut -d' ' -f1)"
printf 'cygwin.din md5           : %s (%s lines)\n' "$(md5sum /root/xc/w-link/runtime/winsup/cygwin/cygwin.din | cut -d' ' -f1)" "$(wc -l < /root/xc/w-link/runtime/winsup/cygwin/cygwin.din)"
printf 'flavour                  : %s\n' "$(aarch64-pc-cygwin-nm $L/dcrt0.o | grep -oE ' T (msys|cygwin)_dll_init' | tr -d ' T')"
echo
echo "## INPUT ARTEFACTS"
for f in sigfe.s sigfe.o msys.def autoload.o fenv_aarch64.o cygwin.sc libdll.a; do
  printf '%-16s %10s  %s\n' "$f" "$(stat -c%s $L/$f)" "$(sha256sum $L/$f | cut -c1-64)"
done
echo
echo "## THE DLL"
printf 'size            : %s bytes\n' "$(stat -c%s $D)"
printf 'sha256          : %s\n' "$(sha256sum $D | cut -c1-64)"
printf 'stripped size   : %s bytes\n' "$(stat -c%s /tmp/honest-stripped.dll)"
printf 'stripped sha256 : %s\n' "$(sha256sum /tmp/honest-stripped.dll | cut -c1-64)"
printf 'file            : %s\n' "$(file -b $D)"
printf 'PE machine      : %s = 0xAA64 (IMAGE_FILE_MACHINE_ARM64)\n' "$(od -An -tx1 -j$(( $(od -An -tu4 -j60 -N4 $D | tr -d ' ') + 4 )) -N2 $D | tr -s ' ')"
printf 'bfd format      : %s\n' "$(aarch64-pc-cygwin-objdump -f $D | sed -n '2p' | sed 's/.*format //')"
printf 'entry point     : %s\n' "$(aarch64-pc-cygwin-objdump -f $D | grep 'start address' | awk '{print $3}')"
printf 'sections        : %s\n' "$(aarch64-pc-cygwin-objdump -h $D | grep -c '^ *[0-9]')"
printf 'exports (EAT)   : %s\n' "$(python3 -c "print(int('$(aarch64-pc-cygwin-objdump -p $D | grep -m1 'Export Address Table' | awk '{print $NF}')',16))")"
printf 'imported DLLs   : %s\n' "$(aarch64-pc-cygwin-objdump -p $D | grep -i 'DLL Name' | sed 's/.*: //' | sort -u | paste -sd' ')"
printf 'shared id       : %s\n' "$(strings -a $D | grep -oE '(msys-2\.0|cygwin1)S[0-9]+' | sort -u | paste -sd' ')"
echo
echo "## STATUS"
echo "UNEXECUTED AND UNVALIDATED. Linking is not running."
echo "Nothing in this programme has ever been executed on ARM64."
echo "Not a product pass. Not a working runtime. Creates no authority."
} > $E/honest-link-result.txt

cat $E/honest-link-result.txt
cp -p /root/xc/link-honest.log $E/link-honest.log
