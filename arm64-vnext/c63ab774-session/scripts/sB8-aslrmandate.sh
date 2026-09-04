#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- WINDOWS ON ARM MANDATES ASLR (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   host: Windows 11 ARM64 10.0.28000.0"
echo
echo "## THE CONTROL EXPERIMENT"
echo "  Take a KNOWN-GOOD Microsoft ARM64 system DLL, copy it, and clear ONLY the"
echo "  DYNAMIC_BASE bit (0x0040) in DllCharacteristics. Change nothing else."
echo "  Then LoadLibraryEx both copies in a fresh process."
echo
echo "  DLL                     DllChar    DYNAMIC_BASE set   DYNAMIC_BASE cleared"
echo "  ----------------------- ---------- ------------------ --------------------"
echo "  System32\\version.dll     0x4160     LOADED             FAILED err=193"
echo "  System32\\winmm.dll       0x4160     LOADED             FAILED err=193"
echo "  System32\\psapi.dll       0x4160     LOADED             FAILED err=193"
echo "  System32\\profapi.dll     0x4160     LOADED             FAILED err=193"
echo
echo "  FOUR FOR FOUR. err=193 is ERROR_BAD_EXE_FORMAT -- the SAME error our"
echo "  fixed-base msys-2.0.dll produced. The only variable changed was one bit."
echo
echo "## CONCLUSION"
echo "  WINDOWS ON ARM REQUIRES ASLR-CAPABLE IMAGES. A non-relocatable ARM64 PE is"
echo "  rejected outright at load time. This is a platform rule, not a property of"
echo "  our build."
echo
echo "## WHAT THIS RETRACTS -- TWO OF MY OWN CLAIMS"
echo "  1. 'Link with --disable-dynamicbase' is NOT a viable fix on Windows ARM64."
echo "     It removes the crash only by making the image unloadable. RETRACTED."
echo "  2. I downgraded the missing-base-relocation finding on the grounds that"
echo "     disabling ASLR made it moot. That reasoning is now INVALID."
echo "     THE 414 MISSING BASE RELOCATIONS ARE A GENUINE MUST-FIX DEFECT."
echo "     I re-raise it, and the earlier downgrade is withdrawn."
echo
echo "## THE ARCHITECTURAL CONSEQUENCE -- LARGER THAN THE LINK"
echo "  Cygwin's fork() copies the address space and REQUIRES the runtime DLL at"
echo "  the SAME address in parent and child. Upstream achieves this with a fixed"
echo "  image base and never relocating. Windows on Arm FORBIDS exactly that."
echo
echo "  These two requirements are in DIRECT CONFLICT. On Windows ARM64 the runtime"
echo "  WILL be relocated, therefore:"
echo "    - every absolute .quad in the autoload thunks MUST carry a base"
echo "      relocation (the 414 are fatal, not benign)"
echo "    - fork() cannot rely on a fixed load address and needs a different"
echo "      strategy on this platform"
echo "  This is a design-level problem for the ARM64 port, not a build-flag问题."
echo
echo "## STATUS"
echo "  Measured, reproduced 4x, and it contradicts two of my own earlier claims."
echo "  Nothing has executed beyond the loader. No user code has run."
} > $E/windows-arm-mandates-aslr.txt
sed -i 's/问题/ question/' $E/windows-arm-mandates-aslr.txt
cat $E/windows-arm-mandates-aslr.txt | head -28
