# 005 — cygheap fork child_copy / cygheap_max audit

## Assignment
c63ab774 offered (coordinator-adjacent) static read of `child_copy` and what bounds
`cygheap_max` in the forked child, to explain the fork crash in
`cygheap_fixup_in_child` (mm/cygheap.cc:113) walking `cygheap->chain` onto an
unmapped `prev` pointer. Read-only.

## Result: CORRECT NEGATIVE (arch-clean, LP64-identical to x86_64)
Same category as the `_cygtls` and `create_new_main_thread_stack` exonerations.
The code on the fault path is NOT the defect; the fault is a downstream consequence
of corrupted child state fed in upstream.

## MEASURED facts
- `_cmalloc_entry` (local_includes/cygheap.h:15): `union{unsigned b; char*ptr;}`=8B on
  LP64, `_cmalloc_entry *prev`@+8, `char data[0]`@+16. Identical x86-64/ARM64 (both LP64).
- `child_info` (child_info.h:48): checksummed layout, `cygheap`/`cygheap_max` plain 8B
  pointers, no packing. Transferred intra-build so parent/child agree by construction.
- Constants (memory_layout.h:39-41): CYGHEAP_STORAGE_LOW=0x800000000,
  INITIAL=0x800300000, HIGH=0xa00000000. cygheap base==LOW (fixed, both processes,
  VirtualAlloc @92/96). c63ab774's measured x22=0x800300000==INITIAL confirms constants live.
- Commit (cygheap.cc:87-91): default INITIAL-LOW=0x300000; grows to
  allocsize(cygheap_max-LOW) if cygheap_max>INITIAL. allocsize rounds up to 64K granularity.
- child_copy (fork.cc:731): bare ReadProcessMemory of [cygheap, cygheap_max). Pointer-clean,
  arch-independent. Committed region ⊇ copied region. Self-consistent.
- Chain-walk fault (cygheap.cc:113): can only fault if a chain `prev` lands ABOVE the
  committed/copied cygheap_max => child's cygheap_max short of chain's true extent.
  Byte-identical to x86_64 path (which forks fine) => shortfall, if real, is fed by
  ARCH-SPECIFIC upstream corruption, not this arithmetic.

## Structural note (NOT arch-specific — flagged, not asserted)
`refresh_cygheap()` (fork.cc:338) snapshots ::cygheap_max under cygheap->lock BEFORE
setup_forkables (341) and later cygheap-touching work. A post-snapshot _csbrk would make
the child snapshot stale-low and put the newest (highest) chain entry above the copied
range — matches the fault signature. But it would break x86_64 too, so unlikely to be
THE ARM64-specific cause alone.

## x18=0 lead (c63ab774's) — static corroboration only, did NOT build on it
Source writes x18 NOWHERE. Only sites: config.h:50 `mov %0,x18` (__getreent TEB read),
exceptions.cc:283 prints ctx->X18. All other 0x18 = immediate/ASCII false positives
(autoload.cc `0x18(%rsp)` x86-only, spawn.cc buf[0x18], etc.). So a genuine child x18=0
was NOT produced by Cygwin — Windows owns x18 for a natively-created thread. Leaves exactly
c63ab774's two undecidable-without-control possibilities: (a) GetThreadContext doesn't report
the platform register faithfully, (b) wrong faulting thread. Not resolvable statically.

## Bottom line
Fork defect is UPSTREAM of cygheap_fixup_in_child (stale/short cygheap_max in the child_info
record, or arch-specific state incl. possibly the x18/TEB thread question, unproven).
Reported to c63ab774 and 2b2e50a5. Read-only throughout; zero edits this session.

## Files (all READ-ONLY, none edited)
- mm/cygheap.cc: cygheap_fixup_in_child@85, chain-walk@113, _csbrk@326, _cmalloc@365
- fork.cc: child_copy@731, refresh_cygheap call@338, frok::child@135
- dcrt0.cc: handle_fork@585 (cygheap_fixup_in_child@587 first), alloc_stack@405
- local_includes/cygheap.h:15 (_cmalloc_entry), child_info.h:48 (child_info), :75 refresh_cygheap
- local_includes/memory_layout.h:39-41 (constants)
- include/cygwin/config.h:50 (x18 TEB read)
