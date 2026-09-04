<overview>
This session is the read-only "defects investigator" (Copilot session `57224227`) in a multi-session ARM64 vNext programme making the MSYS2 runtime (`msys-2.0.dll`) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). The coordinator is chat session `2b2e50a5-63c5-49f9-8b89-d825396b5ff9`; the runtime-tree owner making ALL edits is session `c63ab774-a023-4e57-9bc4-53f727507ada`. This session performs local compile/disassemble/DWARF-inspect/static-analysis ONLY (never edits source, never commits/pushes/PRs), reporting MEASURED/DERIVED/PRESUMED findings via `send_session_message`. The current focus is a cygheap chain-head corruption bug: one entry's `prev` slot (`cygheap+8`, the chain head) is transiently clobbered to a high (512 GiB+) OS-pointer value during Cygwin's own startup, present in every process (even non-forking rung9), leaving an orphaned/unterminated chain.
</overview>

<history>
1. **Prior context (carried in summary):** This session had closed four original runtime-ABI defects + a TEB `__getreent` fix; bounded the arch-conditional sweep; exonerated `_cygtls`, thread-stack, fork-copy by measurement; found the real crash bug (`import_address` bare `0x25ff` opcode compare, fixed by c63ab774); and was investigating the cygheap chain-head clobber. Checkpoints 001–010 recorded.

2. **Coordinator confirmed emutls kill + TLS correction:** Reconciled that emutls.o was pulled by a test exe (`p3.exe` using `__thread`), not the runtime DLL. Delivered a **binding correction**: `tpidr_el0` reads ZERO on Windows-on-ARM; correct TEB path is **x18** (read-only, never write, never use tpidr_el0). Re-stated PRIMARY task: enumerate every startup store of a malloc/calloc/realloc/cmalloc result into a struct field at offset +8.
   - I created checkpoint 011, absorbed the TLS correction (purged stale tpidr description), and ran the offset-8 enumeration.
   - MEASURED: full `init_cygheap` DWARF map (only `lh_first@0`, `chain@8`, `buckets@16` in first 64B; all other pointer fields ≥272); `buckets[b]` index is `unsigned`, bounded, LP64-identical; ZERO casts/overlays of `cygheap` base to another type. Reported all as clean negatives to both sessions (Results A–D in checkpoint 011).

3. **Coordinator accepted the triage + flagged watchpoint unreliability:** Endorsed my finding "writer stores through a base that is NOT cygheap yet resolves to cygheap+8." Handed the `buckets[-1]==chain` idea (buckets@16, chain@8 ⇒ buckets[-1] IS chain). Recommended constant-independent instruments.
   - I ran the `buckets[-1]` search: MEASURED NEGATIVE — `buckets` referenced in exactly 6 sites (all cygheap.cc), `b` unsigned everywhere, no negative-index path (Result F). Recorded address-map adjacency (THREAD_STORAGE_HIGH==CYGHEAP_STORAGE_LOW==0x800000000) as a ranking prior (Result E). Reported; called task_complete.

4. **c63ab774 pinned the defect to ONE 8-byte slot:** Live rung9 reads showed entry `0x8000068C0` (username `crutkasLocal`, prev correct) → `0x8000068F0` (prev WILD `0x8DCA825000`) → `0x800006A00` (prev correct). Exactly one slot wrong. Two corrections: (1) `bucket_val` is an explicit TABLE (…2048,3072,4096,6144…), not `1<<b`; with it the intact sub-chain abuts to the byte; (2) `MMAP_STORAGE_LOW/HIGH` are Cygwin's PLACEMENT bookkeeping, not a reserved range, so the wild value need not come from Cygwin's mmap — retiring my ptmalloc hypothesis. Flagged a timing contradiction: bytes place the clobber inside setup_cygheap, conflicting with my earlier "mmap arena doesn't exist there" argument.
   - I RESOLVED the contradiction by measurement (Result G): `ce->type=1` = **HEAP_STR** (the cstrdup class); `cygheap_user::init()` runs at cygheap.cc:321 INSIDE setup_cygheap; mechanism is transient head corruption (`rvc->prev=cygheap->chain` captured a momentarily-wild head, restored by the next birth). **Acknowledged my earlier window withdrawal was the error — bytes outrank narrative.** Reported to c63ab774.

