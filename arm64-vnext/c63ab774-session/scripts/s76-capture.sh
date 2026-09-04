#!/bin/bash
# Capture the combined-link results to DISK (not just the transcript).
export PATH=/root/xc/inst/bin:$PATH
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
L=/root/xc/w-link/bld/winsup/cygwin
D=$L/new-msys-2.0.dll
mkdir -p $E

{
echo "# ARM64 vNext -- COMBINED LINK RESULTS (session c63ab774)"
echo "# Captured $(date -u +%Y-%m-%dT%H:%M:%SZ). Tree: /root/xc/w-link (my own copy)."
echo "# Preserved /root/xc/{inst,runtime,bld} NOT modified."
echo
echo "## PRECONDITIONS"
printf '_cygwin.h aarch64 _WIN64 guard : %s\n' "$(grep -q '#if defined(__x86_64__) || defined(__aarch64__)' /root/xc/inst/aarch64-pc-cygwin/include/w32api/_cygwin.h && echo PRESENT || echo ABSENT)"
printf 'w32api commit                  : %s\n' "$(git --no-optional-locks -C /root/xc/mingw-w64 rev-parse HEAD)"
printf 'w32api describe                : %s\n' "$(git --no-optional-locks -C /root/xc/mingw-w64 describe --tags)"
printf 'mbstate_t in corecrt.h         : %s (want 0)\n' "$(grep -c mbstate_t /root/xc/inst/aarch64-pc-cygwin/include/w32api/corecrt.h)"
printf 'autoload.cc md5                : %s (fixed=45fd56e736709e712ee202b7ed3c9c4f)\n' "$(md5sum /root/xc/w-link/runtime/winsup/cygwin/autoload.cc | cut -d' ' -f1)"
printf 'gendef md5 (LF-normalised)     : %s\n' "$(md5sum /root/xc/w-link/runtime/winsup/cygwin/scripts/gendef | cut -d' ' -f1)"
printf 'gendef md5 (as delivered CRLF) : d78ea8d7ac923428d0130aa04ab40c2f\n'
printf 'tlsoffsets lines               : %s\n' "$(wc -l < $L/tlsoffsets)"
echo
echo "## GENERATED ARTEFACTS"
for f in sigfe.s sigfe.o msys.def autoload.o cygwin.sc libdll.a; do
  printf '%-14s %10s  %s\n' "$f" "$(stat -c%s $L/$f)" "$(sha256sum $L/$f | cut -c1-64)"
done
echo
echo "## DLL (DIAGNOSTIC CONFIG ONLY -- 10 export entries removed from cygwin.din)"
printf 'path            : %s\n' "$D"
printf 'size            : %s bytes\n' "$(stat -c%s $D)"
printf 'sha256          : %s\n' "$(sha256sum $D | cut -c1-64)"
printf 'stripped size   : %s bytes\n' "$(stat -c%s /tmp/stripped.dll)"
printf 'stripped sha256 : %s\n' "$(sha256sum /tmp/stripped.dll | cut -c1-64)"
printf 'file            : %s\n' "$(file -b $D)"
printf 'PE machine      : %s  (0xAA64 = IMAGE_FILE_MACHINE_ARM64)\n' "$(od -An -tx1 -j$(( $(od -An -tu4 -j60 -N4 $D | tr -d ' ') + 4 )) -N2 $D | tr -s ' ')"
printf 'bfd format      : %s\n' "$(aarch64-pc-cygwin-objdump -f $D | sed -n '2p' | sed 's/.*format //')"
printf 'entry point     : %s\n' "$(aarch64-pc-cygwin-objdump -f $D | grep 'start address' | awk '{print $3}')"
printf 'sections        : %s\n' "$(aarch64-pc-cygwin-objdump -h $D | grep -c '^ *[0-9]')"
printf 'exports (EAT)   : 1757 (0x6dd)\n'
printf 'imported DLLs   : %s\n' "$(aarch64-pc-cygwin-objdump -p $D | grep -i 'DLL Name' | sort -u | tr -d '\t' | paste -sd' ')"
echo
echo "## HONEST STATUS"
echo "UNEXECUTED AND UNVALIDATED. Linking is not running."
echo "Nothing in this programme has ever been executed on ARM64."
echo "This DLL is MISSING 10 EXPORTS and is NOT a complete msys-2.0.dll."
echo "It is a diagnostic artefact answering 'is anything else behind those 10?'."
} > $E/combined-link-results.txt

cat $E/combined-link-results.txt
cp -p /root/xc/link-combined.log      $E/link-combined-honest.log
cp -p /root/xc/link-experiment2.log   $E/link-experiment-green.log
cp -p $L/msys.map                     $E/msys-combined.map 2>/dev/null
echo
echo "evidence written."
