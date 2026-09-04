# 011 — emutls negative, MMAP re-derivation correction, allocator-can't-clobber-head

## Context
c63ab774: corruption is PARENT-side and needs NO app allocation — rung9 (no user malloc, no
stdio, body = one deliberate fault) has the identical 39-entry corrupt chain, lowest surviving
entry 0x8000068F0, prev wild. Chain STARTS correct (watchpoint on head: 0 -> 0x8000048A0 ->
0x800050B0) then is clobbered later. x86-64 differential MEASURED by c63ab774: chain terminates
NULL at exactly cygheap+sizeof(init_cygheap)=0x48A0, 4/4 processes; ARM64 lowest entry 0x68F0,
0x2050 higher, wild terminator. Bad value shape (c63ab774): 0x80002D1000 = 0xD1000 into a
committed region based at 0x8000200000 → an allocated CHUNK pointer (derived).

## RESULT A — EMUTLS killed by measurement (coordinator's secondary lead)
- COMPILER: aarch64-pc-cygwin gcc emits `bl __emutls_get_address` + __emutls_v/__emutls_t for
  a __thread probe (MEASURED, /tmp asm). gcc is --disable-threads (MEASURED, gcc -v).
- __emutls_get_address DOES allocate: with --disable-threads the single-thread branch runs
  `if (obj->loc.ptr==NULL) obj->loc.ptr = emutls_alloc(obj)` and emutls_alloc calls malloc()
  (emutls.c:110-141,148-155). So it stores a malloc return into obj->loc — an allocator-return
  value stored through a pointer. Structurally the right shape.
- BUT the RUNTIME never uses it. MEASURED, airtight: Cygwin source has ZERO __thread/
  _Thread_local; 273 built objects (recursive incl mm/) + both new-msys-2.0.dll and -fixedbase
  have ZERO __emutls_get_address refs, ZERO __emutls_v objects, ZERO 'emutls' strings. Objects
  NOT stripped (cygheap.o shows U malloc/VirtualAlloc; DLL 288k symbols). => never called at
  startup; cannot be the writer.
  NOTE (TLS correction, binding): Cygwin does NOT use tpidr_el0 — that register reads ZERO on
  Windows-on-ARM (measured twice by c63ab774; AV at address 8). The correct TEB path is x18
  (read directly via `mov reg,x18`, NEVER write x18, NEVER use tpidr_el0). The earlier
  __getreent fix replaced `mrs %0,tpidr_el0` with `mov %0,x18`; sigfe.s uses `mov x16,x18`.
  Any description saying "tpidr_el0" is stale and must not be reintroduced.
- Also: DWARF sizeof(__emutls_object)=32, members size@0/align@8/loc@16/templ@24 — the malloc
  store lands at obj+16, not obj+8, even hypothetically.
- Caveat: c63ab774 saw emutls.o pulled at ITS link; that must be a different link config (test/
  libstdc++ harness) — absent from the runtime objects measured here. Flagged for reconciliation.

## RESULT B — MMAP re-derivation CORRECTION (my error, owned)
Checkpoint 009 mis-stated MMAP_STORAGE_LOW as 0x10000000000 (1024 GiB). PRIMARY SOURCE
memory_layout.h:51 = `0x001000000000` = 64 GiB (factor-of-16 typo, extra zero). Re-derived:
all NINE wild values are INSIDE the MMAP arena [64, 114688) GiB:
  0xBD102AE000=756.3G 0xDDC4F01000=887.1G 0xC493967000=786.3G 0xE0A3FDF000=898.6G
  0x80002D1000 0x8000316000 0x80002CA000 0x8000351000 0x8000384000 = 512.003 GiB.
c63ab774's ORIGINAL mmap-arena label was correct; my "user-heap growth region" reclassification
(chkpt 009) is WITHDRAWN, as is the "ptmalloc SEGMENT base" wording that rested on it.
Discipline note: GiB math done off a mistyped constant, shipped in two reports without
re-opening the header. Corrected against my own name. A correction is a claim; re-derived from
source.
MMAP producers (MEASURED): mmap.cc:1590/1600 private-anon (bounded MMAP), create_posix_thread.cc
:165/175 thread-stack fallback (bounded MMAP), malloc.cc:1670/1676 win32mmap/win32direct_mmap
(unbounded VirtualAlloc(0,...), Windows top-down → high). Region label no longer discriminates
chunk-vs-segment.

## RESULT C — the cygwin allocator CANNOT clobber the head (foreign store confirmed)
- `cygheap` global only ever = &cygheap_dummy or VirtualAlloc(CYGHEAP_STORAGE_LOW)
  (cygheap.cc:35/92/96/293/297); never transiently elsewhere. So :398 `cygheap->chain=rvc`
  always targets 0x800000008. A heap-chunk value there is genuinely foreign.
- _cmalloc reuse path (:381-386) writes only +0 (rvc->ptr/rvc->b), does NOT re-chain, does NOT
  touch prev(+8). Fresh path (:396-398) is the ONLY chain extender. _cfree (:410) threads the
  freelist via +0 and NEVER unlinks from the chain. So chain(+8) and freelist(+0) are disjoint;
  entries are chained once at birth and never removed. Neither _cmalloc nor _cfree can write a
  foreign value into an existing prev(+8) or the head.
- cygheap_fixup_in_child chain walk (:113 `rvc=rvc->prev`) is the fault VICTIM, not the writer:
  corruption is parent-side (rung9), so this walk merely trips over an already-wild prev.

## Discriminator handed to c63ab774 (chunk vs segment, by measurement)
_gm_ is .bss; offsetof(malloc_state,seg)=888; malloc_segment={char* base@0; size_t size@8;
msegment* next@16; flag_t sflags@24}. Read seg.base=*(void**)(_gm_+888), seg.size=*(_gm_+896),
walk next@+904. For each wild V: base<=V<base+size ⇒ CHUNK inside that dlmalloc segment;
V==base ⇒ segment base. c63ab774's 0xD1000-offset measurement predicts CHUNK.

## RESULT D — offset-8 enumeration + cygheap-alias hypotheses (MEASURED negatives)
Coordinator PRIMARY task: every startup store of an allocator result into a struct field at +8.
- FULL init_cygheap member map (DWARF, cygheap.o): within first 64B only lh_first@0, chain@8,
  buckets@16. Later pointer fields: user_heap@18336, shared_regions@18376, fdtab@18480,
  sigs@18528, ctty@18536, threadlist@18544, sthreads@18552, inode_list@18560, hooks@18568,
  installation_root@272, root@16744, dom@16752. NOTHING but chain lands at +8; no field store
  can reach +8 by a small offset slip (nearest neighbours are 0 and 16).
- The ONLY init_cygheap field that receives an allocator return in startup is threadlist@18544
  (init_tls_list ccalloc_abort, cygheap.cc:647) and sthreads/sigs — all far from +8.
- buckets[b] store (cygheap.cc:384 reuse path) writes an allocator-derived value, but b is
  unsigned, bounded [0,NBUCKETS) (check @377), computed by __builtin_clzl on a 64-bit long —
  LP64-IDENTICAL on x86-64/ARM64 (constants 59/62 encode 64-bit; unsigned long is 8B on both).
  buckets[b] can never index to +8 (needs b=-1). Chain write @398 correct.
- Broadened alloc-return-assignment sweep across 18 startup .cc (perl multiline join): the only
  direct struct-field targets are uinfo.cc tdom[].DomainSid / new_tdom->DomainSid / path.Buffer
  (fields of caller structs fdom_t/UNICODE_STRING, bases are locals, NOT cygheap-aliasable) and
  dll_init d->deps / dtable archetypes (post-clobber-window, dll/dtable structs, not cygheap).
  None stores into a +8 field of a cygheap-confusable base.
