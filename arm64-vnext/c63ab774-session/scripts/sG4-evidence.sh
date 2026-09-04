#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
F=$D/frozen-rung5
{
echo "# ARM64 vNext -- RUNG 5: SIGNALS PASS, fork() LOCALISED"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   session c63ab774"
echo
echo "## RUNG 5a -- SIGNALS -- PASSED"
echo "  signal(SIGUSR1,h); raise(SIGUSR1); handler observed to run."
echo "    handler installed"
echo "    raise returned"
echo "    handler RAN, signal=30      (30 = SIGUSR1 on Cygwin)"
echo "  exit 55 as designed."
echo "  THIS IS THE FIRST EXECUTION OF THE sigfe TRAMPOLINES. Three sessions"
echo "  reproduced that artefact byte-identically; none had ever run it."
echo
echo "## RUNG 5b -- fork() -- FAILS, BUT FAILS HONESTLY AND FAR IN"
echo "  parent pid=1727, about to fork"
echo "  dofork: child -1 - forked process 75656 died unexpectedly,"
echo "          retry 0, exit code 0xC0000005, errno 11"
echo "  FAIL: fork() returned -1"
echo
echo "  WHAT ALREADY WORKS, MEASURED:"
echo "   - getpid() returns a real Cygwin pid"
echo "   - fork() reaches dofork and CREATES the child Windows process"
echo "   - the child loads the DLL and executes Cygwin initialisation"
echo "   - the PARENT's own diagnostic machinery formats a correct Cygwin"
echo "     error message and returns -1/EAGAIN, which is correct behaviour"
echo "     on fork failure. The failure path itself is working."
echo
echo "## THE CHILD'S FAULT, CAPTURED WITH A FORK-AWARE DEBUGGER"
echo "  Harness rewritten to DEBUG_PROCESS (was DEBUG_ONLY_THIS_PROCESS) so it"
echo "  follows the child, with a process handle per pid so VirtualQueryEx"
echo "  resolves modules IN THE FAULTING PROCESS, not the parent."
echo
echo "   CHILD pid=85840  EXCEPTION 0xC0000005 (first chance)"
echo "   ACCESS_VIOLATION READ target=0x000000BD102AE000   NOT COMMITTED"
echo "   PC = msys-2.0.dll RVA 0xAA7B8      SP 16-aligned: YES"
echo "   LR = msys-2.0.dll RVA 0xAA784"
echo "   x19 = 0x000000BD102AE000  (the faulting pointer)"
echo "   x22 = 0x0000000800300000  = CYGHEAP_STORAGE_INITIAL"
echo
echo "  ImageBase read from the header (0x180040000), never assumed:"
echo "   RVA 0xAA7B8 -> VA 0x1800EA7B8"
echo "   addr2line: cygheap_fixup_in_child(bool)  mm/cygheap.cc:116"
echo "   LR  0xAA784 -> cygheap.cc:106, same function"
echo
echo "  The source at that line:"
echo "    113  for (_cmalloc_entry *rvc = cygheap->chain; rvc; rvc = rvc->prev)"
echo "    115    cygheap_entry *ce = (cygheap_entry *) rvc->data;"
echo "    116    if (!rvc->ptr || rvc->b >= NBUCKETS || ce->type <= HEAP_1_START)"
echo
echo "  Disassembly confirms the walk and shows it had already iterated"
echo "  successfully at least once (x0 = 3, a plausible bucket index) before"
echo "  a prev-pointer led to unmapped memory:"
echo "    1800ea790  ldr x19, [x0, #8]        ; rvc = cygheap->chain"
echo "    1800ea7b0  ldr x19, [x19, #8]       ; rvc = rvc->prev"
echo "    1800ea7b8  ldr x0,  [x19]           ; <== FAULTED, rvc unmapped"
echo "    1800ea7c4  cmp w0, #0x1f            ; rvc->b >= NBUCKETS (32)"
echo
echo "  So: after child_copy() and cygheap_init(), the cygheap allocation chain"
echo "  in the child contains a pointer to memory that is not mapped in the"
echo "  child. The chain is partially valid and then goes bad."
echo
echo "## WHAT I CHECKED AND RULED OUT"
echo "  memory_layout.h CYGHEAP_STORAGE_LOW/INITIAL/HIGH are NOT arch-conditional"
echo "  (0x800000000 / 0x800300000 / 0xa00000000, no #ifdef). x22 holding"
echo "  0x800300000 confirms the child is using the correct constants. So this"
echo "  is NOT another instance of the x86-fallthrough pattern."
echo
echo "## STRONGEST REMAINING LEAD, WITH ITS CAVEAT STATED"
echo "  x18 = 0x0000000000000000 IN THE FAULTING CHILD THREAD."
echo "  On Windows on Arm x18 IS the TEB and is platform-reserved; this runtime"
echo "  depends on it (the __getreent fix earlier this programme changed"
echo "  'mrs tpidr_el0' to x18 precisely because x18 is the TEB here). A child"
echo "  thread resumed with x18 = 0 would have no TEB."
echo "  CAVEAT, NOT YET ELIMINATED: x18 is platform-reserved, and it is not"
echo "  established that GetThreadContext reports it faithfully rather than"
echo "  returning zero for a register Windows manages itself. I have ONE sample"
echo "  and no control. DO NOT TREAT THIS AS A FINDING. The control needed is"
echo "  a captured context from a thread known to be healthy in the same"
echo "  process, compared against this one."
echo
echo "## FROZEN ARTEFACT PAIR (coordinator policy: freeze before diagnosing)"
sha256sum $F/rung5.exe $F/rung6.exe $F/msys-2.0.dll 2>/dev/null | sed "s|$F/||"
echo
echo "## HARDENING APPLIED THIS SESSION (sibling 57224227 findings, both latent)"
echo "  cygwin.sc.in:82  .xdata placement now '#if defined(__x86_64__) ||"
echo "    defined(__aarch64__)' so exception-unwind placement is EXPLICIT rather"
echo "    than relying on the linker's orphan-section heuristic. Verified: .xdata"
echo "    present, Exception Directory RVA 0x2d5000 size 0xbab8 matches .pdata."
echo "  pseudo-reloc.cc  3 guards now name __aarch64__ directly instead of"
echo "    depending on _WIN64 arriving from the w32api header fix."
echo "  REGRESSION CHECKED: rung3 3/3 exit 77, rung4 exit 42 with correct stdout,"
echo "  after relinking with both changes. No regression."
echo
echo "## HONEST STATUS"
echo "  PASS: process start, runtime init, main(), malloc/free, printf/stdout,"
echo "        signal handlers via the sigfe trampolines."
echo "  FAIL: fork()."
echo "  UNTESTED: pthreads, exec, pipes, any real MSYS2 program (bash, coreutils)."
echo "  This is NOT a product pass and creates NO authority. No commits, pushes,"
echo "  PRs, CI or upstream contact."
} > $E/rung5-signals-pass-fork-localised.txt
wc -l $E/rung5-signals-pass-fork-localised.txt
