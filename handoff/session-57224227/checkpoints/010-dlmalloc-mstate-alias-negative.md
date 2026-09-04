# 010 — dlmalloc mstate/segment-list aliasing of cygheap+8: CLEAN NEGATIVE

## Assignment (coordinator, endorsed)
Determine where dlmalloc's mstate (_gm_) lives and whether its segment list (whose heads hold
512-GiB win32mmap segment bases — the exact class of value seen in cygheap->chain) can alias
cygheap+8. Four sub-questions: (1) _gm_ location — static or base-computed? (2) offsetof(seg)?
(3) any relation of dlmalloc state to cygheap (user_heap_info @ +18336)? (4) MALLOC_ALIGNMENT
LP64 correctness. Prior: mm/malloc_wrapper.cc already carried an ARM64 defect (import_address
0x25ff), so the malloc subsystem's prior for another x86 assumption is elevated.

## RESULT — hypothesis is a CLEAN STRUCTURAL NEGATIVE
1. _gm_ LOCATION (MEASURED, nm on built ARM64 malloc.o):
   `_ZL4_gm_`  → symbol type 'b' = .bss, bss-offset 0 (static/local zero-init in DLL BSS).
   `_ZL7mparams` → 'b' at bss+0x3b0.
   NOT computed from a base, NOT absolute, NOT cygheap-relative. mstate + entire segment list
   live at fixed DLL image-data addresses → CANNOT alias cygheap+8 (0x800000008, 32-GiB
   VirtualAlloc region). No offset error off _gm_ can reach the cygheap.
2. LAYOUT (MEASURED, DWARF): sizeof(malloc_state)=936; offsetof(malloc_state, seg)=888.
   _gm_.seg at BSS+888; its base/next (the segment-base holders) at BSS+888/+904 — fixed image
   data, nowhere near cygheap+8. struct malloc_segment {char* base; size_t size; msegment*
   next; flag_t sflags} — LP64-clean.
3. dlmalloc↔cygheap RELATION: none. init_cygheap holds user_heap_info user_heap @ +18336, BUT
   HAVE_MORECORE 0 (malloc.cc:547) → this dlmalloc uses NO sbrk/user_heap; all system memory
   comes from win32mmap/win32direct_mmap into _gm_. user_heap_info is vestigial here. NO writer
   stores a dlmalloc segment head through a cygheap base → the "should be +18336 but lands at
   +8" mechanism has no actual writer.
4. MALLOC_ALIGNMENT (malloc.cc:575) = 16U = 2*sizeof(void*) on LP64 ARM64 — CORRECT.
   CHUNK_ALIGN_MASK=15. Alignment/size macros clean; malloc_state is all size_t/pointer fields,
   LP64-identical to x86_64.

## malloc_wrapper.cc sweep (elevated-prior file)
Only READS user_data->malloc/free/realloc/calloc/posix_memalign (function pointers) and calls
them (lines 74/88/105/133/152); WRITES nothing to cygheap or any cygheap-based address.
import_address (:49-64) is a pure reader. NOTE: in this READ-ONLY tree import_address still
shows the bare `*(uint16_t*)imp == 0x25ff` check with NO aarch64 branch (:53); c63ab774's
decode-the-thunk fix lives in ITS tree, not here — expected, not my edit. malloc_wrapper.cc is
NOT the stray writer.

## Conclusion / handoff
dlmalloc does NOT write its segment list onto the cygheap; its bookkeeping writes only into
_gm_ at BSS+888. The 512-GiB value in cygheap->chain is a genuine dlmalloc segment base, but
the WRITE placing it at cygheap+8 is performed by OTHER code that PROPAGATES that value (reads
a malloc return or _gm_.seg.base and stores it via a pointer mis-resolving to cygheap+8).
Static enumeration cannot pin an arbitrary mis-based store without an anchor; c63ab774's
before/after-first-malloc read of cygheap+8 names the exact call in one shot. Framing preserved:
observed on ARM64, arch-differential unknown.

## Files (READ-ONLY, none edited)
- mm/malloc.cc: MALLOC_ALIGNMENT@575, malloc_segment@2471, malloc_state@2581 (seg@2601),
  _gm_@2634, mparams@2626, HAVE_MORECORE 0 @547, win32mmap@1670, win32direct_mmap@1676
- mm/malloc_wrapper.cc: import_address@49, free/malloc/realloc/calloc wrappers@69-160,
  use_internal decision@320-322
- Built objects: /root/xc/w-link/bld/winsup/cygwin/mm/malloc.o (nm + DWARF source)
