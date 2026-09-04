# 009 — wild-value region reclassification + ptmalloc-segment source

## ⚠ SUPERSEDED / CORRECTED (see below and checkpoint 011)
The reclassification in this checkpoint contained a FACTOR-OF-16 ERROR:
MMAP_STORAGE_LOW was written as 0x10000000000 (1024 GiB); the PRIMARY SOURCE
(memory_layout.h:51) is `0x001000000000` = 64 GiB. Re-derived from source, ALL nine wild
values (512–898 GiB) are INSIDE the MMAP arena [64 GiB, 114688 GiB) — c63ab774's ORIGINAL
mmap-arena label was correct. The "user-heap growth region" conclusion below and the
"ptmalloc SEGMENT base" wording are WITHDRAWN. What survives: the dlmalloc structural
negative (checkpoint 010), emutls negative, allocator-can't-clobber-head — all independent of
region labelling. Discipline note: GiB arithmetic was done off a mistyped constant and shipped
without re-opening the header; corrected against my own name.

## (original content below, retained for the record but region label is WRONG)


## Assignment (coordinator, endorsed)
Static search of memory_init()/user_heap.init() and callees for a rogue 8-byte store at
cygheap+8 (chain head). x86_64 differential now MEASURED (chain begins at cygheap+0x48A0 =
sizeof(init_cygheap), terminates NULL, 4/4 processes). Prioritise arch-varying address/size
in arch-neutral code.

## RESULT 1 — memory_init() is CLEAN (MEASURED)
memory_init() (mm/shared.cc:323) calls: shared_info::create, user_heap.init,
user_info::create(false), tty_list::init_session.
- user_heap_info::init (heap.cc:57): writes only base/chunk/ptr/top/max/page_const — all in
  the user_heap sub-struct at cygheap+18336. VirtualAlloc at USERHEAP_START=0xa00000000 (40GiB)
  or rare NULL fallback (heap.cc:121). No write near +8.
- open_shared (shared.cc:127): MapViewOfFileEx into SHARED_REGIONS [0x1a0000000,0x200000000)
  (~6.5GiB). Results stored to cygheap->shared_regions (+18376) at shared.cc:245/287. No +8.
- No 512-GiB-class address is produced anywhere in memory_init. So the clobber is NOT here.

## RESULT 2 — wild-value REGION CORRECTION (MEASURED, corrects checkpoint 008)
Re-classified all six observed wild prev values vs memory_layout.h bounds (GiB):
  THREAD_STORAGE [0x600000000,0x800000000)  24–32 GiB
  CYGHEAP        [0x800000000,0xa00000000)  32–40 GiB
  USERHEAP_START  0xa00000000               40 GiB (grows UP, no defined end)
  MMAP_STORAGE   [0x10000000000,0x700000000000) 1024–114688 GiB (grows DOWN)
  Observed: 0xBD102AE000=756.253G, 0xDDC4F01000=887.077G, 0x80002D1000/0x8000316000/
            0x8000384000/0x80002CA000=512.003 GiB (four clustered exactly at 512G+jitter).
=> NOT mmap arena (that's ≥1024 GiB) and NOT cygheap. They sit in the UNBOUNDED gap above
   USERHEAP_START and below MMAP_LOW — the user-heap growth region (memory_layout.h:43-46).
   Earlier "mmap arena" label was WRONG.

## RESULT 3 — SOURCE = ptmalloc user-heap SEGMENT BASE (MEASURED+DERIVED)
Only two unbounded VirtualAlloc(0,...) in the whole tree, both the USER malloc segment
allocators:
  mm/malloc.cc:1670 win32mmap        = VirtualAlloc(0,size,MEM_RESERVE|MEM_COMMIT,RW)
  mm/malloc.cc:1676 win32direct_mmap = VirtualAlloc(0,size,...|MEM_TOP_DOWN,RW)
Both lack MEM_ADDRESS_REQUIREMENTS → Windows chooses the address → ~512 GiB on ARM64.
Ruled OUT by their explicit bounds/fixed bases: pthread stacks (create_posix_thread.cc:158/175,
BOUNDED THREAD_STORAGE 24–32 GiB), mmap() proper (mmap.cc:1600, BOUNDED MMAP ≥1024 GiB),
shared regions (~6.5 GiB), user_heap base (40 GiB).
Also MEASURED: HAVE_MORECORE 0 (malloc.cc:547) → this ptmalloc uses NO sbrk/user_heap;
ALL system allocation goes through win32mmap/win32direct_mmap. Global mstate _gm_ is a static
struct (malloc.cc:2634), segment records live in _gm_.seg — not based off cygheap.
=> The value clobbering cygheap->chain is a ptmalloc SEGMENT BASE. Fits rung8 (printf/malloc/
   free) exactly. Tight 512.003-GiB clustering = stable first-segment base + per-run jitter.

## Structural crux restated
cygheap->chain (cygheap+8) has ONE writer (cygheap.cc:398) storing only _csbrk() results
(always in-cygheap). A 512-GiB ptmalloc-segment value there therefore proves either a
non-:398 STRAY 8-byte write to cygheap+8, or the head already held that stray value when :398
copied it into rvc->prev. Locating the stray writer needs c63ab774's dynamic before/after
probe (read cygheap+8 immediately before vs after the first user malloc); the static side
cannot enumerate an arbitrary mis-based store without it.

## Arch angle (framing preserved: "observed on ARM64, differential unknown")
The win32*mmap VirtualAlloc(0,...) are unbounded, so the address is ARCH-CHOSEN: ARM64 →
512 GiB; x86_64 may land where a downstream mis-based store is harmless. Exactly the
"arch-neutral code, arch-different address" shape the coordinator flagged as most promising.

## Handoff probe given to c63ab774
Read cygheap->chain (cygheap+8) immediately BEFORE and AFTER the first user malloc. If it
flips valid→512-GiB across that one call, the writer is in the ptmalloc segment-growth path
(win32mmap/win32direct_mmap or callers morecore/segment install). Also check whether any
ptmalloc segment/mstate record is mis-based off cygheap.

## Files (READ-ONLY, none edited)
- mm/shared.cc: memory_init@323, open_shared@127 (MapViewOfFileEx@167), user_info::create@221
  (store@245), shared_info::create@278 (store@287)
- mm/heap.cc: user_heap_info::init@57 (VirtualAlloc@75/113/121; writes base/ptr/top/max@129-131)
- mm/malloc.cc: win32mmap@1670, win32direct_mmap@1676, HAVE_MORECORE 0 @547, _gm_@2634,
  MMAP_DEFAULT@1699, DIRECT_MMAP_DEFAULT@1701
- create_posix_thread.cc: _alloc@142 (thread_req THREAD_STORAGE@144, VirtualAlloc2@158/175)
- mm/mmap.cc: fhandler_dev_zero::mmap@1567 (mmap_req MMAP_STORAGE@1590, VirtualAlloc2@1600)
- local_includes/memory_layout.h:34-52 region constants
- DWARF offset map source: /root/xc/w-link/bld/winsup/cygwin/mm/cygheap.o