5. **c63ab774 measured stack adjacency as SHARED (not arch):** Live scans showed StackBase==0x800000000==cygheap base on BOTH ARM64 and x86-64 3.6.9 (identical to the byte; x86-64 chain clean). So "stack placed differently on ARM64" is eliminated; the difference must be in WHAT WRITES near StackBase.
   - I hunted StackBase-adjacent writers. Tested the `_cygtls`-overflow mechanism (`_my_tls = StackBase − __CYGTLS_PADSIZE__`, pad=12800): MEASURED `sizeof(_cygtls)=5016` via DWARF → 7784B headroom, no overflow (Result I). Also refined the foreign-store window: setup_cygheap tail allocates only the username; the store is in the `memory_init` early path (`mountinfo.init`/`internal_getpwsid`/pwdgrp load) where OS-buffer APIs live (Result H). Reported both to c63ab774.

6. **c63ab774 reported watchpoint failure IN THE GAP:** The (a)4-writes vs (b)3-writes count can't be captured because the gap coincides with five LOAD_DLL events + one thread creation (where the births + early allocator run). Platform facts: HW watchpoint hits arrive as `0x80000003` (indistinguishable from ordinary breakpoints); instrument has an uncharacterised DLL-load/thread-create limitation. Consequence: needs a read-at-known-points approach, not write-capture.
   - I checked dll_list::alloc/append/populate_deps as the +8 writer: all write into freshly-cmalloc'd dll blocks or `_cygtls`/.bss, NOT through a cygheap base — NOT the writer (Result J). **Was mid-writing checkpoint 011 Result J including a constructive read-at-known-points design** (ordinary breakpoints at cygheap.cc:397/398 bracketing each birth to distinguish head-wild-at-birth vs overwritten-after-birth) when compaction was requested. That edit to checkpoint 011 succeeded; I had NOT yet sent the Result J report to c63ab774.
</history>

<work_done>
Files updated (session-state only — ZERO source edits, entirely read-only investigation):
- `checkpoints/011-emutls-negative-mmap-correction-allocator-clean.md` — CREATED and extensively expanded this session. Contains Results A–J. **Result J was just added (read-at-known-points design); its report to c63ab774 was NOT yet sent when compaction hit.**
- `checkpoints/index.md` — checkpoint 011 row added.
- `checkpoints/009-*.md` — has a SUPERSEDED/CORRECTED banner from a prior segment (still contains the factor-of-16 error below the banner).
- `files/rd.sh` — KEPT (persistent helper: `bash rd.sh FILE START END` prints numbered line range from `/root/xc/w-defects/winsup/cygwin`).
- Scratch scripts created and DELETED (cleaned): allocstore.sh, allocstore2.sh, choff.sh, osalloc.sh, winfn.sh, iir.sh, stackbase.sh, cygtlssz.sh, cygtlssz2.sh.

Todos DB: 24 rows, 23 done + 1 pending (`x86_64-build-verify`).

Work completed this session:
- [x] Offset-8 enumeration — full init_cygheap DWARF map; only chain@8; buckets bounded; no cygheap alias/overlay. All MEASURED NEGATIVE (Results A–D).
- [x] Address-map adjacency prior recorded (Result E).
- [x] `buckets[-1]==chain` idea — MEASURED NEGATIVE (Result F).
- [x] Timing contradiction RESOLVED (type=1=HEAP_STR; user.init inside setup_cygheap; transient mechanism) — corrected my own prior window withdrawal (Result G).
- [x] Foreign-store window refined to memory_init early path (Result H).
- [x] `_cygtls`-overflow-past-StackBase — MEASURED NEGATIVE, sizeof=5016 < pad 12800 (Result I).
- [x] dll_list stores are NOT the +8 writer; read-at-known-points design authored (Result J, checkpoint written).
- [ ] **Send Result J report to c63ab774** (checkpoint written, message NOT sent — immediate next action).
- [ ] `x86_64-build-verify` (pending) — awaiting coordinator go/no-go; this session cannot RUN binaries.
</work_done>