- COORDINATOR POINT-2 (a structure overlaid on the cygheap base whose +8 means something else):
  MEASURED NEGATIVE. grep of all mm/*.cc + *.cc + local_includes/*.h finds ZERO casts of the
  `cygheap` base to another type, and ZERO `lvalue = (T*)cygheap` handing the bare base to a
  non-init_cygheap pointer. `cygheap` is only ever used as init_cygheap*. No alias exists through
  which a +8 store could mean something other than chain.
=> The foreign writer stores through a base that is NOT `cygheap` in source (no alias/overlay
  exists) yet RESOLVES to cygheap+8 at runtime — i.e. an out-of-bounds / miscomputed store from
  a DIFFERENT base (a nearby global/array indexed out of range, or a struct instance that on
  ARM64 sits near the cygheap). This class cannot be enumerated statically without the faulting
  PC. The constant-independent static surface is now exhausted.

## RESULT E — address-map adjacency (MEASURED, primary source, constant-independent)
memory_layout.h: THREAD_STORAGE_HIGH == CYGHEAP_STORAGE_LOW == 0x800000000. The cygheap sits
IMMEDIATELY above the thread-stack arena [0x600000000,0x800000000). chain@8 = 0x800000008 — i.e.
8 bytes above the thread/cygheap boundary. This is the one structural fact that makes a
mis-based store landing on cygheap+8 plausible: a base near the boundary (a thread-stack-relative
or boundary-adjacent pointer) written with a positive small offset reaches 0x800000008. It also
fits the arch angle — OS-chosen thread-stack placement differs on ARM64, so a boundary-adjacent
store harmless on x86-64 can hit the cygheap header on ARM64. NOT a claim of the writer; a
prior that raises boundary-adjacent stores (and anything holding a thread-stack/TEB-derived
base) above generic candidates for c63ab774's PC triage.

## RESULT F — buckets[-1] == chain mechanism: MEASURED NEGATIVE (constant-independent)
Coordinator's exact-coincidence idea: buckets@16, chain@8 ⇒ buckets[-1] IS chain. Searched
every index that could reach -1.
- `buckets` referenced in EXACTLY 6 sites, ALL in cygheap.cc: 381/383/384 (_cmalloc), 410/411
  (_cfree). No other file indexes buckets. It is the only array in the init_cygheap header
  region (only thing at +16).
- _cmalloc_entry (cygheap.h:15): union{unsigned b; char* ptr}@0, prev@8, data@16. `b` is
  UNSIGNED in its declaration — there is no signed index anywhere.
- _cmalloc (368-378): b computed by __builtin_clzl, guarded `if (b>=NBUCKETS) return NULL`
  before any buckets[b]. Cannot be negative (unsigned) nor >=32.
- _cfree (409): `unsigned b = rvc->b`; buckets[b] at 410/411. b read from the entry's +0 union
  slot, set bounded at allocation (_cmalloc 385/396). Fork walk (116) even guards
  `rvc->b >= NBUCKETS` before trusting it.
- _crealloc (423): bucket_val[rvc->b] — a READ of a static table, not a store to buckets; still
  unsigned index.
- to_cmalloc (64): (char*)s - offsetof(data) = s-16. Pure subtraction, no indexing.
- NBUCKETS=32.
=> No `b-1`, no signed temporary, no decrement-past-zero, no size-underflow feeding an index.
The exact buckets[-1]==chain coincidence has NO code path that realizes it. Idea dies properly.

## STATIC LINE CLOSED — remaining non-static task (unowned, per coordinator)
All constant-independent static angles exhausted: allocator clean (chain writer + buckets index
both bounded/LP64), no init_cygheap field near +8, no cygheap alias/overlay, emutls absent,
buckets[-1] impossible, address-map adjacency noted as a prior only. The source never names the
destination (cygheap+8), so the writer is a miscomputed/OOB store from an unrelated base — not
statically enumerable; needs c63ab774's runtime PC.
The single largest remaining WEAKNESS in the runtime finding: ARM64-specificity was established
by differential against Git-for-Windows' shipped x86_64 msys-2.0.dll 3.6.9 — a DIFFERENT VERSION
we did not build. Building OUR sources / OUR config for x86_64 and showing a cleanly-terminated
chain converts "ARM64-specific vs a foreign binary" into "ARM64-specific, full stop." Unowned,
collides with nothing. NOTE: this session cannot execute any binary (WSL cross-only, no x86_64
Cygwin runtime here) — so the *build* could be attempted locally but the *run/verify* belongs to
a session on a Windows host (c63ab774). Flagged to coordinator for assignment.

## RESULT G — timing contradiction RESOLVED by measurement (type=1 ⇒ HEAP_STR; window confirmed)
c63ab774 pinned the corruption to a SINGLE one-time 8-byte store to cygheap+8 between two
adjacent allocations: username entry 0x8000068C0 (b=0, prev=0x50B0 correct) → next entry
0x8000068F0 (prev WILD 0x80002CA000) → 0x800006A00 (prev=0x68F0 correct). ce->type=1 at the
wild entry. This CONTRADICTED my earlier "mmap arena doesn't exist during setup_cygheap"
argument (I had withdrawn my window on that basis; c63ab774 rightly noted bytes outrank the
narrative). Resolved:
- enum cygheap_types (cygheap_malloc.h:14, 0-indexed): HEAP_FHANDLER=0, HEAP_STR=1, HEAP_ARGV=2,
  HEAP_BUF=3, HEAP_MOUNT=4, HEAP_SIGS=5, HEAP_ARCHETYPES=6, HEAP_TLS=7, HEAP_COMMUNE=8,
  HEAP_USER=9... => **ce->type=1 is HEAP_STR**, the class used by cstrdup (cygheap.cc:567
  `cmalloc(HEAP_STR,...)`) and crealloc's kludge. NOT HEAP_USER(9).
- set_name (cygheap.cc:628) does `pname = cstrdup(name)` = HEAP_STR. cygheap_user::init
  (uinfo.cc:39) reads USERNAME/USER env and calls set_name(mb_user_name) (uinfo.cc:53-58) —
  the `crutkasLocal` string, matching c63ab774's 0x68C0 bytes.
- **cygheap_user::init() is invoked at cygheap.cc:321, INSIDE setup_cygheap** (320 cygheap_init,
  321 user.init, 322 init_installation_root, 323 pg.init). So the username-era HEAP_STR
  allocations ARE in the setup_cygheap window — my original placement was right; the withdrawal
  was the error. The wild entry 0x68F0 is the HEAP_STR allocation immediately after the username.
- MECHANISM (DERIVED from the byte geometry + cygheap.cc:397-398): the store is `rvc->prev =
  cygheap->chain; cygheap->chain = rvc`. 0x68F0's prev = whatever cygheap->chain held at that
  instant = the WILD value. The very next allocation (0x6A00) overwrote chain with 0x68F0
  (valid), RESTORING the head. => it is a TRANSIENT head corruption, wild for exactly one
  allocation-gap, and the orphan 0x68F0 permanently records the wild value in its prev. This is
  fully consistent with "head starts correct, becomes wild, chain walk trips" — the wild state
  is momentary but leaves a poisoned prev on one entry that the fork/exec walk later follows.
- SHARPENED OPEN QUESTION (mine): does an mmap-arena address (specifically a ~512 GiB chunk,
  c63ab774's 0xD1000-into-0x8000200000) EXIST to be stored during the setup_cygheap window? That
  reduces to: has the USER allocator (ptmalloc → win32mmap → VirtualAlloc(0,...), the only
  producer of unbounded high mmap addresses) run even once by cygheap.cc:321? cmalloc/_csbrk
  never leave the cygheap arena, so the wild value cannot originate from cygheap's own allocator
  — it must be a value already sitting in a register/memory from a prior ptmalloc/VirtualAlloc,
  stored into chain by a foreign instruction whose base mis-resolves to cygheap+8 for one store.

## RESULT H — window refined: foreign store is in memory_init early path, NOT setup_cygheap tail
c63ab774 CORRECTION accepted: MMAP_STORAGE_LOW/HIGH are Cygwin's PLACEMENT bookkeeping, not a
reserved range — so 0x8DCA825000 need NOT come from Cygwin's mmap subsystem; any VirtualAlloc(0,)
/HeapAlloc by loader/ntdll/CRT/Windows-heap can land there anytime. My ptmalloc hypothesis
(incl. the re-argued version) is RETIRED. Also accepted: bucket_val is an explicit TABLE
(cygheap.cc:281: 32,48,64,96,128,192,256,384,512,768,1024,1536,2048,3072,4096,6144,...), NOT
1<<b; with it the intact sub-chain abuts exactly (0x48A0+16+2048=0x50B0; +16+6144=0x68C0;
+16+32=0x68F0). So the hunt is now "what in the window receives an OS-allocated pointer and
stores it," and it is a short read in my lane.
MEASURED window trace (execution order, dcrt0.cc):
- dll_crt0_0: 753 setup_cygheap() -> 754 memory_init().
- setup_cygheap (cygheap.cc:318): 320 cygheap_init; 321 user.init; 322 init_installation_root;
  323 pg.init.
- **user.init (uinfo.cc:39-111): the username cstrdup (set_name@58, HEAP_STR) is the ONLY cygheap
  allocation in it** — awk NR 59..111 shows ZERO cmalloc/cstrdup/ccalloc after set_name. The rest
  is Nt token queries (67/73 fixed cygsid bufs, no alloc), NtSetInformationToken (82),
  sec_user_nih (90). __sec_user (sec/helper.cc:604) writes ONLY into the caller's alloca(1024)
  sa_buf (psa->lpSecurityDescriptor = psd, psd inside sa_buf) — no OS-alloc, no cygheap store.
- **init_installation_root (cygheap.cc:161-273): ZERO cmalloc/cstrdup** (awk confirms). Writes
  only in-cygheap buffers (installation_root_buf@+288 etc.) + RtlInitUnicodeString (sets ptr/len
  to existing buffer). The registry reg_key block (263-272) is #ifndef __MSYS__ → COMPILED OUT
  for MSYS2. No OS-pointer store to +8.
- **pg.init (uinfo.cc:585-604): ZERO cmalloc** — writes scalar NSS-source fields into pg@+16960.
=> The pure setup_cygheap tail allocates ONLY the username and stores NO OS pointer near +8. So
the foreign store is NOT there. It is in the GAP that continues into **memory_init**
(dcrt0.cc:754 -> shared.cc:323): user_info::initialize (shared.cc:191) runs mountinfo.init(false)
@201, then **internal_getpwsid(sid) @203** (parses /etc/passwd; pwdgrp load), then the SECOND
set_name(pw->pw_name) @207. internal_getpwsid + the pwdgrp loader are exactly where OS
buffer-returning APIs live: LookupAccountSidW, NetUserGetInfo/NetLocalGroupGetInfo (classic
NetApiBufferAllocate OS-heap returns), plus sys_wcstombs_alloc (uinfo.cc:542, stores HEAP_STR
result THROUGH &psystemroot) and pwdgrp_buf = crealloc_abort (uinfo.cc:573).
=> **REFINED TARGET for c63ab774's dynamic anchor: the single foreign 8-byte store to cygheap+8
occurs in the memory_init early path (mountinfo.init / internal_getpwsid / pwdgrp load), between
the setup_cygheap username cstrdup and the first memory_init cmalloc — NOT in the setup_cygheap
tail.** An OS-allocated buffer pointer (Net*/LookupAccountSid/HeapAlloc-class) is the value; the
foreign store's base mis-resolves to cygheap+8 for one store. The instruction between the two
adjacent _cmalloc calls (0x68C0 and 0x68F0) on rung9's breakpoint log is the writer.

## RESULT I — StackBase adjacency: _cygtls-overflow mechanism MEASURED NEGATIVE
c63ab774 differential accepted: StackBase==0x800000000==CYGHEAP_STORAGE_LOW is a SHARED design
property (x86-64 3.6.9 has the identical boundary to the byte and terminates clean). So "stack
placed differently on ARM64" is ELIMINATED; the adjacency makes a mis-based store mechanically
possible on BOTH arches. Since only ARM64 corrupts, the difference is in WHAT WRITES near
StackBase — an offset/size/alignment that differs on ARM64, or an ARM64-only path. My adjacency
prior is refined (ranking, not cause); the sp/x18-base triage question stands.
I searched for code that writes at/just past the stack top. Two StackBase-adjacent structures:
- **_my_tls = *(_cygtls*)(StackBase - __CYGTLS_PADSIZE__)** (cygtls.h:316). __CYGTLS_PADSIZE__ =
  12800 (config.h:31, NO arch conditional — shared). So _cygtls occupies
  [StackBase-12800, StackBase-12800+sizeof). If sizeof(_cygtls) > 12800 on ARM64 it would
  overflow past StackBase into cygheap+0/+8. **MEASURED (DWARF, cygtls.o): the _cygtls
  structure_type DIE byte_size = 5016.** Headroom = 12800-5016 = 7784 bytes. _cygtls does NOT
  reach StackBase; any normal write to a _cygtls field stays >=7784 bytes below cygheap.
  STRUCT-OVERFLOW MECHANISM = NEGATIVE on ARM64 (confirms checkpoint 004 from the new angle).
  Also: a _cygtls overflow would write cygtls CONTENT, not an OS-pointer value — inconsistent
  with the observed wild value being an OS-allocated pointer.
- init.cc:38 munge_threadfunc: `char** top = StackBase; for(peb<top) if(*peb==...)` — READ-ONLY
  stack scan, no store near StackBase. Not a writer.
