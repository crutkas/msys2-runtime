#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- DLL ASLR IS PER-BOOT, NOT PER-PROCESS (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   host: Windows 11 ARM64 10.0.28000.0"
echo
echo "## THE EXPERIMENT"
echo "  Load msys-2.0-teb.dll (DYNAMIC_BASE set, preferred base 0x180040000) with"
echo "  DONT_RESOLVE_DLL_REFERENCES -- which maps AND RELOCATES the image without"
echo "  running DllMain -- and report the load base."
echo "    phase 1: two CONCURRENT processes, both holding the image loaded"
echo "    phase 2: two more processes AFTER both had exited (image fully unloaded)"
echo
echo "  concurrentA   PID=30496   base=0x7FFDAF010000"
echo "  concurrentB   PID=39904   base=0x7FFDAF010000"
echo "  afterUnload   PID=69436   base=0x7FFDAF010000"
echo "  afterUnload2  PID=91552   base=0x7FFDAF010000"
echo
echo "  FOUR PROCESSES, ONE BASE. Identical across concurrent loads AND across a"
echo "  full unload/reload cycle. The randomised base is assigned PER IMAGE PER"
echo "  BOOT, not per process -- which is what makes cross-process page sharing"
echo "  work in the first place."
echo
echo "## THIS SOFTENS MY OWN ARCHITECTURAL CLAIM -- SIGNIFICANTLY"
echo "  I said: 'Cygwin's fork() requires a fixed base, Windows on Arm forbids"
echo "  fixed bases, therefore the two are in DIRECT CONFLICT and fork() needs a"
echo "  different strategy.' THAT WAS TOO STRONG."
echo
echo "  fork()'s REAL requirement is not 'a FIXED base'. It is 'the SAME base in"
echo "  parent and child'. Per-boot ASLR SATISFIES that requirement: the parent"
echo "  already has the image loaded, and the child maps it at the same address."
echo
echo "  CORRECTED POSITION:"
echo "    - Cygwin's fork model is NOT architecturally incompatible with Windows"
echo "      on Arm."
echo "    - What is lost is the GUARANTEE BY CONSTRUCTION. Upstream got the"
echo "      invariant for free from a fixed image base; on this platform the port"
echo "      must VERIFY the invariant rather than assume it."
echo "    - That is a real porting task, but it is ordinary work, not a design-"
echo "      level blocker."
echo
echo "## WHAT IS UNCHANGED AND STILL MUST-FIX"
echo "  The image IS relocated: observed 0x7FFDAF010000 vs preferred 0x180040000."
echo "  So every absolute quad in the autoload thunks needs a base relocation, and"
echo "  414 of 424 do not have one. That remains FATAL and is the single most"
echo "  important open item. The mandatory-ASLR platform rule (4/4 control DLLs"
echo "  rejected with err 193 when DYNAMIC_BASE is cleared) also stands unchanged."
echo
echo "## STATUS"
echo "  Nothing has executed beyond the loader. No user code has run."
} > $E/aslr-per-boot.txt
cat $E/aslr-per-boot.txt | head -32
