<overview>
This session is the read-only "defects investigator" (Copilot session `57224227`) in a multi-session coordinated programme to make the MSYS2 runtime (`msys-2.0.dll`) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). The coordinator is chat session `2b2e50a5-63c5-49f9-8b89-d825396b5ff9` ("General Chat" / "Arm64 vnext resume"); the runtime-tree owner who makes ALL edits is session `c63ab774-a023-4e57-9bc4-53f727507ada` ("Link arm64 msys runtime dll"). This session performs local compile/disassemble/DWARF-inspect/static-analysis ONLY and reports MEASURED / DERIVED / PRESUMED findings back to those two sessions via `send_session_message`. The current focus is a `fork()`/cygheap-chain corruption bug, now reframed by c63ab774 as a **cygheap chain-head corruption present in EVERY process (even one that never forks)**, not a fork defect.
</overview>

<history>
1. (Carried from prior summaries) This session previously closed four original runtime-ABI defects + a TEB `__getreent` fix; retracted a binutils base-reloc hunt; disproved a dll_info layout audit; bounded the arch-conditional `#ifdef/#else` sweep at four instances; exonerated `_cygtls`/`__CYGTLS_PADSIZE__` and `create_new_main_thread_stack` by measurement; and ran the "x86 assumption encoded as DATA" sweep (found the real crash bug class — `import_address()` bare `0x25ff` opcode compare in `malloc_wrapper.cc`, fixed by c63ab774, enabling rung 3/4/5a to pass).

2. c63ab774 reported (informational) that rung 5a signals PASS and `fork()` now fails in `cygheap_fixup_in_child` (mm/cygheap.cc:116) walking `cygheap->chain` onto an unmapped `prev`. It offered an optional static-read target (child_copy / cygheap_max bounds).

3. This session took that target (todo `cygheap-fork-audit`):
   - Read `cygheap_fixup_in_child` (cygheap.cc:85-127), `child_copy` (fork.cc:731), `_cmalloc`/`_csbrk`/`cygheap_max`, `_cmalloc_entry`/`child_info` structs, memory_layout.h constants.
   - Concluded CORRECT NEGATIVE: region is arch-clean, LP64-identical to x86_64. Reported to both sessions. Also gave static corroboration of c63ab774's `x18=0` lead (source writes x18 nowhere) without building on it. Recorded checkpoint 006.

4. Coordinator replied: corrected that the fault target `0xBD102AE000` is NOT in the cygheap region, so truncation is not the mechanism. New assignment: enumerate every cygheap allocation between `refresh_cygheap()` (fork.cc:338) and the child copy, and determine whether size/count can differ on ARM64 — killing my own "post-snapshot allocation" structural note by measurement rather than argument.

5. This session executed the post-snapshot allocation audit (todo `post-snapshot-cygheap-alloc-audit`):
   - Read fork.cc:320-480 (the parent window 338→410), opened every callee, launched one explore agent to trace the whole window, then personally verified the two load-bearing negatives (`request_forkables`/forkable path and `fixup_before_fork`).
   - RESULT: ZERO cygheap allocations in the parent window on either arch. Key evidence: the only forkable cmalloc (forkable.cc:540) carries the comment "allocate here, to avoid cygheap size changes during fork" and is deliberately hoisted to DLL-load time — the authors already defended against exactly this mechanism. Reported to both sessions. Recorded checkpoint 007.

6. Coordinator accepted the kill and gave a new assignment: find where `cygheap->chain` is initialised to NULL and whether that path runs on ARM64; check for zero-fill reliance, cygheap creation API/flags, adjacent-field spill into `chain`, and what allocates at an OS-chosen address in early init.

7. This session began the chain-init audit (todo `cygheap-chain-init-audit`):
   - MEASURED via DWARF from the built ARM64 object `cygheap.o`: `sizeof(init_cygheap)=0x48A0 (18592)`, `offsetof(chain)=8`, `sizeof(mini_cygheap)=8`, full member-offset map. Confirmed the flagged entry at cygheap offset `0x68F0` is PAST the 0x48A0 header, so it's a real `_cmalloc` region, not a header misread. Confirmed `cygheap->chain` has exactly ONE writer (cygheap.cc:398). Confirmed cygheap region is only ever created by `VirtualAlloc` (zero-filled), no file/section mapping. Cleaned scratch.