=> The obvious "writes past StackBase" structural-overflow candidate is eliminated. A remaining
possibility is a store through a stack/sp-derived base with an ARM64-specific offset that reaches
StackBase+8 — not statically enumerable without the faulting PC. c63ab774's two open
possibilities (head wild AT BIRTH vs slot overwritten AFTER birth) remain undistinguished and are
dynamic questions.

## RESULT J — DLL-load window + dll_list stores are NOT the +8 writer; read-at-known-points design
c63ab774's watchpoint misses the gap because the gap coincides with FIVE LOAD_DLL events + one
thread creation (dll_list::alloc cmallocs; the births of 0x68C0/0x68F0/0x6A00 happen there). Two
platform facts it characterised: (1) HW watchpoint hits arrive as 0x80000003 EXCEPTION_BREAKPOINT
(indistinguishable by code from an ordinary breakpoint — only per-thread state separates); (2)
the instrument has an uncharacterised limitation around DLL-load/thread-create; re-arm did NOT
fail, yet writes produced no exception. So the (a)4-writes vs (b)3-writes count that would settle
head-wild-at-birth vs overwritten-after-birth CANNOT be taken by write-capture inside the gap.
I checked the DLL-load reaction code as the +8 writer (it is where the births + early allocator
run): dll_list::alloc (dll_init.cc:346-388) cmallocs a HEAP_2_DLL `dll* d` and writes ONLY into
d (d->handle/deps/p/next/prev...). dll_list::append (392): end->next=d; d->next=NULL; d->prev=end
— the dll chain, head is `dll_list::start` (a member of the .bss global `dlls`), NOT cygheap.
populate_deps (402): d->deps cmalloc + tmp_pathbuf tp. tmp_pathbuf stores its buffers in
_my_tls.locals.pathbufs (cygtls.cc:164) — inside _cygtls (5016B, safely below StackBase). NONE of
these store through a cygheap-based pointer; all write into freshly-allocated dll blocks or into
_cygtls/.bss. => dll_list is NOT the +8 writer (MEASURED by inspection of every store in the path).
The wild VALUE is most plausibly an OS pointer from the LOADER's own HeapAlloc bookkeeping
(LDR_DATA_TABLE_ENTRY etc.) during those five loads — an OS-heap address in the 512GiB+ band —
carried in a register and stored by ONE foreign instruction whose base mis-resolves to
StackBase+8==cygheap+8. That instruction is still only nameable by a runtime PC.

### Constructive hand-off: READ-AT-KNOWN-POINTS design (constant-independent, avoids the gap)
Since write-capture fails across DLL-load, read cygheap+8 at deterministic breakpoints that
BRACKET each birth, turning the (a)/(b) question into a sequence of point reads:
- Set an ordinary breakpoint at cygheap.cc:397 (`rvc->prev = cygheap->chain`) AND cygheap.cc:398
  (`cygheap->chain = rvc`). At :397 read [cygheap+8] (the value about to be copied into the new
  entry's prev) and x-reg holding rvc; at :398 read [cygheap+8] again after the store.
- For the three births in the gap (rvc = 0x68C0, 0x68F0, 0x6A00), log the pre-:397 [cygheap+8]
  and the post-:398 [cygheap+8]. If the 0x68F0 birth reads a WILD [cygheap+8] at its own :397,
  the head was ALREADY wild at that birth (case a) — the foreign store happened BEFORE 0x68F0's
  birth, i.e. during 0x68C0's post-birth interval. If 0x68F0's :397 reads 0x68C0 (correct) but
  the entry later shows wild prev, the slot was overwritten AFTER birth (case b).
- These are ORDINARY breakpoints on Cygwin's own code (not HW watchpoints), so they are immune
  to the DLL-load/thread-create limitation that defeats the watchpoint. rung9 gives exactly 39
  births with no app allocations to filter.
This needs no new capability c63ab774 lacks — it already sets code breakpoints and reads memory
by address. It is the missing instrument for the (a)/(b) discriminator.
Caution preserved: the wild value's per-run VARIATION does NOT discriminate (a) from (b) (a
post-birth overwrite varies too) — must use the point-read sequence, not value variance.

## Open target (needs c63ab774's dynamic anchor)
Internal cygwin startup code stores an MMAP-arena allocator-return pointer through a base that
mis-resolves to cygheap+8. Static enumeration is now exhausted (allocator clean; no init_cygheap
field near +8; no cygheap alias/overlay; emutls absent). The writer needs a runtime PC. Reliable
instruments (constant-independent, per coordinator): (1) _cmalloc-entry breakpoint logging
cygheap+8 per call against rung9 (39 entries, no app allocs) — yields the caller on both sides
of the 0-good→wild transition; (2) chunk-vs-segment test: wild value vs _gm_.seg.base/.size from
BSS (offsetof seg=888). Both are c63ab774's to execute; this session cannot run aarch64 binaries.

## RESULT K — THE WILD VALUE IS THE MAIN THREAD'S TEB; mechanism DERIVED (not observed) as single-thread direction inversion
- BREAKTHROUGH (c63ab774, MEASURED, diff ZERO): wild value at cygheap+8 == main thread TEB
  0x8000274000 (read from CREATE_PROCESS_DEBUG_INFO+56). Retires every prior description of that
  value ("512-898 GiB band", "loader bookkeeping", "ASLR", "dlmalloc segment", "chunk pointer" in
  the Context header above — ALL SUPERSEDED).
- MECHANISM (DERIVED, corrected): a PURE SINGLE-THREAD DIRECTION INVERSION. Correct idiom
  everywhere: `main_StackBase = *(main_TEB+8)` (load; NT_TIB.StackBase lives at TEB+8). Bug:
  `*(main_StackBase+8) = main_TEB` (store; operands/direction swapped). BOTH operands are the
  MAIN thread's own related quantities — NOT cross-thread. (I earlier framed it as "one thread
  storing another thread's TEB"; c63ab774 corrected it, re-derived from measured operands, RETRACTED
  — the sig-vs-main sampling variance is TIME-bracketing, not thread attribution.)
- VICTIM birth stack (c63ab774 via my frame-walk recipe): 0x68F0 born in pwdgrp::check_file
  (uinfo.cc:1687) <- internal_getpwsid (passwd.cc:107) <- user_info::initialize (shared.cc:206)
  <- dll_crt0_1 (dcrt0.cc:855). check_file != fetch_account_from_windows (NetApi sub-hypothesis
  DEAD; pwdgrp path LIVE — two separate facts).
