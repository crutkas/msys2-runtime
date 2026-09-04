#!/bin/bash
# Persist the execution-attempt results (lesson: echo to a transcript is not persistence).
export PATH=/root/xc/inst/bin:$PATH
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
RT=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
L=/root/xc/w-link/bld/winsup/cygwin

{
echo "# ARM64 vNext -- EXECUTION ATTEMPT RESULTS (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)  host: Windows 11 ARM64 (10.0.28000.0)"
echo
echo "## RUNG 1 -- PE identity verified NATIVELY on Windows (not via WSL tooling)"
echo "  MZ 0x5A4D ok / PE 0x00004550 ok"
echo "  MACHINE 0xAA64 = IMAGE_FILE_MACHINE_ARM64"
echo "  23 sections, Characteristics 0x2026 (IMAGE_FILE_DLL set), opt magic 0x020B (PE32+)"
echo "  PASSED."
echo
echo "## RUNG 2 -- LoadLibrary"
echo "  A. LOAD_LIBRARY_AS_IMAGE_RESOURCE (0x20)        : SUCCESS"
echo "  B. DONT_RESOLVE_DLL_REFERENCES  (0x01)          : SUCCESS"
echo "     GetProcAddress resolved real addresses:"
echo "       cygwin_internal 0x7FFDB0DE5A30   msys_dll_init 0x7FFDB0DC6DA8"
echo "       fork            0x7FFDB0ECA7E8   printf        0x7FFDB0ECBB20"
echo "       dll_entry       0x7FFDB0E529B0"
echo "     => image maps, sections lay out, export table is valid and resolvable."
echo "  C. FULL LOAD (flags 0), DllMain/dll_entry RUNS  : CHILD PROCESS DIES"
echo "     child exit code -1073741819 = 0xC0000005 STATUS_ACCESS_VIOLATION"
echo "     Reproduced in TWO independent harnesses, one with NO VEH and NO CLR"
echo "     involvement at all (r02-loadlibrary.ps1)."
echo "  => RUNG 2 IS PARTIAL: maps and binds, but initialisation faults."
echo
echo "## BUG FOUND AND FIXED BY EXECUTING: Windows ARM64 TEB register"
echo "  winsup/cygwin/include/cygwin/config.h __getreent() read the TEB with"
echo "      mrs xN, tpidr_el0 ; ldr xN, [xN, #8]"
echo "  under a comment asserting 'On Windows ARM64 the TEB pointer is held in"
echo "  tpidr_el0 (and mirrored in the reserved platform register x18)'."
echo "  THAT IS BACKWARDS."
echo
echo "  EMPIRICAL PROOF, measured on this machine by executing raw AArch64"
echo "  instructions in allocated RWX memory (no compiler required):"
echo "      mrs x0, tpidr_el0  -> 0x0000000000000000     <-- ZERO"
echo "      mov x0, x18        -> 0x00000080002C8000"
echo "      [x18+0x08] StackBase = 0x000000801B990000"
echo "      GetCurrentThreadStackLimits high = 0x000000801B990000   MATCH"
echo "  x18 IS the TEB; tpidr_el0 is zero. So 'ldr xN,[xN,#8]' reads address 0x8."
echo "  The first captured fault was AV READ of target 0x0000000000000008 -- exact match."
echo
echo "  FIXED in two places (tpidr_el0 -> x18, read-only, never written):"
echo "    - include/cygwin/config.h  __getreent()"
echo "    - scripts/gendef           6 trampoline emission sites"
echo "  newlib was ALSO rebuilt, because the preserved libc.a/libm.a carried"
echo "  inlined __getreent copies compiled against the old header."
echo "  Result: tpidr_el0 occurrences in the linked DLL 520 -> 0; x18 sites 1850."
echo
echo "## SECOND, DIFFERENT FAULT after the TEB fix"
echo "  child exit still 0xC0000005, but the failure MOVED:"
echo "      EXCEPTION 0xC0000005 ACCESS_VIOLATION EXEC target=0xFFFFFFFF00000000"
echo "        at 0xFFFFFFFF00000000  (PC itself is the bad value)"
echo "  A branch to 0xFFFFFFFF00000000 -- high 32 bits all ones, low 32 zero."
echo "  That is a corrupt/unpatched code pointer, not a null dereference."
echo "  Consistent with the autoload thunk mechanism, which rewrites function"
echo "  pointers at first call and is the next thing dll_entry exercises."
echo "  NOT YET DIAGNOSED. Reported as-is."
echo
echo "## ARTEFACTS"
for f in $RT/msys-2.0.dll $RT/msys-2.0-teb.dll; do
  [ -f "$f" ] && printf '  %-24s %10s  %s\n' "$(basename $f)" "$(stat -c%s $f)" "$(sha256sum $f | cut -c1-64)"
done
echo
echo "## STATUS"
echo "  A native ARM64 msys-2.0.dll MAPS and BINDS on Windows ARM64."
echo "  It does NOT yet complete DllMain. It has NOT run any user code."
echo "  Not a working runtime. Not a product pass. No authority."
} > $E/execution-attempt.txt

cp -f $RT/fault-teb.txt $E/fault-after-teb-fix.txt 2>/dev/null
cp -f $RT/crash2.txt    $E/fault-before-teb-fix.txt 2>/dev/null
cat $E/execution-attempt.txt
