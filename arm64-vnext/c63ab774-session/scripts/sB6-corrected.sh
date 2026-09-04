#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- BASE-RELOCATION INVESTIGATION, CORRECTED (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "## METHOD CORRECTION (mine)"
echo "  My first count assumed every thunk's two quads sat at +0x30/+0x40. That is"
echo "  unsound: each thunk embeds .asciz \"<name>\", so thunk size varies with name"
echo "  length. I re-measured WITHOUT any layout assumption -- scanning the section"
echo "  for 8-byte-aligned qwords whose value falls inside the image VA range, then"
echo "  checking each against the .reloc directory."
echo "  The corrected method returns THE SAME NUMBERS:"
echo "      absolute image-range qwords in .autoload_text : 424"
echo "      WITH DIR64 base relocation                    :  10"
echo "      WITHOUT                                       : 414"
echo "  So the figure stands, but it now rests on a sound derivation."
echo
echo "## HYPOTHESIS TESTED AND REFUTED: '10 == number of distinct DLLs'"
echo "  distinct autoloaded DLLs in autoload.cc : 21"
echo "  distinct ..._info symbols in the image  : 21"
echo "  (kernel32 ntdll advapi32 user32 secur32 netapi32 ws2_32 wldap32 shell32"
echo "   ole32 psapi pdh mpr iphlpapi gdi32 dnsapi authz userenv winmm KernelBase)"
echo "  21 != 10, so 'one base relocation per unique target symbol' is WRONG."
echo
echo "## WHAT THE SURVIVORS ACTUALLY ARE"
echo "  At least one survivor is a genuine thunk slot: RVA 0x21bdd0 belongs to"
echo "  _win32_waveOutClose (thunk at 0x18021bd90) and holds 0x18021bd98, the"
echo "  address of its 1b loader stub -- i.e. exactly the same construct as the"
echo "  414 that were dropped. So the linker emits a base relocation for SOME"
echo "  instances of a construct and drops it for others. The discriminator is"
echo "  STILL NOT IDENTIFIED. Reported as an open question, not guessed at."
echo
echo "## BUT THE PRIMARY DEFECT IS UPSTREAM OF ALL OF THIS"
echo "  x86_64 and aarch64 emit the SAME two absolute quads per thunk, and a"
echo "  sibling confirmed both targets emit ADDR64 object relocations for them."
echo "  The construct is upstream Cygwin design, not an ARM64 port artefact."
echo "  It is safe upstream because the Cygwin runtime DLL is NEVER RELOCATED:"
echo "  fork() copies the address space and requires the DLL at the same address"
echo "  in parent and child."
echo
echo "  OUR LINK ENABLED ASLR:  DllCharacteristics 0x0160"
echo "      HIGH_ENTROPY_VA SET / DYNAMIC_BASE SET / NX_COMPAT SET"
echo "  and the image was duly relocated to 0x00007FFDAD3D0000."
echo "  Makefile.am passes no --disable-dynamicbase; modern binutils defaults it on."
echo
echo "  Relinking with -Wl,--disable-dynamicbase -Wl,--disable-high-entropy-va:"
echo "      DllCharacteristics 0x0100 (DYNAMIC_BASE cleared)"
echo "      sha256 5914644f37789006c104c91205b755d66e07cf81c8e6283dbd645fdc1380ae9e"
echo "      LOAD BEHAVIOUR CHANGED: the 0xC0000005 crash is GONE; LoadLibrary now"
echo "      returns cleanly with GetLastError 193 ERROR_BAD_EXE_FORMAT."
echo
echo "## NEXT STEP, NOT DONE"
echo "  ImageBase reads 0x180040000, not the 0x180000000 requested via"
echo "  -Wl,--image-base; cygwin.sc places .text at __image_base__ +"
echo "  __section_alignment__ and appears to win. With ASLR off the loader must"
echo "  place the image at exactly that base, and 193 is consistent with it being"
echo "  unable to. This is a link/script question, not a source one."
echo
echo "## STILL OPEN, STILL SEPARATE"
echo "  0xFFFFFFFF00000000 remains unexplained and is NOT merged into the above."
echo
echo "## STATUS"
echo "  Nothing has executed beyond the loader. No user code has run."
} > $E/base-reloc-corrected.txt
head -20 $E/base-reloc-corrected.txt