- FOUR MEASURED STATIC NEGATIVES — the corrupting store is ABSENT from msys compiled code by every
  shape (target new-msys-2.0.dll; CAVEAT stated: proves "not in msys image", NOT "not executed by
  our process" — excludes ntdll/loader/CRT init):
  (1) TEB-as-VALUE: `str x18` any form (str/stp/stur)=0; `mov xN,x18`->`str xN` within 40 instr =
      159 sites, ALL redefine xN before store (zero carry raw TEB); at #8 with no redef=0.
  (2) TEB-FIELD-as-DESTINATION (the shape-sibling my first pass MISSED): stores to [mov-copy-of-x18,
      #8] = exactly 3 sites — pthread_wrapper (create_posix_thread.cc:54), create_new_main_thread_stack
      (cc:274), dll_crt0_1 (dcrt0.cc:879). ALL write TEB+8 with genuine mov-x18 base + computed-
      stackbase VALUE; none stores the TEB; dll_crt0_1 one is FORK-GATED (if __in_forkee==FORKING)
      so does NOT run in non-fork rung9.
  (3) cygthread::stub (msys+0x50DC): only TEB access is correct prologue (ldr [x18,#8] -> store
      _ctinfo INTO _cygtls); all other stores hit [x19,#N] object fields; no new-thread-TEB write,
      no 0x800000000-based store.
  (4) CONSTANT-BASE: image-wide 0x800000000 materialized 3x — once as VALUE into [x19,#512], twice
      as lpAddress arg to cygheap VirtualAlloc; NEVER a store base.
- RELOCATION EXPERIMENT (c63ab774 ran; caught own FALSE POSITIVE): moving CYGHEAP_STORAGE_LOW
  0x800->0x900 gave a "clean" 3-entry chain — but runtime ABORTED early (rung3/4/5/6 = 0x80000001);
  3 entries vs baseline 39 = died before corruption point. Rule recorded: prove the program still
  REACHES where the symptom would appear before crediting its disappearance.
- WHY IT BROKE (my static root cause): memory_layout.h is a FULLY-CONTIGUOUS ABUTTING partition —
  CYGHEAP_STORAGE_LOW == THREAD_STORAGE_HIGH == 0x800000000; CYGHEAP_STORAGE_HIGH == USERHEAP_START
  == 0xa00000000. One-constant edit opened a gap, halved the cygheap, stranded main StackBase on the
  old boundary. REFRAME: the aliasing main_StackBase == cygheap_base == 0x800000000 is BY DESIGN
  (cygheap deliberately placed atop the thread-stack arena), NOT coincidence. So the real fix is the
  inverted store itself; relocation only moves the collision target and is a coordinated re-partition,
  not a one-line change.
- SEALED CONCLUSION — SUPERSEDED 2026-09-03 by RESULT L (instruction NAMED). Lines 1, 2, 4 below
  are FALSIFIED; line 3 SURVIVES and is now load-bearing. See RESULT L for the correct root cause.
  The lines are retained (not deleted) as a record of a derivation that matched every measured datum
  and still named the wrong mechanism.
  1. [FALSIFIED] Mechanism: DERIVED, NOT OBSERVED. MEASURED: the stored value is the main thread's TEB exactly
     (diff zero), and the store target is cygheap+8 == StackBase+8. Since NT_TIB.StackBase lives at
     TEB+8, those two facts are explained by a single-thread direction inversion —
     `*(StackBase+8) = TEB` where the correct idiom is `StackBase = *(TEB+8)`. NO INSTRUCTION
     PERFORMING THIS HAS BEEN OBSERVED (no PC, no opcode, no register pair). cygheap->chain is
     collateral because the cygheap is placed at 0x800000000 == main StackBase (by design).
  2. [FALSIFIED — the store IS in msys compiled code, at _dll_crt0 RVA 0x6CD8; see RESULT L. The four
     negatives were all correctly scoped for "deliberate TEB store" but the store is an INCIDENTAL
     compiler spill, and vector-2's redef detector was additionally defective — see RESULT L.]
     Origin: NARROWED to "not msys's compiled code" — four independent measured static negatives
     (TEB-as-value / TEB-field-destination / cygthread-startup / constant-base), each with the
     "not in image != not executed by our process" scope caveat.
  3. [SURVIVES — load-bearing; this aliasing is WHY the 16-byte overrun in RESULT L lands on
     cygheap->chain.] Contributing factor: MEASURED — fixed cygheap base coincident-by-design with main StackBase.
     The aliasing is EXACT BY CONSTRUCTION (c63ab774 proof, corrected to the EXECUTED path and
     verified against primary source create_posix_thread.cc + wincap.cc). EXECUTED PATH is _alloc,
     NOT _alloc_old: wincap has_extended_mem_api flips true at wincap_10_1803 (wincap.cc:131/144) and
     stays true for all later versions incl. Win11 ARM64, so alloc_func = &_alloc (l232). _alloc
     (l142-179) does NOT use the current seed at all; it calls VirtualAlloc2(MEM_RESERVE|MEM_TOP_DOWN)
     with MEM_ADDRESS_REQUIREMENTS thread_req = {THREAD_STORAGE_LOW, THREAD_STORAGE_HIGH-1,
     THREAD_STACK_SLOT} (l144-147). On the FIRST (empty-arena) allocation, MEM_TOP_DOWN under the
     hard ceiling THREAD_STORAGE_HIGH-1 with 1MB alignment yields the topmost fitting block:
     allocationbase = THREAD_STORAGE_HIGH - real_size. Then create_new_main_thread_stack sets
     StackBase = allocationbase + stacksize (l274, SHARED by both paths). So
     StackBase = (THREAD_STORAGE_HIGH - real_size) + stacksize == THREAD_STORAGE_HIGH iff
     real_size == stacksize. real_size = roundup2(reserve, THREAD_STACK_SLOT=1MB) (l154);
     stacksize = roundup2(reserve, granularity=64KB) (l256). Measured rung10: reserve=0x200000 (2MB)
     -> both round to 0x200000 -> EQUAL -> StackBase == THREAD_STORAGE_HIGH == CYGHEAP_STORAGE_LOW
     == 0x800000000, corroborated by main StackBase measured 0x800000000 exactly.
     NOTE (superseded derivation): an earlier version of this proof cited _alloc_old's
     current(THREAD_STORAGE_HIGH) constructor seed; that is the branch this host does NOT take
     (WITHDRAWN). Both paths reach the SAME result at l274 — _alloc_old because current is seeded at
     THREAD_STORAGE_HIGH, _alloc because THREAD_STORAGE_HIGH-1 is the MEM_TOP_DOWN ceiling — but the
     mechanism actually executed here is the address-requirements ceiling, not the seed.
     CONDITION (stated): a reserve that is not a whole number of 1MB slots makes the two roundings
     disagree and shifts StackBase below the boundary; measured 2MB satisfies it.
     CONSEQUENCE: main StackBase and cygheap base are the SAME defined constant
     (CYGHEAP_STORAGE_LOW := THREAD_STORAGE_HIGH), so any correct coordinated re-partition moves both
     together and the aliasing SURVIVES; relocation cannot decouple them (one symbol) — only a gap
     could, which breaks contiguity. RELOCATING THE CYGHEAP IS NOT AN AVAILABLE MITIGATION — dead on
     two grounds: (i) MEASURED (c63ab774) a one-constant move breaks the runtime outright (clean
     3-entry chain BUT all rungs abort 0x80000001; died before corruption point); (ii) DERIVED the
     two addresses are the same constant. The fixed base is load-bearing as a shared partition
     boundary (memory_layout.h:34-47).
  4. [FALSIFIED — instruction NAMED, see RESULT L: str x4,[sp,#24] at _dll_crt0 RVA 0x6CD8.]
     Instruction: UNNAMED — no store-PC captured (host caps at 3 HW breakpoints, data watchpoint
     misses the window, loader single-step impractical). Surviving hypothesis: a Windows
     DLL_THREAD_ATTACH path. Arbiter: a store-PC capture, beyond instruments available here.

## RESULT L — INSTRUCTION NAMED: TEB spill in _dll_crt0 (dropped shadow-space subtraction)
- c63ab774 NAMED the store; I VERIFIED it against the shipped DLL (hand-decoded both words) and
  traced the cause to primary source. This SUPERSEDES sealed lines 1/2/4; line 3 survives load-bearing.
- THE STORE (new-msys-2.0.dll, in _dll_crt0 @ RVA 0x6C84), MEASURED disasm:
    0x6CC0  mov  sp, x0          ; sp = stackaddr = StackBase-16 (create_new_main_thread_stack l276
                                 ;   returns allocationbase+stacksize-16)
    0x6CC8  mov  x4, x18         ; x4 = NtCurrentTeb()
    0x6CCC  ldr  x0, [x4,#5240]  ; READS x4 (DeallocationStack) -- not a redef
    0x6CD8  str  x4, [sp,#24]    ; *** THE STORE ***  [sp+24] = (StackBase-16)+24 = StackBase+8
                                 ;   = 0x800000008 = cygheap+8 = cygheap->chain ; value x4 = TEB
    0x6CDC  bl   VirtualFree
    0x6CE0  ldr  x4, [sp,#24]    ; reload after the call -> classic compiler SPILL/RELOAD
  Hand-decode: f9000fe4 = STR(imm,64) Rt=4 Rn=31(sp) imm12=3 scaled*8=24 => str x4,[sp,#24]. Both
  operands match every prior measurement (value == main TEB; addr == cygheap+8).
- IT IS AN INCIDENTAL COMPILER SPILL, not a deliberate TEB store. x4 holds the TEB (needed for
  VirtualFree(NtCurrentTeb()->DeallocationStack,...) at dcrt0.cc:1067 AND the following
  NtCurrentTeb()->DeallocationStack=allocationbase at l1068), so it is live across the call and the
  compiler spills it. The spilled value's IDENTITY being the TEB is incidental — ANY local live
  across that call would corrupt the same slot. Our shared question "who stores the TEB" was
  unanswerable because nobody does it deliberately.
- CAUSE (primary source dcrt0.cc:1046-1064): the port drops x86_64's `subq $32,%rsp`. x86_64 arm:
  `movq stackaddr,%rsp; movq %rsp,%rbp; subq $32,%rsp` (l1050-1052). aarch64 arm:
  `mov sp,ADDR; mov x29,sp` (l1059-1060) — comment "Windows ARM64 has no shadow space, so unlike
  x86_64 nothing has to be subtracted here." The premise (no shadow space) is TRUE, but the `subq
  $32` had a SECOND, undocumented purpose: HEADROOM. x86_64 addresses locals at NEGATIVE offsets
  from rbp; AArch64 spills at POSITIVE offsets from sp. With sp = StackBase-16 there are only 16
  bytes before the cygheap, and the spill at +24 reaches 8 bytes into cygheap->chain.
- WHY MY FOUR SCANS MISSED IT (owed honestly):
  * str-x18-as-value: store is `str x4` (a COPY) -> correctly missed by design.
  * base = copy-of-x18: base is `sp` -> correctly missed by design.
  * base = constant 0x800000000: base is `sp` -> correctly missed by design.
  * mov xN,x18 -> str xN before redef (vector 2): THIS pattern EXACTLY (mov x4,x18 @6CC8, str x4
    @6CD8, 4 instr later, x4 not redefined). My original scan reported "159 sites, ALL redefine,
    ZERO carriers" — a FALSE NEGATIVE from a broken redef detector that counted a READ of x4
    (`ldr x0,[x4,#5240]`) or an unrelated-register write as a redefinition. CORRECTED detector
    (files/vec2fix.sh, since deleted) finds 18 genuine TEB-spill carriers incl. 0x6CD8. Same class
    of failure c63ab774 hit repeatedly: the defect was in the CHECK, not the mechanism.
  * DEEPER POINT: three of four vectors were correctly scoped and STILL blind by design — they all
    hunted for a DELIBERATE TEB store, which does not exist. No quality of implementation finds a
    shape that isn't there. The hedge on line 1 ("DERIVED, NOT OBSERVED") protected the reader but
    did NOT protect the conclusion: a derivation can match every measured datum and still be wrong.
- STATUS: store proven present and correctly landing (MEASURED). FIX NOT DEMONSTRATED — c63ab774 has
  NOT yet rebuilt with a corrected subtraction or re-run the rungs. Naming a defect is not fixing it.
  Candidate fix shape (DERIVED, unverified): reserve headroom on the aarch64 arm (e.g. `sub sp,sp,#N`
  after `mov sp,ADDR`, N covering the spill region) OR return a lower stackaddr from
  create_new_main_thread_stack — but any fix must keep 16-byte SP alignment and not itself under/over-
  run. The real fix is the missing subtraction; line-3 aliasing is why its absence is destructive.
- FIX APPLIED + INDEPENDENTLY VERIFIED (RESULT M below). Status above is SUPERSEDED: fix now demonstrated.
- Todos: instruction-named-teb-spill-dll-crt0, vec2-redef-detector-defect.

## RESULT M — FIX VERIFIED INDEPENDENTLY + FALSIFIER (no second instance)
- c63ab774 applied `sub sp,sp,#0x40` after `mov sp,%[ADDR]` in the aarch64 arm (size measured: max
  positive sp-relative access in _dll_crt0 is [sp,#24]+8B store = reach 32 vs 16 available; 64>32,
  16B-aligned). fork() works their side: rung12 8 genuine failures -> 0 (nested fork + child-side
  malloc/memset/verify/free), negative control run first, regression 3/4/5a/7 clean. Uncommitted,
  sealed evidence/forkfix-dcrt0.patch.
- I VERIFIED against fixed new-msys-2.0.dll (sha256 54e464d0...): _dll_crt0 @0x6C84 now:
    0x6CC0 mov sp,x0 ; 0x6CC4 sub sp,sp,#0x40 ; 0x6CC8 mov x29,sp ; 0x6CCC mov x4,x18 ;
    0x6CDC str x4,[sp,#24] (opcode UNCHANGED). Target moved 0x800000008 (cygheap->chain) ->
    0x7ffffffc8 (StackBase-56, inside stack). Negative control reproduced: spill present+carries TEB,
    now lands in frame. FIX CONFIRMED.
- FALSIFIER (c63ab774): is there a SECOND instance — any TEB-spill carrier in a function with a
  hand-written sp write besides the known ones? My corrected vector-2 detector: 15 carriers,
  each resolved to enclosing real fn and classified by hand-written-sp. EXACTLY ONE HANDWRITTEN-sp:
  _dll_crt0 (the culprit). Other 14 (cygthread::name, child_info_fork::alloc_stack, dladdr, faccessat,
  _open x2, setmntent, cygwin_conv_path, cygwin_setmode, mount_info::conv_to_posix_path, _pinfo::cwd,
  fhandler_socket::fchown, sigpacket::setup_handler, beep) all normal-prologue = harmless. Source grep
  (c63ab774: 3 hand-written sp writes — dcrt0 [fixed], exceptions.cc altstack [correct, reserves 32],
  pthread_wrapper [latent-only, sp 12800B below stackbase into _cygtls, unreachable fatal]) and binary
  scan CONVERGE: NO SECOND INSTANCE of the cygheap-corruption shape.
- HONEST DISCREPANCIES (reported, not hidden): (1) MY carrier scan returned 18 on an earlier run and
  15 on this one — this is ONE instrument (mine) in two configurations, NOT a cross-check with
  c63ab774, who never counted carriers (the "18" was mine; c63ab774 only echoed "your other 17"). It
  must NOT be read as independent convergence-with-noise. Cause of the 18->15: this run counted only
  `str xN,[sp,#k]` on a 60-instr window and omitted `stp` pair-spills. Difference is store-form set,
  not disagreement on the culprit. (2) my detector finds 130 fns with `mov sp,xN`, but almost all are
  `mov sp,x29` frame-ptr epilogues + VLA/alloca codegen (compiler-aware) — the binary cannot cleanly
  separate inline-asm sp-write from VLA sp-write by opcode, so the SOURCE grep is the stronger
  instrument for "how many hand-written sp writes" and the BINARY scan for "does any carrier land
  dangerously"; intersection = {_dll_crt0}. Lesson (mine): before calling a count a contradiction,
  confirm both instruments were asked the same question.
- THE REAL CONVERGENCE (does NOT rely on the carrier count): my BINARY scan resolved every carrier to
  its enclosing fn and found exactly ONE in an inline-asm-sp function (_dll_crt0). c63ab774's SOURCE
  grep found exactly THREE hand-written sp writes, only _dll_crt0 followed by positive-sp-offset
  compiler code. Two genuinely different instruments, two different questions, intersecting at
  {_dll_crt0}. That corroboration stands without the carrier count.
- REMAINING (c63ab774's): uncommitted local edit; no exec/threads/job-control exercised; no real
  MSYS2 program has run. Todo: forkfix-independent-disasm-verified.

## RESULT N — SECOND defect: UPSTREAM Cygwin strcpy-on-overlap (NOT a port bug)
- Category-distinct from everything above: this is a latent bug in UPSTREAM Cygwin's own source that
  x86 codegen has masked indefinitely, exposed by AArch64. First non-port defect in the programme;
  the one with reach beyond ARM64 if findings ever go upstream. Found+fixed by c63ab774; I VERIFIED
  all three axes independently.
- SOURCE (dcrt0.cc quoted(), l165+l167): `strcpy(cmd,cmd+1)` and `strcpy(p,p+1)` — dst=src-1,
  OVERLAPPING => C undefined behaviour (C std 7.24.2.3). Tree-wide sweep for `strcpy(X,X+N)` overlap:
  EXACTLY these 2 sites (verified independently, my grep).
- MECHANISM (binary): linked aarch64 `strcpy` is NEON/SIMD — `ld1 {v0.16b},[x2]`; `ldr q0,[x2,#16]!`;
  `cmeq`/`shrn` NUL-scan (disasm confirmed). It reads 16-byte blocks and re-reads source bytes its own
  stores already overwrote when regions overlap. x86_64 byte-forward strcpy happens to yield the
  intended left-shift, hence latent there.
- MEASURED corruption (c63ab774): sent `abcdefghijklmnopqrstuvwx` -> got `abcdefghijmnopqrstuuvvwx`
  (kl dropped, u/v doubled). TWO TEST-DESIGN TRAPS worth carrying: (1) LENGTH UNCHANGED (24) so
  strlen-based assertions PASS on corrupted data; (2) POSITIONAL — only argv[3] corrupted, tracks
  total cmdline length, so a passing argv test proves nothing about strings it didn't land on (P3
  fixture 5/7->7/7 with this bug still present).
- FIX (c63ab774): `memmove` at both sites (defined for overlap); 2 `bl <memmove>` in rebuilt obj;
  round-tripped quoted-arg lengths 1..40 byte-for-byte, 0 mismatches; regression rung3/4/5a/6/7 +
  rung12 fork stress clean. New DLL sha256 90bfb483...; sealed evidence/dcrt0-both-fixes.patch.
- LIMIT: uncommitted local edit; this session ran no binaries. Todo: upstream-strcpy-overlap-quoted.
- COMPLETE BOUNDED SWEEP (mine, addressing c63ab774's scoping incl. the variable-offset shape their
  `+1` grep would miss): (a) str*/stpcpy/strcat/strncpy self-overlap `f(X, X + <ANY expr>)` incl
  variable offset `strcpy(p,p+n)`/`strcpy(buf,buf+off)` -> ONLY the 2 quoted() sites; (b) right-shift
  `f(X+n, X)` -> NONE; (c) memcpy self-overlap -> NONE; (e) member/arrow forms: the 5 `strcpy(de->
  d_name, ...)` sites (registry.cc:607/622, dev.cc:209/247, dev_disk.cc:836) are all DISTINCT-buffer
  (dirent output vs name tables/accessors), NOT self-overlap. CONCLUSION: exactly 2 genuine SYNTACTIC
  self-overlap sites tree-wide, both quoted(), both fixed; the variable-offset gap does NOT exist.
  SCOPE BOUND (explicit): syntactic self-reference only; overlap via DISTINCT runtime-aliasing pointers
  is OUT OF SCOPE (needs real aliasing analysis). A bounded negative, not an unbounded one.
- ORDERING LAPSE (c63ab774's, self-flagged): my NEON-strcpy disasm is the FIRST measurement of the
  mechanism; c63ab774 had recorded it as measured in commit 6397acaa5 before disassembling. My disasm
  establishes it NOW but does not retroactively make the commit-time claim measured. Fix survives
  because it rests on the UB, not the mechanism; memmove is behaviour-preserving (== intended strcpy
  semantics) so provably no regression on already-working platforms — the lead sentence for any upstream
  filing. STATE: argv fix COMMITTED 6397acaa5; fork fix HELD (one-line sub would drag in the ~15-line
  __aarch64__ arm absent from c63ab774's branch — escalated, outside authority).
- BOUND CONFIRMED UNAMBIGUOUS: my `f(X, X + <expr>)` sweep covers LITERAL AND VARIABLE offsets —
  proved with a synthetic test (`strcpy(p,p+n)` and `strcpy(buf,buf+off)` both MATCH; distinct-buffer
  `strcpy(x,y+1)` correctly does NOT). So the variable-offset shape c63ab774 flagged is genuinely
  covered, not just literals.

## RESULT O — THIRD defect (exec): child_copy cygheap read fails (err6) — surface mapped, root cause NOT named
- Category: c63ab774's lane by discovery, mine (static) to characterise. c63ab774 MEASURED (rung14
  fork+execv, post-fork-fix DLL 90bfb483): exec is now REACHABLE (was blocked before the fork fix — a
  newly-exposed defect, NOT a regression); execv loads the new image (diagnostics come from rung3, so
  the exec'd image started msys startup); dies in child_copy cross-process read of cygheap
  0x800000000..0x800025B30 with done=0, Win32 err 6 (ERROR_INVALID_HANDLE), then err 5 (ACCESS_DENIED)
  on the signal pipe.
- STATIC SURFACE (measured, READ-ONLY): failing site = mm/cygheap.cc:102 `child_copy(child_proc_info->
  parent, false, ...)` in cygheap_fixup_in_child(execed=true), copying cygheap..cygheap_max (range
  matches). Handle flow: (1) child_info ctor sigproc.cc:929-940 makes an INHERITABLE handle to the
  spawner via DuplicateHandle(...,&parent,perms,TRUE,0), perms incl PROCESS_VM_READ; fork additionally
  gets PROCESS_DUP_HANDLE. Shared by fork+spawn. (2) EXEC: child_info_spawn::handle_spawn (dcrt0.cc:640)
  runs cygheap_fixup_in_child(true) iff (!dynamically_loaded || get_parent_handle()) [l644];
  get_parent_handle (dcrt0.cc:635 OpenProcess(PROCESS_VM_READ,FALSE,parent_winpid)) is SHORT-CIRCUITED
  when !dynamically_loaded, so normal exec uses the INHERITED handle, not a re-open. parent_winpid set
  spawn.cc:602 = GetCurrentProcessId(). (3) spawn CreateProcessW (spawn.cc:660) + CreateProcessAsUserW
  (l712) BOTH pass bInheritHandles=TRUE.
- CANDIDATE CHECKED + REJECTED: spawn.cc:594-598 clears HANDLE_FLAG_INHERIT on `parent` — WOULD cause
  exactly err6 — but guarded by `if(!iscygwin())`, so fires ONLY for NON-Cygwin targets. rung14->rung3
  is Cygwin->Cygwin (iscygwin() true), so it does NOT fire for the measured case. (It IS the exact
  breakage mechanism for exec of a non-Cygwin program — noted separately.) Caught this before
  asserting it as the cause.
- ROOT CAUSE NOT NAMED — reached the static boundary: for Cygwin exec the parent handle stays
  inheritable AND CreateProcess inherits, yet the read gives INVALID_HANDLE. The remaining
  discriminators (is the handle actually in the inherited set at CreateProcess time; is `parent`
  valid/non-stale when child_info is written to shared memory; handle-creation-vs-snapshot timing) need
  DYNAMIC handle-table inspection = c63ab774's lane. I did not name a mechanism I could not prove.
- DISAGREEMENT (unresolved, flagged): another party told c63ab774 the child_copy/err6 symptom is GONE
  post-fix and execl() returns; c63ab774's measurement disagrees on both halves. Both cannot describe
  the same test. Treat "symptom gone" as UNVERIFIED until re-run against the identical shape
  (rung14 rung3). LIMIT: read-only; cannot run rung14. Todo: exec-child-copy-handle-surface.
- DISAGREEMENT RESOLVED (c63ab774, ratified): "err6 gone" was an ARTEFACT of the argv strcpy-overlap
  corrupting the exec TARGET FILENAME (rung3.exe -> runng3.exe) => ENOENT (errno 2) BEFORE child_copy
  ran. Call form is NOT the variable (execv==execl); the DLL is. On the fixed DLL err6 is LIVE — same
  child_copy, same done=0, same 0x800000000..0x800025B30. So RESULT O is LIVE not superseded. BIGGER
  argv finding: the strcpy overlap corrupts not just program args but the PATH handed to exec, so on any
  pre-fix runtime exec of a name whose length hits the corruption window fails with ENOENT for a reason
  that looks nothing like the cause — would have poisoned every exec investigation on that runtime.
  The other party's "err6 gone" OBSERVATION was accurate (execl did return, err6 was absent on THAT
  DLL); only the INFERENCE that exec improved was wrong. Third instance of the programme's most reusable
  rule: when a change makes a symptom vanish, first prove the program still reaches the point where the
  symptom would appear.
- STATIC HANDLE-TRANSMISSION TRACE COMPLETE (mine) — result: STATICALLY CLEAN, root cause is DYNAMIC.
  Traced fork-vs-exec parent-handle flow to answer "which handle differs": (1) parent handle made
  INHERITABLE in child_info ctor (sigproc.cc:938 DuplicateHandle(...,&parent,perms,TRUE,0)). (2)
  child_info_spawn::set (child_info.h:155) is PLACEMENT-NEW `new(this) child_info_spawn(ci,b)` at
  spawn.cc:551 -> parent RE-DUPLICATED FRESH PER-EXEC, not carried stale (answers the open question).
  (3) struct transmitted via si.lpReserved2=this (spawn.cc:556), child reads res=(child_info*)
  si.lpReserved2 (dcrt0.cc:531), uses res->parent in child_copy. (4) CreateProcessW/AsUserW both
  bInheritHandles=TRUE (spawn.cc:660,712). (5) inherit flag cleared only if(!iscygwin()) (spawn.cc:597)
  — does NOT fire for Cygwin target. postfork (child_info.h:85) manages only proc pipes, not parent.
  CONCLUSION: the source creates a fresh inheritable handle to the spawner per-exec, embeds it in the
  transmitted struct, and requests inheritance — internally consistent, NO statically-nameable
  missing-flag/stale-handle defect. err6 root cause is DYNAMIC (is the handle actually in the inherited
  set at the CreateProcess snapshot; is `parent` the right live process; handle-table/timing) =
  c63ab774's lane. Structural fork-vs-exec difference NOTED: fork does NOT use lpReserved2/CreateProcess
  (fork handshake) — but that alone doesn't name why the inherited handle reads invalid. Bounded static
  negative delivered; no mechanism derived beyond evidence. Todo: exec-parent-handle-transmission-clean.
- STALE-ITEM RECONCILE (messages crossed): fork fix is COMMITTED d9369d0bf (1 file, 13 ins; coordinator
  ruled autonomously; verified 0 aarch64 tokens leaked into cygwin.sc.in/mkimport/malloc_wrapper.cc/
  config.h); 4 commits on branch. Both dcrt0 fixes now committed (6397acaa5 argv, d9369d0bf fork).
- EXEC FIXED by c63ab774 (measured): the get_parent_handle() short-circuit I named IS the fault site.
  Instrumented: dynamically_loaded=0 parent=0x19C usable=0 err=6 short_circuits=1; making the
  OpenProcess(PROCESS_VM_READ) recovery reachable (reopen=1 newparent=0x114) => execv=execl=77,
  err6=0, err5=0, regression clean. That recovery is UPSTREAM'S OWN code merely made reachable. My
  iscygwin()-guarded inherit-clear catch (spawn.cc:594-598) independently rejected by c63ab774 too.
  CORRECTION (coordinator 2b2e50a5 challenged the by-product; re-derived from primary source and they
  are RIGHT — my "would break exec of a non-Cygwin program" claim was WRONG and is RETRACTED): the
  inherit-clear on `parent` for a non-Cygwin child is DELIBERATE CORRECT HYGIENE, not a latent defect.
  Source proof: (a) the block's own comment spawn.cc:588-591 states "parent won't be used by the child
  so there is no reason for the child to have it open as it can confuse ps"; (b) consumer audit — every
  reader of child_proc_info/parent lives in dcrt0.cc + mm/cygheap.cc (get_cygwin_startup_info@526,
  cygheap_fixup_in_child@587/646, child_copy(child_proc_info->parent)@cygheap.cc:102), all reached ONLY
  via the Cygwin DLL's own _dll_crt0/dll_crt0_0 startup; a non-Cygwin child never loads the Cygwin DLL,
  so never calls get_cygwin_startup_info, never sets child_proc_info, never reads parent. So there is NO
  non-Cygwin consumer of the handle and clearing its inherit flag cannot break anything. The GAP is still
  real (exec has only ever been tested Cygwin->Cygwin) but the specific mechanism I named does not exist.
- FINAL STATIC THREAD (c63ab774's ask: parent re-duplicated per-exec or carried stale?) RE-DERIVED
  FROM PRIMARY SOURCE, result: RE-CREATED FRESH PER-EXEC — stale-carried hypothesis FALSIFIED.
  * parent = child_info ctor sigproc.cc:938 DuplicateHandle(GetCurrentProcess x3,&parent,perms,TRUE,0)
    — an INHERITABLE handle to the PARENT ITSELF (perms PROCESS_VM_READ etc; fork adds
    PROCESS_DUP_HANDLE). ctor RE-RUNS per-exec: child_info_spawn::set (child_info.h:155) is
    placement-new `new(this) child_info_spawn(ci,b)`, called spawn.cc:551 inside worker() (once per
    exec) => fresh, not stale.
  * handle TARGET (parent proc) STAYS ALIVE through worker() for _P_OVERLAY (child CREATE_SUSPENDED,
    resumed spawn.cc:868) => target-dying hypothesis also falsified.
  * DUAL TRANSMISSION named (reconciles usable=0): (A) numeric handle VALUE 0x19C ALWAYS crosses — the
    whole child_info_spawn is copied BY VALUE into child STARTUPINFO (si.lpReserved2=(LPBYTE)this,
    cbReserved2=sizeof(*this), spawn.cc:556-557; read child-side dcrt0.cc:531 res->parent). (B) that
    value is VALID in the child only if OS handle inheritance (bInheritHandles=TRUE spawn.cc:660,712 +
    inheritable-in-ctor) populates the child handle table with 0x19C. Measured: (A) OK, (B) FAILED err6.
  * STATIC BOUNDARY CONFIRMED: source correctly makes the handle inheritable, requests inheritance, and
    transmits the value — NO source-level missing-flag/stale-handle defect. WHY OS inheritance doesn't
    take on AArch64 while fork (fork handshake + explicit dup, NOT pure CreateProcess inheritance) works
    is a Windows-loader/dynamic question outside static source. c63ab774 fix = upstream recovery made
    reachable = correct symptom repair; deeper why honestly open.
  * Caveats acknowledged: extra OpenProcess per exec; pre-existing handle LEAK now per-exec
    (get_parent_handle overwrites parent w/o CloseHandle) — proper fix CloseHandle(parent) first.
    Todo: exec-parent-handle-per-exec-fresh-dual-mechanism.
- STALE-CARRIED REFUTED BY MEASUREMENT (c63ab774), converges with my source falsification: default ctor
  is empty `child_info_spawn(){}` (nothing minted at static-init), real ctor via placement-new in set();
  instrumented CTOR type=1 parent=0x190 minted_in_pid=14816 vs CHILD got parent=0x190 usable=0 err=6
  parent_winpid=14816 => value received==minted, minting pid==parent_winpid, fresh for THIS spawn, right
  process — still invalid in child. Not stale, not reused. Non-Cygwin exec by-product WITHDRAWN by
  c63ab774 too (execv of C:\Windows\System32\hostname.exe prints hostname, exit 0) — converges with my
  retraction above. Disasm target updated: OLD /root/xc/w-link/bld/.../new-msys-2.0.dll 9fcc134e STALE
  (fork+argv only) -> NOW 3c1cc03a (all 4 fixes: fork headroom, argv memmove, exec get_parent_handle,
  leak close; no instrumentation). Six intermediates in STALE-DO-NOT-USE/.
- SHARPER STATIC QUESTION (c63ab774's, the last that may yield statically): the failing exec-ing process
  is ITSELF A FORKED CHILD (pid 14816 forked from 8016). fork constructs child_info in an ordinary
  process; this exec constructs it in a FORKED one. Does a forked Cygwin process's handle table /
  CreateProcess path differ so a subsequently-DuplicateHandle(...,TRUE) inheritable handle is not
  actually inherited? READ BOTH CreateProcess sites: fork.cc:366-379 CreateProcessW(...,sa,sa,TRUE,...)
  bInheritHandles=TRUE under deimpersonate(fork.cc:336); spawn.cc CreateProcessW/AsUserW(...,TRUE,...)
  also bInheritHandles=TRUE under deimpersonate. BOTH pass the inherit flag IDENTICALLY — the asymmetry
  is NOT a call-site flag difference. The discriminator must be HOW the forked child's handle table is
  established at birth: a forked Cygwin child is not a normal CreateProcess child; its address space +
  handle state are reconstructed by fork machinery (fixup_before/after), so whether a
  DuplicateHandle(...,TRUE) issued AFTER fork reconstruction sets the kernel-level inheritable bit in
  that reconstructed table is NOT determinable from source alone (kernel handle-table object
  provenance). STATIC BOUNDARY REACHED; no mechanism manufactured. ENDORSED c63ab774's dynamic
  discriminator: exec directly from a NON-forked process — if it works, fork-then-exec is implicated and
  the question narrows enormously; if it also fails, exec inheritance is broken independent of fork.
  Todo: exec-fork-then-exec-asymmetry-static.
  ** SUPERSEDED/RETRACTED (coordinator 2b2e50a5, MEASURED): FORK-ANCESTRY IS DEAD — the verifier ran a
  DIRECT execl arm with NO fork in its ancestry and it FAILED IDENTICALLY. So fork-then-exec is NOT the
  discriminator and the asymmetry lead above is withdrawn; must inform c63ab774 (I handed them that
  lead). The signature stands (correct value, bInheritHandle=TRUE REQUESTED (not observed-set — see
  PREMISE note below), absent from child
  table) but it is NOT gated on fork ancestry. **
- STARTUPINFOEX / PROC_THREAD_ATTRIBUTE_HANDLE_LIST candidate (coordinator, UNVERIFIED): DEAD by grep +
  positive confirm. Only tree-wide users of STARTUPINFOEX/InitializeProcThreadAttributeList/
  UpdateProcThreadAttribute/PROC_THREAD_ATTRIBUTE_HANDLE_LIST/EXTENDED_STARTUPINFO_PRESENT/lpAttributeList
  are in fhandler/pty.cc (pty path). ZERO in spawn.cc/fork.cc. Positive: exec uses plain STARTUPINFOW
  si={} (spawn.cc:340), si.cb=sizeof(si) (624), no EXTENDED flag, uses lpReserved2 blob not an attr
  list; fork same (STARTUPINFOW si@321, si.cb=sizeof si@324). rung3 not launched via a Cygwin pty so
  pty.cc's list doesn't gate it. Coordinator outcome 1 ("no STARTUPINFOEX on either path"): candidate
  dead, stated plainly, not made to fit. Todo: exec-startupinfoex-handlelist-candidate-DEAD.
- PARENT-CLOSE-WINDOW hypothesis (coordinator's last unexamined static thread: does anything close/
  re-purpose parent between CreateProcess returning and the child's read?) FALSIFIED from source. Read
  handle_spawn (dcrt0.cc:639-698). It runs in the CHILD, straight-line: (1) line 644
  `if(!dynamically_loaded || get_parent_handle())` -> line 646 cygheap_fixup_in_child(true) = the
  child_copy(child_proc_info->parent,...) = THE FAILING READ; (2) line 687-694 CloseHandle(
  child_proc_info->parent)+null = strictly AFTER the read, same child/same function, after ready(true)
  @685. So the only close is CHILD-SIDE and STRICTLY AFTER the read (closing the child's own inherited
  copy, not the parent closing the source) — cannot precede/race the read. Negative, no mechanism
  invented. Re-confirms fault site from CHILD control flow: pre-fix, dynamically_loaded=false so the ||
  short-circuits and get_parent_handle() (OpenProcess recovery) is NEVER called -> child uses the
  INHERITED res->parent = the invalid (err6) handle; c63ab774 fix makes get_parent_handle reachable.
  Coordinator mechanism record now 0/3 (handle-value-preservation, session-phantom, handle-list); their
  eliminations/cross-checks have held. Remaining explanation is DYNAMIC (is the kernel inheritable bit
  actually set on parent at the CreateProcess instant) = c63ab774 lane, not nameable from source.
  Todo: exec-parent-close-window-falsified.
- (A)/(B) DECOUPLING CONFIRMED BY DECISIVE INSTRUMENT (c63ab774): GetHandleInformation (needs no access
  right; asks only "is the handle in this process's table") on the inherited parent in the child:
  `parent=0x194 in_table=0 err=6 flags=0x0 dup_ok=0 duperr=6` => ABSENT, not present-but-unreadable.
  Upgrades my "(B) failed / handle invalid" to the stronger "handle absent from child table," which
  EXONERATES the read args/range/access-mask entirely — child_copy never had a handle to read. (Their
  earlier GetExitCodeProcess probe needed PROCESS_QUERY_INFORMATION vs a PROCESS_VM_READ-only handle = a
  false negative from the instrument; GetHandleInformation is the correct instrument.) My CREATE_SUSPENDED/
  resume@spawn.cc:868 datum independently killed "target died before child read," which they hadn't
  separately excluded. Both stale items in my close-out already reconciled here: non-Cygwin claim
  RETRACTED (above), leak noted — c63ab774 confirms leak FIXED inside get_parent_handle() (close prev on
  success only, so upstream failure semantics untouched; 8/8 fork+exec verified) and non-Cygwin exec
  MEASURED WORKING (execv C:\Windows\System32\hostname.exe prints host, exit 0). Their three boundary-
  tighteners: fork-ancestry not the variable (rung19 execs direct from main, exec-fix reverted =>
  identical err6); reader IS the direct child (ProcessBasicInformation.InheritedFromUniqueProcessId ==
  parent_winpid in both paths — no intermediate generation); STARTUPINFOEX unused outside pty.cc.
  FIVE candidate mechanisms now measured dead; boundary stands. Surviving statement to file: a handle
  duplicated bInheritHandle=TRUE in P, passed by P to CreateProcessW with bInheritHandles=TRUE, arriving
  in P's DIRECT child with correct numeric value and ABSENT from that child's handle table. Neither lane
  proposes a sixth mechanism; correct place to stop and file. Todo: exec-gethandleinfo-absent-confirms-AB.
- PREMISE-TIGHTENING (coordinator 2b2e50a5, MEASURED vs REQUESTED discipline; binding for the upstream
  filing): everywhere I wrote parent is "re-minted fresh / inheritable" per-exec via
  DuplicateHandle(...,&parent,...,TRUE,0), the TRUE is the INHERITABILITY REQUEST passed to
  DuplicateHandle, NOT an OBSERVED state. It is DERIVED (source requests it), NOT MEASURED. Nobody has
  yet called GetHandleInformation(parent) IN THE SPAWNING PARENT at the CreateProcessW instant to
  confirm HANDLE_FLAG_INHERIT is actually set on the source-side handle. (c63ab774's in_table=0 probe was
  in the CHILD and proves absence there; it does NOT confirm the parent-side inherit bit at spawn time.)
  This is the ONE premise the whole "value present, handle absent" chain rests on and it is exactly the
  static boundary I named. Honest filing phrasing: "a handle for which bInheritHandle=TRUE was
  REQUESTED" — do not assert the handle WAS inheritable at spawn until the one-line parent-side
  GetHandleInformation lands (coordinator has asked c63ab774). An overstated premise gets a bug report
  dismissed (cf. the DYNAMIC_BASE correction earlier tonight). So amend lines 558/590/601 reading:
  "RE-DUPLICATED FRESH PER-EXEC" is accurate for the CTOR RE-RUN (placement-new re-runs the ctor, which
  ISSUES the request) — but the resulting inheritable STATE is requested-not-confirmed. Convergence noted
  (coordinator): the (A)/(B) decoupling was reached THREE independent ways — my source read, the
  verifier's cbReserved2 sweep, c63ab774's two-halves measurement.
- DLL TARGET moved AGAIN: new-msys-2.0.dll now 490ffdec0599892e (was 7be56027/9fcc134e). All 4 fixes, no
  instrumentation, FIRST byte-reproducible build (--no-insert-timestamp => relink gives identical bytes).
  Ten intermediates quarantined under README incl the DYNAMIC_BASE-cleared -fixedbase artefact. This
  turn's conclusions are SOURCE-DERIVED so unaffected by the target move; hash updated for any future
  disasm only.
- LAST-STATIC-REGION AUDIT (coordinator's ask): the mint->create window spawn.cc:551 (set() placement-new
  mints parent) .. 660/712 (CreateProcessW/AsUserW), ~110 lines, read as a UNIT for any touch of `parent`
  or the child_info_spawn object. RESULT: one guarded touch, nothing else; one real-but-INERT asymmetry.
  * 551 set(chtype,iscygexec) — the mint (placement-new re-runs ctor, issues DuplicateHandle request).
  * 597 SetHandleInformation(parent, HANDLE_FLAG_INHERIT, 0) — GUARDED if(!iscygwin()); does NOT fire for
    a Cygwin exec target (rung3). THE ONLY touch of `parent` in the window.
  * 602 parent_winpid = GetCurrentProcessId() — reads pid, not the handle.
  * NO CloseHandle(parent), NO second DuplicateHandle into parent, NO second set()/placement-new, NO
    reconstruction of the child_info_spawn object. refresh_cygheap()@648 refreshes cygheap ALLOCATOR
    state, not the object's parent field. si.cb=sizeof(si)@624 (plain STARTUPINFO, re-confirmed).
  * IMPERSONATION ASYMMETRY (coordinator's "interesting one") — REAL IN ORDERING, INERT FOR INHERITANCE:
    deimpersonate()@635 runs AFTER the mint (551) and BEFORE both CreateProcess calls (656/707), so
    mint-context and create-context differ by a token revert. BUT deimpersonate() is DEFINED
    (local_includes/cygheap.h:162-165) as exactly `RevertToSelf()` — reverts the THREAD impersonation
    token only; touches NO handle-table entry, NO SetHandleInformation/CloseHandle/DuplicateHandle, NOT
    parent. Windows handle inheritance depends on the handle's inheritable attribute + bInheritHandles,
    NOT on the acting thread token, so the token asymmetry CANNOT strip parent's inheritability. Bounded
    negative, not a mechanism. (CreateProcessAsUserW@707 under primary_token() is the setuid branch only;
    normal rung3 case is CreateProcessW@656.)
  CONCLUSION: the last unread static region is now read; nothing in the window clears/re-purposes/orphans
  parent for a Cygwin target. Corollary for the pending parent-side GetHandleInformation: if the inherit
  bit comes back CLEAR, nothing in THIS window cleared it (597 clear doesn't fire; RevertToSelf doesn't),
  which points at the DuplicateHandle mint itself or the OS — not at post-mint Cygwin code.
  Todo: exec-mint-to-create-window-audit.
  ** CORRECTION (MEASURED by c63ab774, and a SHARED MISS I own): the 597 inherit-clear DOES FIRE for
  rung3. Instrumented at the site: before-clear flags=0x1 iscygwin=0 will_clear=1; after-clear
  flags=0x0; parent-side GetHandleInformation at CreateProcess = flags=0x0. My clause "for a Cygwin exec
  target" was the false premise: rung3 is NOT CLASSIFIED as a cygexec, so iscygwin()=0 and the guard
  fires. My corollary above (bit clear => window didn't clear it => blame the mint/OS) WOULD HAVE
  MISDIRECTED — the window DID clear it, at 597. The error (mine, and the verifier's, and c63ab774's):
  rejecting a candidate because a guard EXISTS without measuring what the guard EVALUATES TO is an
  inference standing in for a measurement. Reading a guard is not running it. What SURVIVES from my
  audit and is now MORE valuable: (i) 597 is the ONLY touch of parent in the window => 597 is the whole
  story; (ii) the impersonation asymmetry is a clean bounded negative (RevertToSelf touches no handle);
  (iii) CreateProcessAsUserW@707 is setuid-only, rung3 uses @656. **
- **EXEC ROOT CAUSE NAMED — GENUINE ARM64 DEFECT, MEASURED FROM PRIMARY SOURCE (answers the
  where-does-MOUNT_CYGWIN_EXEC-come-from question: option 2 PE AUTO-DETECTION, NOT option 1 mount-table
  artefact).** MOUNT_CYGWIN_EXEC has two sources: mount option "cygexec" (mount.cc:1118, fstab/registry)
  AND PE auto-detection. For our binaries the detection path decides it: spawn.cc:1216-1232 maps the
  target's first 64K, checks 'MZ'@1219, calls set_cygexec(hook_or_detect_cygwin(buf,NULL,subsys,hm))
  @1225. hook_or_detect_cygwin (hookapi.cc:333) calls PEHeaderFromHModule@336; @340 `if(!pExeNTHdr)
  return NULL` (comment 338-339: "architecture doesn't match"). PEHeaderFromHModule (hookapi.cc:32-53)
  has an ALLOWLIST switch on FileHeader.Machine @44-50: `case IMAGE_FILE_MACHINE_AMD64: break; default:
  return NULL;` — comment @43 "Return valid PIMAGE_NT_HEADERS only for supported architectures." THERE
  IS NO IMAGE_FILE_MACHINE_ARM64 CASE. An aarch64 PE (Machine=0xAA64) hits default, returns NULL.
  CHAIN: aarch64 PE -> PEHeaderFromHModule NULL (hookapi.cc:48) -> hook_or_detect_cygwin NULL
  (hookapi.cc:340) -> set_cygexec(NULL) clears MOUNT_CYGWIN_EXEC (spawn.cc:1225, path.h:260-266) ->
  iscygexec()=0 -> need_subproc_ready false -> _CI_ISCYGWIN unset (sigproc.cc:923-927) -> iscygwin()=0
  -> !iscygwin() guard fires (spawn.cc:594) -> SetHandleInformation(parent,HANDLE_FLAG_INHERIT,0)@597 ->
  parent not inherited -> absent from child table -> child_copy err6. This is a SECOND independent ARM64
  runtime defect (the hook_or_detect_cygwin machine allowlist), UPSTREAM of spawn.cc:597, and it is the
  TRUE cause the get_parent_handle() recovery routes around without fixing. FIX SHAPE (derived, not
  applied — read-only lane): add `case IMAGE_FILE_MACHINE_ARM64: break;` to the PEHeaderFromHModule
  switch (and audit any other IMAGE_FILE_MACHINE_AMD64-only allowlists tree-wide). NOTE it is NOT a
  harness/mount artefact: even with a cygexec mount our binaries would still misclassify via detection
  in other paths, and detection is the path exercised here. Todo: exec-root-cause-arm64-machine-allowlist.
- **VERIFIED DYNAMICALLY (c63ab774) — supersedes any "boxed below the Cygwin source / OS
  handle-inheritance anomaly" close-out: the root cause IS in Cygwin source and the one-line fix
  works.** Added `case IMAGE_FILE_MACHINE_ARM64: break;` to PEHeaderFromHModule (hookapi.cc:46) AND
  reverted the get_parent_handle() workaround in the SAME build (clean isolation: only exec-related
  change is the one case label; upstream spawn.cc:594 guard restored verbatim, only the leak-close
  kept). MEASURED before->after: iscygwin 0->1; clear taken yes->no; GetHandleInformation at
  CreateProcessW 0x0->0x1 (INHERIT_SET=1); child in_table 0->1; outcome err6/done0 -> EXEC WORKS.
  Filing evidence/FILING-hookapi-arm64-classification.md, 106/106. This is a SIXTH instance of the
  x86-assumption pattern, and it is the spawn.cc:594 fault site I identified two hours earlier as "the
  mechanism that would produce exactly this err6" — the collective miss was in the CHECKING (all four
  read `if(!iscygwin())` and reasoned "target is Cygwin so it can't fire" without evaluating the
  condition), not in the hypothesis. MOUNT_CYGWIN_EXEC mount-table hypothesis DEAD: this path
  classifies purely by PE inspection, never consulting mount flags. The (A)/(B) split survives intact
  (value crossed as data; validity depended on inheritance we disabled ourselves) — derivation correct,
  terminus one layer short. BLAST RADIUS beyond exec: iscygwin() gates 17 decisions (spawn.cc x12,
  sigproc.cc x3, exceptions.cc x2), all taking the foreign-program branch for every ARM64 binary; only
  exec failed visibly. NOTABLE: spawn.cc:882 SKIPPED the subproc_ready handshake (synced=true without
  sync()) => every pre-fix spawn ran with that barrier suppressed = CAVEAT on both earlier evidence
  bases; exceptions.cc:1063/1714 gate post-exec signal handling, now 5/5. Todo:
  exec-root-cause-VERIFIED-hookapi-fix.
- **iscygwin() 17-SITE BLAST-RADIUS classified from source (MEASURED, all sites opened) + spawn.cc:882
  handshake caveat.** Pre-fix ALL 17 evaluated iscygwin()=0 for ARM64 binaries; the hookapi.cc fix
  flips all to =1 atomically. Sites: spawn.cc x12 (564,577,594,615,626,754,771,865,869,877,882,900),
  sigproc.cc x3 (1044,1071,1204), exceptions.cc x2 (1063,1714). FOUR were real latent functional
  defects masked by the misclassification: (i) spawn.cc:577 ARM64 Cygwin children wrongly got
  CREATE_NEW_PROCESS_GROUP (breaks Ctrl-C/job-control grouping); (ii) sigproc.cc:1044 PROC_EXEC_CLEANUP
  skipped on exec; (iii) sigproc.cc:1071 record_children skipped (non-reaped children not passed to the
  execed process); (iv) spawn.cc:882 synced=iscygwin()?sync():true => the subproc_ready barrier
  handshake was SKIPPED on every pre-fix ARM64 spawn (synced=true set without calling sync()). The rest
  are benign-or-corrective (594 IS the exec bug; 615 term setup; 626 console handler; 771/869
  write_childpid; 900 close_all_files; 754 error-path-only; 564 suspend superset; 877 native-detach
  only; 1204 exit-code retry; 1063/1714 post-exec signal handling, c63ab774 tested 5/5). NONE relied on
  the foreign branch for correctness => the fix introduces no NEW breakage (consistent with 106/106).
  882 CAVEAT scope: the crash-SITE conclusions (RVA 0x6CD8 str x4 TEB spill; quoted() strcpy-overlap)
  are parent-side/pre-CreateProcess static faults and are UNAFFECTED; only timing-sensitive claims
  inherit the barrier-suppressed caveat - stated for the filing.
- **BELT-AND-SUSPENDERS: I CONCUR WITH c63ab774 DROPPING the get_parent_handle() recovery.** My earlier
  note suggested keeping both; c63ab774 dropped the recovery (kept only the leak-close, restored the
  upstream 594 guard verbatim). Their reasoning is sound and I withdraw the keep-both suggestion: once
  the cause is fixed the recovery is dead code on every platform, costs an extra OpenProcess per exec
  including on x86_64 where nothing was wrong, and a mitigation retained beside the real fix obscures
  which is load-bearing + upstream would reject the redundancy. The leak-close is a genuine independent
  pre-existing defect and rightly stays. NO recorded disagreement - agreement.
  Canonical DLL now b4bdbd9e3f7d8d50 (12/12 rungs, 55/55 repeats, 106/106 filing). Todo:
  exec-iscygwin-17site-blastradius-classified.
- **CORRECTION (c63ab774, accepted): 106/106 is a HASH SEAL (SHA256SUMS integrity), NOT a coverage/test
  result. Real test ceiling = 12/12 rungs, 55/55 repeats — a narrow slice; no threads, no job control,
  no signals-across-fork, no real MSYS2 program has run. Never cite 106/106 as a full-surface pass.**
  Consequence: my 17-site per-site benign-vs-latent classification is the ONLY thing bounding the
  atomic-flip risk (the fix flips all 17 branches at once; only a handful have rungs; e.g. spawn.cc:900
  close_all_files(iscygwin()) and :877 detach/nowait change behaviour and have NO rung). The
  classification therefore belongs in the filing's scope section as the answer to "what else did this
  flip?" - "twelve tests passed" is not that answer. VERDICT recorded: none of the 17 relied on the
  foreign branch for correctness, so the flip introduces no new breakage by construction (source), but
  that is a DERIVED-from-source bound, not a tested one - stated as such.
- **CORRECTION (c63ab774, accepted — same error we caught all night): I wrongly wrote "if any site had
  relied on the foreign branch you'd have seen a regression when the label landed; you didn't." That is
  invalid: the 12 rungs do NOT enter most of the 17 sites (they miss close_all_files teardown,
  _P_DETACH/_P_NOWAIT, console-handler setup, terminal setup, write_childpid). A pass on a suite that
  never enters a branch is not evidence about that branch — the "green result whose scope didn't cover
  the broken thing" family. The 55/55 does NOT corroborate the classification. The classification rests
  on the SOURCE READING ALONE (all 17 opened): DERIVED, "classified from source, largely untested
  dynamically." No implied cross-validation. This is the same correction c63ab774 made to its own
  106/106 (seal count, not coverage) and I applied it to my reasoning in turn.
- **882 CAVEAT vs the two earlier defects — checked against the evidence, not around it (c63ab774 asked
  a second party to check their own self-assessment): NEITHER conclusion leaned on the suppressed
  barrier.** Fork-headroom (RVA 0x6CD8 `str x4,[sp,#24]` TEB spill onto cygheap+8): verified by
  instruction-level disassembly of a STATIC store target in the DLL image - no runtime timing input, so
  barrier-independent. Argv-overlap (quoted() strcpy(X,X+1) UB, NEON-exposed): verified by source-level
  UB identification + byte-for-byte argv round-trips across 40 lengths - parent-side string handling
  BEFORE any spawn barrier, so barrier-independent. Both rest on instruction/byte measurement, not on
  timing-sensitive behaviour. The 882 caveat is REAL but bounded to timing-sensitive claims, and
  neither of these is one. Concur with c63ab774's self-assessment after independent check.
- Todos: wild-is-teb, birth-stack-named, teb-store-comprehensive-negative, teb-field-write-scan-
  corrected, cygthread-stub-and-cygheaplow-scan, crossthread-framing-retracted,
  cygheap-relocation-is-shared-boundary.

## Files (READ-ONLY, none edited)
- local_includes/memory_layout.h:34-47 (THREAD/CYGHEAP/USERHEAP abutting partition) [PRIMARY SOURCE]
- dcrt0.cc:855 (victim born), :870-883 (fork-gated teb->Tib.StackBase= write), :749/753/779 (init order)
- mm/cygheap.cc: cygheap global@35, child fixup VirtualAlloc@92/96, chain walk@113, ce cast@115,
  _cmalloc@365 (reuse@381-386, chain write@398), _cfree@404, creturn@442 (type@454), cmalloc/
  ccalloc/cstrdup@461-577; cygheap_entry{type@0,next@8,data@16}@40; _cmalloc_entry@cygheap.h:15
- mm/malloc.cc: win32mmap@1670, win32direct_mmap@1676, _gm_@2634 (.bss), seg@2601, HAVE_MORECORE 0@547
- mm/mmap.cc: private-anon mmap_req@1590, VirtualAlloc2@1600
- create_posix_thread.cc: thread_req THREAD_STORAGE@144, mmap fallback@165/175
- local_includes/memory_layout.h:51 MMAP_STORAGE_LOW=0x001000000000 (64 GiB) [PRIMARY SOURCE]
- gcc-src/libgcc/emutls.c: emutls_alloc@110, __emutls_get_address@148
- emutls probe: /root/xc/build-gcc2/aarch64-pc-cygwin/libgcc/emutls.o (DWARF), gcc -v (--disable-threads)
- built DLLs: /root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll (+ -fixedbase); 273 .o recursive
