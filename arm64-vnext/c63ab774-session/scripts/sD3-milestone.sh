#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- DllMain COMPLETES. FIRST CODE EVER EXECUTED ON ARM64."
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   session c63ab774"
echo "# host: Windows 11 ARM64 10.0.28000.0"
echo
echo "## THE BUG: 32-BIT CTOR/DTOR LIST MARKERS ON A 64-BIT TARGET"
echo "  winsup/cygwin/cygwin.sc.in builds the constructor/destructor lists as:"
echo
echo "    #ifdef __x86_64__"
echo "        . = ALIGN(8);"
echo "        ___CTOR_LIST__ = .;  LONG(-1); LONG(-1); *(.ctors) ... LONG(0); LONG(0);"
echo "        ___DTOR_LIST__ = .;  LONG(-1); LONG(-1); *(.dtors) ... LONG(0); LONG(0);"
echo "    #else"
echo "        ___CTOR_LIST__ = .;  LONG(-1);            *(.ctors) ... LONG(0);"
echo "        ___DTOR_LIST__ = .;  LONG(-1);            *(.dtors) ... LONG(0);"
echo "    #endif"
echo
echo "  LONG is 4 BYTES. x86_64 emits TWO of them for 8-byte head markers and"
echo "  terminators, matching 64-bit function pointers, and aligns to 8."
echo "  THE #else BRANCH IS THE LEGACY 32-BIT PATH -- AND AARCH64 FELL INTO IT."
echo "  So the ARM64 build got 4-byte markers and no 8-byte alignment."
echo
echo "## HOW IT WAS FOUND -- BY CAPTURING x30, NOT THE FAULT TARGET"
echo "  Earlier captures recorded only the faulting address, which was garbage and"
echo "  led nowhere. Capturing the FULL ARM64 CONTEXT and resolving modules with"
echo "  VirtualQuery AT FAULT TIME (never an assumed ImageBase) gave:"
echo
echo "    ACCESS_VIOLATION EXECUTE target=0xFFFFFFFF00000000"
echo "    PC = 0xFFFFFFFF00000000                       UNMAPPED"
echo "    LR = 0x00007FFDB10B83B8   msys-2.0.dll base=0x7FFDB10B0000 RVA=0x83B8"
echo "    x0 = 0xFFFFFFFF00000000   <- held the faulting target"
echo
echo "  RVA 0x83B8 is the return address, so the branch is at RVA 0x83B4:"
echo
echo "    1800483a8:  cmp  x19, x20"
echo "    1800483ac:  b.ls 1800483c0"
echo "    1800483b0:  ldr  x0, [x19], #-8      // walk the list backwards"
echo "    1800483b4:  blr  x0                  // <== FAULTED"
echo "    1800483b8:  cmp  x19, x20"
echo
echo "  A backwards constructor-list walk. With 4-byte markers the 8-byte reads"
echo "  straddle the ctor terminator LONG(0) and the dtor head marker LONG(-1):"
echo "      [00 00 00 00][FF FF FF FF]  ->  0xFFFFFFFF00000000"
echo "  EXACTLY the captured target. Diagnosis and observation agree bit for bit,"
echo "  and this finally explains the value that had been unexplained all session."
echo
echo "## THE FIX"
echo "  cygwin.sc.in:27   #ifdef __x86_64__"
echo "                 -> #if defined(__x86_64__) || defined(__aarch64__)"
echo "  One line. aarch64 now gets 8-byte markers and ALIGN(8), same as x86_64."
echo
echo "## RESULT -- RUNG 2 FULLY PASSED"
echo "  FULL LoadLibraryEx (flags 0), first load in a fresh process, DllMain RUNS:"
echo "    RESULT: LOADED. base = 0x7FFDB10B0000"
echo "       cygwin_internal  = 0x7FFDAF8E5A30"
echo "       msys_dll_init    = 0x7FFDAF8C6DA8"
echo "       fork             = 0x7FFDAF9CA7E8"
echo "       printf           = 0x7FFDAF9CBB20"
echo "       malloc           = 0x7FFDAF9CB42C"
echo "       signal           = 0x7FFDAF9CCD68"
echo "    SURVIVED DllMain      child exit code 0"
echo
echo "  Reproducible 3/3 in fresh processes."
echo "  A/B: the pre-fix build (msys-2.0-teb.dll) still exits -1073741819."
echo "  Single variable changed: the linker-script ctor marker width."
echo
echo "  artefact : msys-2.0-ctorfix.dll"
echo "  sha256   : 3d305115caccc50935b24e583826444159856d87833b815bf0f7eced4f62a782"
echo
echo "## WHAT THIS MEANS, PRECISELY"
echo "  dll_entry ran to completion. That exercised the AArch64 TLS setup, the"
echo "  static constructors, and the DLL initialisation path. THIS IS THE FIRST"
echo "  CODE FROM THIS PROGRAMME EVER EXECUTED ON ARM64."
echo
echo "## WHAT IT DOES NOT MEAN"
echo "  NO USER CODE HAS RUN. No Cygwin/MSYS2 process has started. fork(), signals,"
echo "  the sigfe trampolines and the autoload thunks are all still UNEXERCISED --"
echo "  DllMain does not call them. This is NOT a working runtime, NOT a product"
echo "  pass, and creates no authority. Rung 3 (a trivial executable) is next and"
echo "  has not been attempted."
} > $E/dllmain-completes.txt
head -20 $E/dllmain-completes.txt