8. c63ab774 sent a major reframe mid-audit: it built `rung8.exe` (never forks) and found the SAME broken chain — so **the chain is corrupt parent-side in every process; it is NOT a fork defect**. It confirmed my struct measurements independently, settled `x18` as a GetThreadContext artefact (stand down), killed its own "pre-init dummy `_cmalloc`" hypothesis (cygheap_max NULL → `_csbrk` returns NULL → `dll_list::alloc` null-deref would crash; no crash = dead). It asked: what can call `_cmalloc`/`cmalloc` (or write `cygheap->chain`) BEFORE `cygheap_init()`.

9. This session traced pre-init allocators (retargeted the todo): read `cygheap_dummy` (cygheap.cc:30-35), found `setup_cygheap()` is called at dcrt0.cc:753 AFTER `do_global_ctors` at dcrt0.cc:748. Launched an explore agent to enumerate pre-init cmalloc callers; it returned a HIGH-confidence bounded negative (no cygheap allocation runs before setup_cygheap).

10. c63ab774 sent a second reframe (most recent inbound of substance): it killed the pre-init-dummy path too, and TIGHTLY LOCALISED the clobber: the username entry ("crutkasLocal") at 0x8000068F0 (from `cygheap->user.init()` → `set_name` → `cstrdup`) is ORPHANED (not on the chain), `b=6` intact at +0, `prev` wild. So `cygheap->chain` is clobbered BETWEEN the username allocation and the next `cmalloc` in `setup_cygheap()` (`init_installation_root()`, then `pg.init()`). It eliminated: linear overrun (b@+0 intact), wide locale write (all 8-byte stores, sizeof(cygheap_locale)=8, no memcpy/memset on header). It asked this session to enumerate every 8-byte write to `cygheap+8` and every path between `user.init()` and the next cmalloc. It cautioned: arch-differential is UNKNOWN — frame as "a cygheap defect observed on ARM64", not "an ARM64 defect".

11. This session (final actions before compaction) retargeted the todo and analysed the clobber window:
    - Read `init_installation_root` (cygheap.cc:161-273): writes only into `installation_root_buf`@288 / `installation_dir_buf`@8496 / `installation_key_buf`@16704 and UNICODE_STRING headers — all far above chain@8; `reg_key` block is `#ifndef __MSYS__` (excluded on MSYS). No write near cygheap+8.
    - Read `cygheap_user::init` (uinfo.cc:39-111): username via VLA (stack) → `set_name` → `cstrdup` (the 0x68F0 entry); `sec_user_nih` at line 90 (does NOT allocate from cygheap — grep empty).
    - Read `cygheap_user::set_name` (cygheap.cc:614-637): first call allocates username and returns early.
    - Read `cygheap_pwdgrp::init` (uinfo.cc:585-604) and `init_pwd`/`init_grp` (passwd.cc:50, grp.cc:56): these only set function pointers and sizes — NO cygheap allocation, no mmap.
    - Dumped full init_cygheap member offset map via DWARF; no header field sits near +8 other than chain itself.
    - Classified the wild `prev` values against cygheap bounds (LOW=0x800000000, INITIAL=0x800300000, HIGH=0xa00000000): all values (0xBD102AE000, 0x80002D1000, 0xDDC4F01000, 0x8000316000, 0x8000384000, 0x80002CA000) are OUTSIDE the cygheap reserve — the mmap arena, as c63ab774 said. (Initial hex misread corrected.)
    - Cleaned scratch files. Had NOT yet sent the report to the two sessions when compaction was requested.
</history>

<work_done>
This session made ZERO file edits throughout — it is entirely read-only investigation. All prior-turn fix files remain intact in `/root/xc/w-defects`.

