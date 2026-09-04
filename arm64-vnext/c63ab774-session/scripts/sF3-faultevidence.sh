#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- RUNG 3 FAULT LOCALISED: RECURSION THROUGH calloc"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   session c63ab774"
echo
echo "## CAPTURED WITH THE WIN32 DEBUG API (DEBUG_ONLY_THIS_PROCESS)"
echo "  EXCEPTION 0xC00000FD STACK_OVERFLOW  (first chance, then second chance)"
echo "    PC = 0x00007FFDAF96FBA0   msys-2.0.dll base=0x7FFDAF8C0000 RVA=0xAFBA0"
echo "    LR = 0x00007FFDAF96FBD8   msys-2.0.dll RVA=0xAFBD8"
echo "    SP = 0x00000007FFE05030   16-BYTE ALIGNED: YES (sp & 15 = 0)"
echo "  Module base resolved with VirtualQueryEx at fault time, not assumed."
echo
echo "## ALIGNMENT HYPOTHESIS REFUTED"
echo "  SP is correctly 16-byte aligned, so this is NOT an AArch64 stack-alignment"
echo "  violation. Also refuted separately: sizeof(_cygtls) = 5016 vs"
echo "  __CYGTLS_PADSIZE__ = 12800, so the TLS pad is not undersized."
echo
echo "## THE FAULTING INSTRUCTION IS A STACK PROBE INSIDE calloc"
echo "  00000001800efb9c <calloc>:"
echo "     1800efb9c:  sub  x10, sp, #0x2, lsl #12     // x10 = sp - 0x2000"
echo "     1800efba0:  str  xzr, [x10, #4032]          // <== FAULTED, probes sp-0x1040"
echo "     1800efba4:  adrp x2, 180230000"
echo "     1800efba8:  stp  x29, x30, [sp, #-64]!"
echo "     ..."
echo "     1800efbb0:  ldrb w2, [x2, #2352]            // dispatch flag"
echo "     1800efbc8:  tbnz w2, #0, ...                // if set, take other path"
echo "     1800efbcc:  adrp x2, 18021e000 <__data_start__>"
echo "     1800efbd0:  ldr  x2, [x2, #2872]            // load a FUNCTION POINTER"
echo "     1800efbd4:  blr  x2                         // call through it"
echo "     1800efbd8:  <-- LR POINTS HERE"
echo
echo "## WHY THIS IS RECURSION, NOT A DEEP CALL CHAIN"
echo "  PC is at calloc+0x4 (its prologue probe)."
echo "  LR is at calloc+0x3C, i.e. the return address of the 'blr x2' INSIDE calloc."
echo "  So calloc dispatched through a function pointer and control came back"
echo "  round into calloc's own prologue. calloc is calling itself indirectly."
echo "  The stack probe is simply the first instruction to notice the stack is"
echo "  exhausted -- it is the symptom, not the cause."
echo
echo "  This is the malloc-interposition path: a flag byte selects between the"
echo "  internal allocator and an exported/overridden one, and the ARM64 build"
echo "  appears to resolve the override back to itself. NOT YET PROVEN -- the flag"
echo "  and the function pointer have not been read at runtime."
echo
echo "## CONSISTENT WITH THE STACK-RESERVE EXPERIMENT"
echo "  2 MB reserve  -> STACK_OVERFLOW (guard page hit sooner)"
echo "  64 MB reserve -> ACCESS_VIOLATION (recursion runs longer, dies differently)"
echo "  Unbounded recursion explains both, and explains why more stack does not help."
echo
echo "## NEXT STEP (not done)"
echo "  Read, at runtime, the dispatch flag at 0x180230000+2352 and the function"
echo "  pointer at __data_start__+2872, and identify what the pointer resolves to."
echo "  If it points at calloc itself, the diagnosis is proven."
echo
echo "## STATUS"
echo "  main() still does not run. Exit 77 never observed. RUNG 3 NOT PASSED."
} > $E/rung3-fault-localised.txt
head -12 $E/rung3-fault-localised.txt
