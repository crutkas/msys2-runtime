#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- RUNG 3 ATTEMPTED: A REAL ARM64 MSYS2 PROCESS RUNS"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   session c63ab774"
echo
echo "## NEW PORT GAP FOUND AND FIXED: scripts/mkimport emits x86-only thunks"
echo "  my \$is_x86_64 = (\$cpu eq 'x86_64' ? 1 : 0);"
echo "     if (\$is_x86_64) { jmp *\$imp_sym(%rip) }   # x86-64"
echo "     else            { jmp *\$imp_sym       }   # legacy 32-bit x86"
echo "  aarch64 fell into the else branch and emitted 'jmp', which the AArch64"
echo "  assembler rejects: \"unknown mnemonic \`jmp'\"."
echo
echo "  THIS IS THE THIRD INSTANCE OF THE SAME STRUCTURAL DEFECT:"
echo "    1. cygwin.sc.in OUTPUT_FORMAT"
echo "    2. cygwin.sc.in ctor/dtor list markers  (caused the DllMain crash)"
echo "    3. scripts/mkimport import thunks       (this one)"
echo "  In every case a 64-bit path is guarded on x86_64 with a legacy 32-bit"
echo "  fallback that aarch64 silently inherits."
echo
echo "  FIX: emit the standard AArch64 PE import thunk --"
echo "      adrp x16, sym ; ldr x16, [x16, #:lo12:sym] ; br x16"
echo "  x16 (IP0) is the architecturally-sanctioned inter-procedure scratch"
echo "  register, so no argument or callee-saved register is disturbed."
echo "  Result: libmsys-2.0.a builds (1,437,942 bytes); printf/exit/malloc/main/"
echo "  cygwin_crt0 all present."
echo
echo "## THE EXECUTABLE"
echo "  int main (void) { return 77; }   -- 77 chosen so a pass cannot be"
echo "  confused with an accidental 0."
echo "  built: crt0.o + rung3.c + libmsys-2.0.a + libgcc + libkernel32"
echo "  rung3.exe  58,975 bytes  sha256 093819b536bece179bf18304e50c31b29498837755cb3f06c628d709dff3ab5b"
echo "  file format pei-aarch64-little, architecture aarch64, EXEC_P"
echo "  imports: KERNEL32.dll and msys-2.0.dll"
echo
echo "## IT RAN"
echo "  runtime used: msys-2.0.dll sha256 3d305115... (the ctor-fixed build,"
echo "  identity verified by hash against msys-2.0-ctorfix.dll before running)."
echo
echo "  stack reserve 0x200000  (2 MB, default) -> exit -1073741571 = 0xC00000FD"
echo "                                             STATUS_STACK_OVERFLOW"
echo "  stack reserve 0x4000000 (64 MB)         -> exit -1073741819 = 0xC0000005"
echo "                                             STATUS_ACCESS_VIOLATION"
echo
echo "  The failure mode CHANGES with the stack reserve, so this is not a simple"
echo "  unbounded recursion: with more stack the process gets further before"
echo "  failing differently. Cygwin manages its own stack and places _cygtls at"
echo "  __CYGTLS_PADSIZE__ (12800) from the stack base, so the reserve interacts"
echo "  with runtime startup directly. NOT YET DIAGNOSED."
echo
echo "## WHAT THIS ESTABLISHES"
echo "  A native ARM64 MSYS2 executable is BUILT, LOADED, and EXECUTES far enough"
echo "  to reach the runtime's own startup code and fail inside it. The process"
echo "  starts; the loader binds msys-2.0.dll; DllMain completes; control reaches"
echo "  crt0/dcrt0. That is further than anything in this programme has gone."
echo
echo "## WHAT IT DOES NOT ESTABLISH"
echo "  main() DID NOT RUN. The expected exit code 77 was NOT observed."
echo "  RUNG 3 IS NOT PASSED. No user code has executed. fork(), signals and the"
echo "  sigfe trampolines remain unexercised. Not a working runtime, not a product"
echo "  pass, no authority."
} > $E/rung3-attempted.txt
head -16 $E/rung3-attempted.txt
