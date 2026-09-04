#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- THE CTOR-FIX RETRACTION IS REFUTED (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "## CLAIM AGAINST ME"
echo "  'cygwin.sc.in ALREADY read #if defined(__x86_64__) || defined(__aarch64__),"
echo "   the generated cygwin.sc ALREADY had paired LONG(-1); LONG(-1), therefore"
echo "   the root cause was wrong and the fix a no-op.'"
echo
echo "## 1. THE PRE-EDIT LINE, from trees I never modified"
echo "  /root/xc/runtime            cygwin.sc.in md5 ceef1c49ee20a4340b47576305d66def"
echo "  /root/xc/w-autoload/runtime cygwin.sc.in md5 ceef1c49ee20a4340b47576305d66def"
echo "  BOTH read, verbatim, at line 27:"
echo "        #ifdef __x86_64__"
echo "  My tree /root/xc/w-link is md5 d444a1e77c8e6c7bbc4304b9701cc8bc and reads:"
echo "        #if defined(__x86_64__) || defined(__aarch64__)"
echo "  And git HEAD of the repo confirms the #else branch:"
echo "        LONG (-1); *(SORT(.ctors.*)); *(.ctors); *(.ctor); LONG (0);"
echo
echo "  THE RETRACTION READ MY TREE AFTER I FIXED IT."
echo
echo "  THE SUBTLETY IT MISSED: the x86_64 branch ALWAYS had paired LONGs. Seeing"
echo "  'LONG(-1); LONG(-1)' in the file proves nothing -- the question is whether"
echo "  AARCH64 REACHES THAT BRANCH. Before the fix it did not; it fell through to"
echo "  the #else with single 4-byte markers and no ALIGN(8)."
echo
echo "## 2. THE A/B DIFFERED ONLY IN THE LINKER SCRIPT"
echo "  pre-fix  msys-2.0-teb.dll     3cf8d39b8509b81382beca1890a1576c2e538c5be8635fdfc82c5ddfb0ae80ca"
echo "  post-fix msys-2.0-ctorfix.dll 3d305115caccc50935b24e583826444159856d87833b815bf0f7eced4f62a782"
echo "  Between them: edit cygwin.sc.in, regenerate cygwin.sc, relink. NO object"
echo "  was recompiled -- libdll.a (31,457,284), msys.def (40,626), sigfe.o"
echo "  (158,129), version.o, libc.a, libm.a all reused byte-identical."
echo
echo "## 3. THE GENERATED-SCRIPT DIFF, which ends the argument"
echo "  pre-fix  script 3729 bytes md5 212e74b5fe339d7366dc140aadf75910"
echo "  post-fix script 3825 bytes md5 7d533f0d48b2c9c51190aec3bd555fc4"
echo
echo "    12a13"
echo "    >     . = ALIGN(8);"
echo "    14c15"
echo "    <    LONG (-1); *(SORT(.ctors.*)); *(.ctors); *(.ctor); LONG (0);"
echo "    ---"
echo "    >    LONG (-1); LONG (-1); *(...); LONG (0); LONG (0);"
echo
echo "## 4. THE MEASUREMENT NOBODY HAD MADE: x19/x20 vs the list bounds"
echo "  captured at fault: x19=0x00007FFDB1287EF0  x20=0x00007FFDB1287E60"
echo "  module base 0x00007FFDB10B0000 (VirtualQuery, not assumed)"
echo "    x20 -> file VA 0x180217E60"
echo "    x19 -> file VA 0x180217EF0"
echo
echo "  symbols in the PRE-FIX image:"
echo "    __CTOR_LIST__ = 0x180217E60   <== EXACTLY x20. The walk bound IS the list."
echo "    __DTOR_LIST__ = 0x180217EFC   <== 0xEFC is 4 MOD 8. MISALIGNED."
echo "  symbols in the POST-FIX image:"
echo "    __CTOR_LIST__ = 0x180217E60"
echo "    __DTOR_LIST__ = 0x180217F00   <== 8-byte aligned. Moved by exactly +4."
echo
echo "  So in the pre-fix image the ctor terminator LONG(0) sits at 0x..EF8-EFB and"
echo "  the dtor head marker LONG(-1) at 0x..EFC-EFF. An 8-byte read at 0x..EF8"
echo "  returns [00 00 00 00][FF FF FF FF] = 0xFFFFFFFF00000000 -- the captured"
echo "  EXECUTE target -- and the captured x19=0x..EF0 is that address after the"
echo "  post-decrement of 'ldr x0, [x19], #-8'. Every number agrees."
echo
echo "## VERDICT"
echo "  The retraction inspected post-fix state and concluded the fix was"
echo "  unnecessary. x20 == __CTOR_LIST__ exactly, and __DTOR_LIST__ moved from a"
echo "  4-mod-8 address to an 8-aligned one. The fix is real and the diagnosis"
echo "  is confirmed by symbol arithmetic, not just by the A/B."
echo
echo "## HAZARD RELAYED, NOT MINE"
echo "  A defective DLL exists at /root/xc/w-ctorfix/msys-2.0.dll, sha256"
echo "  e5ac75234c6131a2dd97f4a17717fcf745f2b3fb1b605766493cd9673ae30f9c, built"
echo "  with THREE markers (12 bytes) by a sed that matched the already-correct"
echo "  paired form. It linked cleanly. DO NOT USE OR COMPARE AGAINST IT."
echo "  I have never read or written anything in w-ctorfix."
} > $E/ctorfix-retraction-refuted.txt
head -14 $E/ctorfix-retraction-refuted.txt