Work completed this session:
- [x] `cygheap-fork-audit` (child_copy / cygheap_max) — CORRECT NEGATIVE, reported, checkpoint 006.
- [x] `post-snapshot-cygheap-alloc-audit` — ZERO allocations in fork window; lead killed by measurement; reported; checkpoint 007.
- [x] Chain-init measurements: DWARF-confirmed sizeof(init_cygheap)=0x48A0, offsetof(chain)=8, full offset map; single writer of chain; VirtualAlloc-only region (zero-filled).
- [x] Pre-init cmalloc caller trace (explore agent): bounded negative — nothing allocates from cygheap before setup_cygheap.
- [x] Clobber-window analysis: `init_installation_root`, `user.init`/`set_name`, `pg.init`/`init_pwd`/`init_grp` all read/verified; none write near cygheap+8; pg.init does not allocate; wild values classified as mmap-arena (outside cygheap).
- [ ] **IN PROGRESS / NOT YET REPORTED:** the chain-clobber findings (todo `cygheap-chain-init-audit`, still status `in_progress`) have NOT been sent to c63ab774 or 2b2e50a5 yet, and no checkpoint 008 has been written.

Todos DB: `cygheap-chain-init-audit` is `in_progress` (id 15); all others done. (Todo count reported as 14 done / 15 total but the reminder text lags.)

Scratch: all temporary probe scripts (probe_dwarf.sh, probe_size.sh, probe_chain.sh, probe_off.sh, cygheap_dwarf.txt, classify.py) have been deleted. `git status` in `/root/xc/w-defects` shows only prior-turn tracked fix files modified (compile, config.guess/sub, depcomp, install-sh, missing, mkinstalldirs, newlib ctype_.c, aarch64 asmdefs.h/rawmemchr.S, etc.) — none touched this session.
</work_done>

