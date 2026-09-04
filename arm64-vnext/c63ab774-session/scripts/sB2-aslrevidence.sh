#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- AUTOLOAD FAULT: ROOT CAUSE IS ASLR, NOT AN ARM64 PORT DEFECT"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)  session c63ab774"
echo
echo "## THE x86_64 DIFFERENTIAL REFUTES THE 'ARM64-ONLY' HYPOTHESIS"
echo "  autoload.cc, x86_64 LoadDLLfuncEx3:      aarch64 LoadDLLfuncEx3:"
echo "      movq  3f(%rip),%rax                      ldr  x16, 3f"
echo "      jmp   *%rax                              br   x16"
echo "      2:.quad .<dll>_info                      2:.quad .<dll>_info"
echo "      3:.quad 1b                               3:.quad 1b"
echo "  BOTH load the slot PC-relatively; BOTH slots hold ABSOLUTE addresses."
echo "  The construct is IDENTICAL. The absolute .quad is upstream Cygwin design,"
echo "  NOT something the ARM64 port introduced."
echo
echo "## SO WHY DOES IT WORK ON x86_64?  BECAUSE THAT IMAGE IS NEVER RELOCATED."
echo "  Cygwin/MSYS2 require the runtime DLL at a FIXED base: fork() copies the"
echo "  address space and the DLL must sit at the same address in parent and child."
echo "  With no relocation, absolute .quad slots never need fixing up -- which is"
echo "  exactly why 414 of 424 missing base relocations are harmless upstream."
echo
echo "## MEASURED DEFECT: OUR LINK ENABLED ASLR"
echo "  DllCharacteristics of the ASLR build : 0x0160"
echo "      HIGH_ENTROPY_VA (0x0020)  SET"
echo "      DYNAMIC_BASE    (0x0040)  SET   <<< loader free to relocate"
echo "      NX_COMPAT       (0x0100)  SET"
echo "  Observed load base 0x00007FFDAD3D0000 vs preferred 0x180040000 -> every"
echo "  unrelocated absolute quad became a stale pointer -> branch to garbage."
echo "  Makefile.am passes NO --disable-dynamicbase; modern binutils defaults it ON."
echo
echo "## TEST: RELINK WITH ASLR DISABLED"
echo "  added -Wl,--disable-dynamicbase -Wl,--disable-high-entropy-va"
echo "  LINK EXIT 0, zero diagnostics"
echo "  DllCharacteristics now 0x0100 (NX_COMPAT only; DYNAMIC_BASE CLEARED)"
echo "  sha256 5914644f37789006c104c91205b755d66e07cf81c8e6283dbd645fdc1380ae9e"
echo
echo "  LOAD RESULT CHANGED SHAPE:"
echo "    before : child process DIED, 0xC0000005 ACCESS_VIOLATION EXEC"
echo "    after  : NO CRASH. LoadLibrary returns cleanly,"
echo "             GetLastError = 193 ERROR_BAD_EXE_FORMAT"
echo "  The crash is gone. A hard fault became a clean, diagnosable refusal."
echo
echo "## NEXT, NOT YET DONE"
echo "  ImageBase reads 0x180040000, not the 0x180000000 requested via"
echo "  -Wl,--image-base. cygwin.sc places .text at '__image_base__ +"
echo "  __section_alignment__' and appears to override the flag. With ASLR off the"
echo "  loader MUST place the image at exactly that base; if it cannot, it fails,"
echo "  and 193 is consistent with that. Getting the image base right is the next"
echo "  step, and is a link/script question rather than a source one."
echo
echo "## STILL OPEN, DELIBERATELY NOT MERGED INTO THE ABOVE"
echo "  The exact fault value 0xFFFFFFFF00000000 remains UNEXPLAINED. The missing"
echo "  relocations predict a stale branch to 0x180218008, not to that value."
echo "  Whether a second effect exists is now testable: with relocation removed"
echo "  from the picture, re-observe where the fault lands."
echo
echo "## STATUS"
echo "  Nothing has executed beyond the loader. No user code has run."
echo "  Not a working runtime. Not a product pass."
} > $E/aslr-root-cause.txt
cat $E/aslr-root-cause.txt | head -30