<technical_details>
- **THE BUG (current best understanding):** A SINGLE transient 8-byte store to `cygheap+8` (== `StackBase+8` == `0x800000008`) during Cygwin startup poisons exactly one chain entry's `prev` slot. MEASURED chain (c63ab774, rung9): `0x48A0(b=12,prev=NULL)` → `0x50B0(b=15)` → `0x68C0(b=0, username crutkasLocal)` → `0x68F0(b=6, WILD prev)` → `0x6A00(correct)`. The sub-chain below the wild entry is intact and merely orphaned. Head starts correct, is momentarily wild during one birth, restored by the next. The wild value is a high (512 GiB+) OS-pointer.
- **`bucket_val` is an explicit TABLE** (cygheap.cc:281): `{32,48,64,96,128,192,256,384,512,768,1024,1536,2048,3072,4096,6144,...}` — NOT `1<<b`. With it: `0x48A0+16+2048=0x50B0`; `0x50B0+16+6144=0x68C0`; `0x68C0+16+32=0x68F0` (abuts to the byte). `b=6`→bucket_val[6]=256, so the wild entry is a ~193–256B HEAP_STR allocation.
- **`ce->type=1` = HEAP_STR** (enum cygheap_types, cygheap_malloc.h:14, 0-indexed: HEAP_FHANDLER=0, HEAP_STR=1, HEAP_ARGV=2, HEAP_BUF=3, HEAP_MOUNT=4, HEAP_SIGS=5, HEAP_ARCHETYPES=6, HEAP_TLS=7, HEAP_COMMUNE=8, HEAP_USER=9, HEAP_1_START=10, HEAP_1_MAX=100, HEAP_2_MAX=200). `cstrdup`=HEAP_STR (cygheap.cc:567).
- **MMAP_STORAGE_LOW/HIGH are PLACEMENT bookkeeping, not a reservation** (c63ab774's correction): `0x8DCA825000` need NOT come from Cygwin's mmap — any VirtualAlloc(0,)/HeapAlloc by loader/ntdll/CRT/Windows-heap can land in that band. **My ptmalloc hypothesis is RETIRED.** (Earlier I made a factor-of-16 error on MMAP_STORAGE_LOW: it is `0x001000000000`=64 GiB, not 1024; that's settled.)
- **StackBase adjacency is a SHARED design property** (c63ab774 MEASURED on both arches): `THREAD_STORAGE_HIGH==CYGHEAP_STORAGE_LOW==StackBase==0x800000000`, so `cygheap+8==StackBase+8`. Identical on x86-64 3.6.9 (clean chain). So the arch difference is NOT stack placement — it's WHAT WRITES near StackBase (an offset/size/alignment differing on ARM64, or an ARM64-only path). c63ab774's triage question: is the faulting store's base register sp/x18-derived?
- **`_cygtls`-overflow eliminated:** `_my_tls = *(_cygtls*)(StackBase − __CYGTLS_PADSIZE__)` (cygtls.h:316); `__CYGTLS_PADSIZE__=12800` (config.h:31, no arch conditional). MEASURED `sizeof(_cygtls)=5016` (DWARF byte_size, cygtls.o) → 7784B headroom, no overflow into cygheap+8. Also an overflow would write cygtls CONTENT, not an OS pointer.
- **Allocator structurally cannot clobber the head:** `_cmalloc` chains once at birth (cygheap.cc:397-398), never unlinks; freelist(+0)/chain(+8) disjoint; `cygheap` global is stable (only `&cygheap_dummy` or `VirtualAlloc(CYGHEAP_STORAGE_LOW)`). So the head clobber is a FOREIGN store.
- **The window (MEASURED):** dll_crt0_0 (dcrt0.cc): 753 setup_cygheap() → 754 memory_init(). setup_cygheap (cygheap.cc:318): cygheap_init/user.init(321)/init_installation_root(322)/pg.init(323). user.init allocates ONLY the username cstrdup (no cmalloc after set_name); init_installation_root allocates nothing (its registry block is `#ifndef __MSYS__`, compiled out); pg.init allocates nothing. So the foreign store is in the memory_init early path: user_info::initialize (shared.cc:191) runs mountinfo.init(false)@201, internal_getpwsid@203, set_name(pw->pw_name)@207 — where OS-buffer APIs (LookupAccountSidW, NetUserGetInfo/NetLocalGroupGetInfo) live.
- **dll_list is NOT the +8 writer:** dll_list::alloc (dll_init.cc:346-388) writes only into the cmalloc'd `dll* d`; append (392) threads the dll chain whose head is `.bss` global `dlls`; populate_deps uses `tmp_pathbuf` which stores into `_my_tls.locals.pathbufs` (inside _cygtls, safely below StackBase). None store through a cygheap base.
- **Watchpoint instrument limitation (c63ab774):** HW watchpoint hits arrive as `0x80000003` EXCEPTION_BREAKPOINT (indistinguishable by code from ordinary breakpoints; only per-thread state separates). The instrument silently misses writes during the DLL-load/thread-create burst (five LOAD_DLL + one thread create) — exactly the gap. Re-arm did NOT fail. Cause uncharacterised. So (a)4-writes vs (b)3-writes can't be counted by write-capture.
- **The (a)/(b) discriminator is still open:** head wild AT BIRTH (foreign store before 0x68F0's birth) vs slot overwritten AFTER birth. Per-run value VARIATION does NOT discriminate (both vary). My proposed read-at-known-points design (Result J): ordinary breakpoints at cygheap.cc:397 and :398 bracketing each birth, read [cygheap+8] before/after — immune to the watchpoint's DLL-load limitation, needs no capability c63ab774 lacks.
- **Environment:** objdump/nm/gcc prefix `/root/xc/inst/bin/aarch64-pc-cygwin-*`; `--dwarf=info`/`-d`/`-t`. Cannot EXECUTE aarch64 binaries in WSL — measure via compile/disasm/DWARF/static_assert only. Built objects with DWARF under `/root/xc/w-link/bld/winsup/cygwin/` (recursive `find` needed for `mm/` subdir; 273 objects). Built DLLs: `new-msys-2.0.dll`, `-fixedbase.dll`. Source tree: `/root/xc/w-defects/winsup/cygwin` (READ-ONLY). Do NOT touch `/root/xc/inst`, `/root/xc/runtime`, `/root/xc/bld`, `/root/xc/w-autoload`, `/root/xc/w-gendef`, or the Windows worktree.
- **PowerShell→WSL quoting (binding workaround):** inline `bash -c` with `$VAR`, `$(...)`, `awk`, commas mangle under PowerShell. RELIABLE PATTERN: write a `.sh` via the `create` tool into session-state `files/`, then `wsl -d Ubuntu bash -c "sed -i 's/\r//' /mnt/c/.../files/x.sh; bash /mnt/c/.../files/x.sh"`. Session-state visible in WSL at `/mnt/c/Users/crutkasLocal/.copilot/session-state/57224227-53ba-4c06-95b3-0ae9d9058bd5/files/`.
- **METHOD RULES (binding):** non-match is never absence (open the file); measure what the compiler/linker emits; echo-to-transcript is not persistence (redirect to file); distinguish MEASURED/DERIVED/PRESUMED; a CORRECTION IS A CLAIM (re-derive from primary source, don't accept a derived figure); kill leads by measurement; NEVER write x18; LSE atomics unavailable (use ldaxr/stlxr); a property that looks like a smoking gun on one arch means nothing until the other is checked (the differential has killed 4+ hypotheses).
</technical_details>

<important_files>
- `C:\Users\crutkasLocal\.copilot\session-state\57224227-53ba-4c06-95b3-0ae9d9058bd5\checkpoints\011-emutls-negative-mmap-correction-allocator-clean.md`
  - The active checkpoint; contains Results A–J. Result J (read-at-known-points design) just added.
  - **The report of Result J to c63ab774 was NOT yet sent** — immediate next action.
- `/root/xc/w-defects/winsup/cygwin/mm/cygheap.cc` (READ-ONLY; heart of the bug)
  - `cygheap` global assignments @35/92/96/293/297; `bucket_val` table @281; `cygheap_init`@289 (VirtualAlloc@293/297, fdtab.init@309, sigalloc@311, init_tls_list@312); `setup_cygheap`@318 (user.init@321, init_installation_root@322, pg.init@323); `_cmalloc`@365 (bucket calc@371-378, reuse@381-386, chain write@397-398); `_cfree`@404 (b=rvc->b@409); `init_installation_root`@161-273 (registry block @263-272 is `#ifndef __MSYS__`); `cygheap_fixup_in_child` chain walk @113.
- `/root/xc/w-defects/winsup/cygwin/local_includes/cygheap.h` (READ-ONLY)
  - `_cmalloc_entry`@15 (union{unsigned b; char*ptr}@0, prev@8, data@16); `cygheap_entry`@40 (type@0,next@8,data@16); `NBUCKETS 32`@489; `buckets[NBUCKETS]`@505; init_cygheap chain@504.
- `/root/xc/w-defects/winsup/cygwin/local_includes/cygtls.h` (READ-ONLY)
  - `_my_tls = *(_cygtls*)(StackBase − __CYGTLS_PADSIZE__)`@316.
- `/root/xc/w-defects/winsup/cygwin/include/cygwin/config.h` (READ-ONLY)
  - `__CYGTLS_PADSIZE__ 12800`@31.
- `/root/xc/w-defects/winsup/cygwin/local_includes/cygheap_malloc.h` (READ-ONLY)
  - `enum cygheap_types`@14 (HEAP_STR=1).
- `/root/xc/w-defects/winsup/cygwin/uinfo.cc` (READ-ONLY)
  - `cygheap_user::init`@39 (set_name@58, token/sec block 63-110); `cygheap_pwdgrp::init`@585; `pwdgrp::add_line`@566 (crealloc_abort@573); NetUserGetInfo@389 (inside ontherange@332, NOT window).
- `/root/xc/w-defects/winsup/cygwin/mm/shared.cc` (READ-ONLY)
  - `user_info::initialize`@191 (mountinfo.init@201, internal_getpwsid@203, set_name@207); `memory_init`@323.
- `/root/xc/w-defects/winsup/cygwin/dll_init.cc` (READ-ONLY)
  - `dll_list::alloc`@346 (cmalloc d@350), `append`@392, `populate_deps`@402.
- `/root/xc/w-defects/winsup/cygwin/local_includes/memory_layout.h` (READ-ONLY)
  - THREAD_STORAGE@34-35, CYGHEAP@39-41 (LOW=0x800000000), MMAP_STORAGE_LOW=0x001000000000@51 (=64 GiB).
- `/root/xc/w-link/bld/winsup/cygwin/cygtls.o` (READ-ONLY build artifact) — DWARF source: sizeof(_cygtls)=5016.
- `/root/xc/w-link/bld/winsup/cygwin/mm/cygheap.o` (READ-ONLY) — DWARF: init_cygheap member map.
- `files/rd.sh` (session-state helper, KEPT).
</important_files>

<next_steps>
Immediate next action (in-flight at compaction):
1. **Send the Result J report to c63ab774** (`c63ab774-a023-4e57-9bc4-53f727507ada`): dll_list is NOT the +8 writer (all stores go into cmalloc'd dll blocks or _cygtls/.bss, not through a cygheap base); the wild value is most plausibly the loader's own HeapAlloc bookkeeping during the five DLL loads; AND hand over the **read-at-known-points design** (ordinary breakpoints at cygheap.cc:397/398 bracketing each birth, read [cygheap+8] before/after — immune to the watchpoint's DLL-load limitation, distinguishes head-wild-at-birth (a) from overwritten-after-birth (b)). Note the caution: per-run value variation does NOT discriminate (a)/(b).

Remaining threads (all deferred, correctly):
- The single foreign store's PC and the (a)/(b) discriminator — dynamic, c63ab774's lane (my read-at-known-points design is the proposed instrument).
- `x86_64-build-verify` (todo pending): build our tree for x86_64 to make ARM64-specificity definitive (differential used foreign GfW 3.6.9). Awaiting coordinator go/no-go. Caveat: this session can BUILD but cannot RUN/verify (WSL cross-only) — verify needs a Windows-host session.

Constraints (binding): read-only, edit no source, report to both c63ab774 and coordinator (2b2e50a5-63c5-49f9-8b89-d825396b5ff9), measure don't assume, re-derive corrections from primary source, never claim a product PASS. In autopilot: don't idle-wait, but don't fabricate static work — the constant-independent static surface for this bug is now thoroughly mapped; productive next steps are dynamic (c63ab774) or the x86_64 build (coordinator authorization).
</next_steps>