<technical_details>
- **THE BUG (reframed, current understanding):** `cygheap->chain` gets clobbered to an mmap-arena pointer (outside the cygheap). The chain becomes unterminated; walking it (e.g. in `cygheap_fixup_in_child` during fork, OR any chain walk) dereferences a `prev` in the mmap arena. It is present in EVERY process (rung8 never forks yet has the identical broken chain), so it is a cygheap-init/setup defect, NOT a fork defect. `child_copy` faithfully reproduces the already-broken parent chain.
- **TIGHT LOCALISATION (from c63ab774, MEASURED by it):** username entry "crutkasLocal" at `0x8000068F0` (cygheap offset 0x68F0), from `cygheap->user.init()` → `set_name` → `cstrdup` → `cmalloc`, is ORPHANED (should be on chain, isn't). Its `b`=6 at +0 is intact; its `prev`@+8 is wild. So `cygheap->chain` was clobbered between that cstrdup and the very next `_cmalloc`. Everything earlier is orphaned.
- **MEASURED struct facts (DWARF from `/root/xc/w-link/bld/winsup/cygwin/mm/cygheap.o`, which carries full DWARF):** `sizeof(init_cygheap)=0x48A0=18592`; member offsets — `lh_first`/base@0, `chain`@8, `buckets`@16, `installation_root`@272, `installation_root_buf`@288, `installation_dir`@8480, `installation_dir_buf`@8496, `installation_key`@16688, `installation_key_buf`@16704, `root`@16744, `dom`@16752, `pg`@16960, `ugid_cache`@17912, `user`@17944, `user_heap`@18336, `shared_regions`@18376, `umask`@18408, `rlim_as_id`@18412, `rlim_core`@18416, `console_h`@18424, `cwd`@18432, `fdtab`@18480, `sigs`@18528, `ctty`@18536, `threadlist`@18544, `sthreads`@18552, `pid`@18556, `inode_list`@18560, `hooks`@18568. NO header field sits at or near +8 except `chain` itself. `sizeof(mini_cygheap)=8` (single `cygheap_locale`=`{mbtowc_p mbtowc}`, one 8-byte fn ptr). `sizeof(_cmalloc_entry)=16` (union{unsigned b; char*ptr}@0=8B, prev@8=8B, data@16), all LP64-identical x86-64/ARM64.
- **`cygheap->chain` has exactly ONE writer** in all source: `mm/cygheap.cc:398` (`cygheap->chain = rvc`, where `rvc` is a `_csbrk` result = in-cygheap). Read at :398 (`rvc->prev = cygheap->chain`) and the fork walk at :113. `grep` for every `chain` access confirmed no stray named writer.
- **`_csbrk` (cygheap.cc:326-357)** returns `prebrk = cygheap_max` (in-cygheap) or NULL — it can never return an mmap-arena pointer if cygheap_max is sane. So an mmap-arena value in a `prev` field cannot come from the allocator; it implies a **stray non-allocator write to `cygheap+8`** (or `cygheap->chain` held that stray value at allocation time). This is the decisive structural conclusion NOT YET REPORTED.
- **Wild `prev` values are ALL OUTSIDE the cygheap** (LOW=0x800000000, INITIAL=0x800300000, HIGH=0xa00000000). Values 0xBD102AE000 / 0x80002D1000 / 0xDDC4F01000 / 0x8000316000 / 0x8000384000 / 0x80002CA000 are the mmap arena (Cygwin places it high). These are OS-chosen and per-run-varying. NOTE: mmap-arena addresses are produced by `VirtualAlloc(NULL,...)` in `heap.cc:121`, `malloc.cc:1670/1676`, `mmap.cc:1611`, which run in `memory_init()`/`user_heap.init()` at/after dcrt0.cc:754 — i.e. AFTER `setup_cygheap()`. So the mmap-arena value did not exist when the username was allocated during setup_cygheap; this suggests the clobber may be a stray write occurring LATER than setup_cygheap, or a write of an mmap pointer into cygheap+8 after memory_init. (This temporal tension is an important open thread to raise with c63ab774.)
- **`init_installation_root` (cygheap.cc:161-273):** writes only high buffers (offset ≥288); `#ifndef __MSYS__` excludes the `reg_key` registry block on MSYS; `#ifdef __MSYS__` adds a "back two folders" loop (223-238). No write near cygheap+8. `hash_path_name`, `RtlInt64ToHexUnicodeString` used.
- **`pg.init()` (uinfo.cc:585) / init_pwd (passwd.cc:50) / init_grp (grp.cc:56):** set function pointers and sizes only — NO cygheap allocation, NO mmap.
- **`cygheap_init()` (cygheap.cc:288-313)** order: VirtualAlloc reserve+commit (root path) OR for child the fixup path; then sets locale.mbtowc/umask/rlim_core; then `fdtab.init()`, `sigalloc()` (cygheap.cc:311 → sigproc.cc), `init_tls_list()` (cygheap.cc:312 → ccalloc_abort at :648). `setup_cygheap()` (cygheap.cc:318) = cygheap_init(); user.init(); init_installation_root(); pg.init().
- **`do_global_ctors` runs at dcrt0.cc:748, BEFORE `setup_cygheap()` at dcrt0.cc:753** (in `dll_crt0_0`, root path only; child path calls handle_fork at :762). Explore agent found no global ctor allocates from cygheap.
- **x18 SETTLED:** GetThreadContext reporting artefact for the platform-reserved register (c63ab774 confirmed via a healthy rung3 control that also showed x18=0). Stand down. My "Cygwin writes x18 nowhere" made it decidable.
- **FRAMING CAUTION (binding, from c63ab774):** arch-differential is UNKNOWN. No ARM64-specific trigger found; every line in the path is arch-neutral. It may be an upstream defect x86_64 also has and never trips. Record as "a cygheap defect observed on ARM64, arch-differential unknown", NOT "an ARM64 defect".
- **Method rules (binding):** non-match is never absence (open the file); measure what the compiler/linker emits (disassemble/DWARF, don't assume); echo-to-transcript is not persistence (redirect to file in same command); distinguish MEASURED/DERIVED/PRESUMED; never write x18; LSE atomics unavailable; read ImageBase from PE header. Kill leads by measurement, not argument ("true of the code, not necessarily true of the data flowing through it").
- **Environment tooling:** objdump `/root/xc/inst/bin/aarch64-pc-cygwin-objdump` (supports `--dwarf=info`, `-h`); g++ `/root/xc/inst/bin/aarch64-pc-cygwin-g++`. Cannot EXECUTE aarch64 binaries in WSL — measure via compile/disasm/DWARF/static_assert only. Built objects with DWARF live under `/root/xc/w-link/bld/winsup/cygwin/`. Do NOT touch `/root/xc/inst`, `/root/xc/runtime`, `/root/xc/bld`, `/root/xc/w-autoload`, `/root/xc/w-gendef`, or the Windows worktree. This session's tree is `/root/xc/w-defects` (READ-ONLY; c63ab774 owns all edits).
- **PowerShell→WSL quoting gotchas (recurring):** inline `bash -c` with `$VAR` mangles; RELIABLE PATTERN: write a `.sh`/`.py` via `create` tool, then `wsl -d Ubuntu -- bash -c "sed -i 's/\r$//' /path/script; bash /path/script"` (strips CRLF the create tool inserts). PowerShell also splits inline `python3 -c` on commas and chokes on `<`, `{}`; put python in a `.py` file.
</technical_details>

<important_files>
- `/root/xc/w-defects/winsup/cygwin/mm/cygheap.cc` (READ-ONLY; the heart of the current bug)
  - `cygheap_dummy` @30-35 (8-byte mini_cygheap, `cygheap` starts pointing here). `cygheap_fixup_in_child` @85-127 (chain walk @113 = fork fault site). `_csbrk` @326-357. `_cmalloc` @365-402 (the ONLY `cygheap->chain` writer @398; `rvc->prev = cygheap->chain` @397). `_cfree` @404-413 (freelist via union@0). `creturn` @442-459 (advances cygheap_max). allocator wrappers `cmalloc`/`ccalloc`/`cstrdup` @462-577. `cygheap_init` @288-313, `setup_cygheap` @318-324. `init_installation_root` @161-273. `cygheap_user::set_name` @614-637 (username cstrdup @628). `init_tls_list` @640-650 (ccalloc @648).
- `/root/xc/w-defects/winsup/cygwin/local_includes/cygheap.h` (READ-ONLY)
  - `_cmalloc_entry` struct @15-24 (union@0, prev@8, data@16). `cygheap_locale` @288-291 (single mbtowc_p). `mini_cygheap` @484-487. `init_cygheap : public mini_cygheap` @499-541 (chain@504, buckets@505, installation buffers, ... fdtab@524, sigs@528, threadlist@531, hooks@537).
- `/root/xc/w-defects/winsup/cygwin/uinfo.cc` (READ-ONLY)
  - `cygheap_user::init` @39-111 (username VLA @56, set_name @58, sec_user_nih @90 — no cygheap alloc). `cygheap_pwdgrp::init` @585-604 (no allocation).
- `/root/xc/w-defects/winsup/cygwin/dcrt0.cc` (READ-ONLY)
  - `dll_crt0_0` region: `do_global_ctors` @748 (BEFORE), `setup_cygheap()` @753, `memory_init()` @754, child path handle_fork @762. `dll_crt0_1` @813.
- `/root/xc/w-defects/winsup/cygwin/fork.cc` (READ-ONLY)
  - `frok::child` @135-203. `frok::parent` window: `__malloc_lock`/`cygheap->lock` @331-332, `refresh_cygheap` @338, `setup_forkables` @341, CreateProcessW @366, fdtab fixup @392-394, `ch.sync` @410. `child_copy` @731-782 (bare ReadProcessMemory).
- `/root/xc/w-defects/winsup/cygwin/local_includes/memory_layout.h` (READ-ONLY)
  - CYGHEAP_STORAGE_LOW=0x800000000 @39, INITIAL=0x800300000 @40, HIGH=0xa00000000 @41. CYGWIN_DLL_ADDRESS=0x180040000 @17.
- `/root/xc/w-defects/winsup/cygwin/local_includes/dll_init.h` (READ-ONLY)
  - `setup_forkables` inline @149-160 (gated on forkables_supported @84 = filesystem property). `buffered_shortname` @123 (static buffer).
- `/root/xc/w-defects/winsup/cygwin/forkable.cc` (READ-ONLY)
  - `forkable_ntnamesize` @465 with cmalloc @540 + the load-bearing comment @539 "allocate here, to avoid cygheap size changes during fork" (hoisted to DLL-load time). `request_forkables` @937, `release_forkables` @961.
- `/root/xc/w-link/bld/winsup/cygwin/mm/cygheap.o` (READ-ONLY build artifact)
  - Carries full DWARF; source of the MEASURED sizeof/offsetof facts. Use `aarch64-pc-cygwin-objdump --dwarf=info`.
- Session checkpoints dir: `C:\Users\crutkasLocal\.copilot\session-state\57224227-53ba-4c06-95b3-0ae9d9058bd5\checkpoints\` — index.md lists 001-007; a checkpoint 008 for the chain-init/clobber audit is NOT yet written.
</important_files>

<next_steps>
Immediate (the audit was mid-flight when compaction was requested — these were about to happen):
1. **Report the chain-clobber findings to BOTH sessions** (`c63ab774-a023-4e57-9bc4-53f727507ada` and `2b2e50a5-63c5-49f9-8b89-d825396b5ff9`). Key content to convey (all MEASURED unless noted):
   - Full init_cygheap offset map; NO header field sits at/near +8 except `chain` itself; `chain` has exactly ONE source writer (cygheap.cc:398) which only ever stores in-cygheap `_csbrk` results.
   - Therefore an mmap-arena value in a `prev` field cannot originate from the allocator — it requires a **stray non-allocator write to address `cygheap+8` (0x800000008)**, OR `cygheap->chain` already held a stray mmap value when the post-username entry was allocated.
   - `init_installation_root` writes only high buffers (≥288) and its registry block is `#ifndef __MSYS__` (excluded); `pg.init()`/init_pwd/init_grp do NOT allocate and do NOT mmap; `sec_user_nih` does not allocate from cygheap. So between the username cstrdup and the next allocation, none of these write near cygheap+8 — which SHARPENS the puzzle: the clobber source is not an obvious write in that window.
   - TEMPORAL TENSION worth raising: the wild values are mmap-arena addresses, but the mmap arena is created by `VirtualAlloc(NULL,...)` in memory_init/user_heap.init which run AFTER setup_cygheap. So the mmap value can't exist at username-allocation time — implying the clobber into that entry's `prev` (or into `cygheap->chain`) happens LATER (after memory_init), even though the entry was allocated during setup_cygheap. Suggest c63ab774's dynamic bisection also sample `cygheap->chain` after memory_init / after user_heap.init.
   - Keep the framing: "cygheap defect observed on ARM64, arch-differential unknown."
2. **Update todo `cygheap-chain-init-audit` to done** after reporting.
3. **Write checkpoint 008** (e.g. "Cygheap chain-head clobber audit") and add it to index.md (rename to 008-*.md; index currently ends at 007).

Possible follow-on static work (if coordinator/c63ab774 requests): enumerate every code path that stores an mmap-arena-derived pointer (VirtualAlloc(NULL)/MapViewOfFile/NtMapViewOfSection results) and check whether any could write to a low cygheap offset via a mis-based pointer or bad index; examine `memory_init`, `user_heap.init` (mm/shared.cc:326), and `mmap`/`heap.cc` init for a stray store near cygheap base; consider whether a global/static pointer adjacent to something writes through a stale/mis-based `cygheap`-relative address. Also consider whether the orphaned-chain symptom could be a READ-side walk-past-end rather than a write-side clobber (re-derive: c63ab774 says entry is orphaned AND prev is wild, which points to write-side, but keep both open).

Blocked/awaiting: no new binding assignment beyond the chain-clobber enumeration c63ab774 already requested; continue coordinating with both sessions. Maintain all constraints: read-only, edit nothing, never claim a product PASS, non-match is never absence, measure (DWARF/disasm) don't assume, read ImageBase from header.
</next_steps>