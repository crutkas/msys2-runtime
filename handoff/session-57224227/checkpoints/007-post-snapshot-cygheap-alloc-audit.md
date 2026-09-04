# 007 — Post-snapshot cygheap-allocation audit (fork window)

## Assignment (coordinator 2b2e50a5)
Correction: my truncation mechanism is wrong — fault target 0xBD102AE000 is OUTSIDE the
cygheap region (0x800000000–0xa00000000), so not a short-copy artefact. But my structural
note (post-snapshot cygheap alloc) is the live lead. ENUMERATE every cygheap allocation
between refresh_cygheap() (fork.cc:338) and the child's copy, and for each ask whether its
size/COUNT can differ on ARM64. If total identical both arches, dismissal proven; else
mechanism found. Coordinator's sharpening: "shared code can fail arch-specifically if the
AMOUNT allocated after the snapshot differs by arch" — don't dismiss on "breaks x86_64 too"
(true of the code, not the data). Read-only.

## Window
Parent fork.cc:338 (refresh_cygheap snapshots ::cygheap_max into child_info) →
fork.cc:410 (ch.sync blocks until child signals init; child runs handle_fork →
cygheap_fixup_in_child → child_copy = ReadProcessMemory of [cygheap_base, cygheap_max)).
Any parent cygheap alloc in this window advances the real chain past the snapshot.

## RESULT: ZERO cygheap allocations in the parent window — lead KILLED BY MEASUREMENT
Cygheap allocators that advance cygheap_max: cmalloc/cmalloc_abort/ccalloc/ccalloc_abort/
crealloc/crealloc_abort/cstrdup/cstrdup1/cwcsdup/cwcsdup1/cnew/_csbrk (all mm/cygheap.cc).
cfree/_cfree do NOT advance (bucket return) — ignored.

Per-call-site (each callee opened 2–3 levels, MEASURED):
- 339 ch.prefork() (fork.cc:117) — CreatePipe/SetHandleInformation/ProtectHandle1. No alloc.
- 341 dlls.setup_forkables() (dll_init.h:149) → request_forkables() (forkable.cc:937):
  ENTIRELY gated on forkables_supported() == cygwin_shared->forkable_hardlink_support>=0
  (FILESYSTEM property, NOT arch). Subcalls prepare_forkables_nomination (558) &
  update_forkables_needs (618) use nt_max_path_buf() (STATIC buffer) + string/flag ops only.
  update_forkables/create_forkables only if !forkables_created.
  *** KEY: the only cmalloc in the forkable path (forkable.cc:540, in forkable_ntnamesize
  @465) has the comment "allocate here, to avoid cygheap size changes during fork" and is
  reached ONLY from dll_list::alloc (dll_init.cc:348) at DLL-LOAD time — deliberately hoisted
  OUT of the fork window BY DESIGN. Authors already defended against this exact mechanism.
- 346 sec_user_nih() — fills caller's 1024B alloca buffer; RtlCreateSecurityDescriptor. No alloc.
- 355 buffered_shortname() (dll_init.h:123) — static nt_max_path_buffer. No alloc.
- 366 CreateProcessW() — Win32; child suspended; no cygwin code in parent. No alloc.
- 392/394 fdtab.need_fixup_before()/fixup_before_fork() (dtable.cc:1102) — loop runs only if
  cnt_need_fixup_before>0 (sockets needing WSADuplicateSocket into pre-alloc'd prot_info_ptr);
  no cygheap alloc; not reached at all for trivial std-handle-only rung-5 process.
- 401 release_forkables() (forkable.cc:961) — SetHandleInformation only. No alloc.

ARCH DIFFERENTIAL: none. No arch-conditional #ifdef in any window callee. All forkable
allocs hoisted to DLL-load. Count-dependent quantities (DLL count, fd count) not arch-varying
for the same test program. Coordinator's sharpened form does not apply: amount allocated
after snapshot is ZERO on BOTH arches.

## Consequence for the fault (reported to c63ab774)
Parent does not grow cygheap in-window ⇒ the bad `prev` (0xBD102AE000) was copied FAITHFULLY
from the parent. Not truncation. Either (a) garbage already in the parent's chain at that
offset, or (b) a legitimate PARENT pointer into non-cygheap memory the child lacks. c63ab774's
parent-vs-child same-offset comparison discriminates: if parent bytes there already ==
0xBD102AE000, corruption predates copy (parent-side); if differ, copy/child-side write mangled it.

## Method note applied
Coordinator named the failure shape "true of the code, not necessarily true of the data flowing
through it" (same class as its own earlier "changing failure mode rules out recursion" error).
Applied it: did NOT let the shared-code argument stand as the dismissal; measured the data.
Outcome changed from "set aside" to "measured zero".

## Files (READ-ONLY, none edited)
- fork.cc: frok::parent window 338–410; prefork@117; child_copy@731
- local_includes/dll_init.h: setup_forkables@149, forkables_supported@84, buffered_shortname@123
- forkable.cc: forkable_ntnamesize@465 (cmalloc@540 + comment@539), prepare_forkables_nomination@558,
  update_forkables_needs@618, request_forkables@937, release_forkables@961
- dll_init.cc:348 (forkable_ntnamesize call site @ DLL-load)
- dtable.cc: fixup_before_fork@1102; dtable.h need_fixup_before
- mm/cygheap.cc: allocator surface @462–577, _csbrk@326, _cmalloc@365
