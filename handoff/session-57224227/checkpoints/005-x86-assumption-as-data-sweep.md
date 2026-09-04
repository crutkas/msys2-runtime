<overview>
This session is the read-only "defects investigator" (session `57224227`) in a multi-session coordinated programme to make the MSYS2 runtime (`msys-2.0.dll`) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). The coordinator is chat session `2b2e50a5-63c5-49f9-8b89-d825396b5ff9` ("General Chat"/"Arm64 vnext resume"); the runtime-tree owner who makes ALL edits is session `c63ab774-a023-4e57-9bc4-53f727507ada` ("Link arm64 msys runtime dll"). This session does local compile/disassemble/inspect ONLY and reports MEASURED/DERIVED/PRESUMED findings to those two sessions. Absolute constraints: no commits/pushes/branches/tags/PRs/CI/upstream/contributor-contact; `.copilot\repos\` is strictly read-only; never edit `autoload.cc` or any file c63ab774 owns; work only in the isolated WSL worktree `/root/xc/w-defects`.
</overview>

<history>
1. (Carried from prior summary) Closed four original runtime-ABI defects + a TEB `__getreent` fix; a binutils base-relocation hunt was RETRACTED (ImageBase was 0x180040000, not 0x180000000); dll_info/func_info layout audit disproven; arch-conditional `#ifdef/#else` sweep bounded at (eventually) four instances; began `_cygtls`/`__CYGTLS_PADSIZE__` audit.

2. Completed the `_cygtls`/PADSIZE audit (this session's opening work):
   - MEASURED sizeof(_cygtls)=5016, align=8, PADSIZE=12800 (not arch-conditional) → fits with 7784 headroom; overflow hypothesis DISPROVEN.
   - Disassembled `create_new_main_thread_stack` @0x1800444c8: the `stp x1,x20,[x18,#8]` writes new StackBase/StackLimit to TEB — correct.
   - Reported the exoneration + a widened build-system sweep (scripts/*, Makefile.am, configure.ac, *.m4, `$cpu eq` string tests) to both sessions. Sweep found mkimport (fixed by c63ab774) and gendef (aarch64 backend in w-gendef) as the only script-level instances; Makefile.am symmetric; no fifth instance.

3. Coordinator reassigned: statically analyze `create_new_main_thread_stack` (guard-page/commit-size hypothesis).
   - Disassembled the full function; mapped it byte-for-byte to source `create_posix_thread.cc:242-277`. Confirmed PE offsets ([x21,#96]=SizeOfStackReserve, [x21,#104]=SizeOfStackCommit), guardsize=3 pages (DEFAULT_GUARD_PAGE_COUNT=3), guard VirtualAlloc protect=0x104 (PAGE_READWRITE|PAGE_GUARD), return `allocbase+stacksize-16` (16-aligned). Function is BYTE-CORRECT for ARM64.
   - Found the DLL's `SizeOfStackCommit=0x1000` (4096) — committed region only 4096B while `_cygtls` needs [StackBase-12800, StackBase-7784); the `___chkstk` probe in `_cygtls::call` walks page-by-page correctly, but `init_thread`'s `memset(_my_tls,0,5016)` writes into/below the guard band → guard-fault whose resolution (autogrow/overflow/AV) is reserve-dependent. Reported this as the hazard geometry, correctly noting it is NOT a defect in `create_new_main_thread_stack` and that the x86_64 differential could not be run locally.

4. Coordinator: STAND DOWN — both `_cygtls` and `create_new_main_thread_stack` EXONERATED (correct negatives). The real bug was `import_address()` in `mm/malloc_wrapper.cc`: bare `*(uint16_t*)imp==0x25ff` opcode compare, no arch guard → NULL on aarch64 → unbounded malloc/calloc recursion. With it fixed, rung 3 (exit 77, 5/5) and rung 4 (malloc/printf, exit 42) PASS. NEW ASSIGNMENT: sweep for "x86 assumptions encoded as DATA" (magic opcode bytes, instruction decoders, hardcoded strides, register/frame-layout assumptions, x86-derived struct sizes), prioritizing signal and fork paths (rung 5 next).

5. Executed the opcode-data sweep (main body of this session):
   - Calibrated detector on the known defect (`malloc_wrapper.cc:53` `0x25ff` fired).
   - Found `path.cc:4859/4945` `find_fast_cwd_pointer` (x86 opcode scanner) — MEASURED NOT REACHED on aarch64 (guarded by `find_fast_cwd()` ARM64 check at path.cc:4972-4976).
   - Verified `hookapi.cc` is pure PE IAT/EAT data manipulation (clean); signal path (`exceptions.cc`) register macros/sigaltstack asm/unwind all arch-guarded; fork path (`fork.cc`) clean.
   - Found ONE diagnostic-only imperfection: `exceptions.cc:397-401` `stack_info::walk` reads call args off the stack (x86 convention) but only for `dumpstack()` crash-trace Args column — cosmetic on ARM64, never affects correctness.
   - Reported comprehensive results to both sessions; cleaned all scratch; called task_complete.

6. Final message from c63ab774 (informational, no new task requested of this session): confirmed both hardening items applied/relinked/regression-checked (cygwin.sc.in:82 `.xdata` explicit rule changed layout — `.xdata` now after `.pdata`, Exception Directory RVA 0x2d5000 size 0xbab8 matches .pdata, rung3 3/3 + rung4 still pass; pseudo-reloc.cc 3 guards now name `__aarch64__`). Confirmed my `_cygtls`/`create_new_main_thread_stack` negatives were correct and load-bearing. Reported new status: rung 5a signals PASS (989 sigfe trampolines executed first time); `fork()` fails in `cygheap_fixup_in_child(bool)` at `mm/cygheap.cc:116` walking `cygheap->chain` onto an unmapped `prev` pointer. Offered an OPTIONAL next target (static read of `child_copy` and what bounds `cygheap_max` in the child) and a lead it explicitly says NOT to build on (`x18=0` in faulting child thread, single sample, no control).
</history>

<work_done>
This session made ZERO file edits — it is entirely read-only investigation. All 11 fix files listed below are from PRIOR turns/sessions and remain intact in `/root/xc/w-defects`.

Work completed this session:
- [x] `_cygtls`/`__CYGTLS_PADSIZE__` audit — EXONERATED by measurement (confirmed correct by c63ab774).
- [x] `create_new_main_thread_stack` static audit — EXONERATED (byte-correct disassembly; confirmed correct by c63ab774).
- [x] Widened build-system sweep (scripts/*, Makefile.am, configure.ac, *.m4, `$cpu eq`) — no fifth arch-conditional instance.
- [x] "x86 assumption encoded as DATA" sweep — class bounded to 2 instruction-decoder sites (1 fixed, 1 not-reached); signal/fork paths arch-aware; 1 cosmetic imperfection flagged.
- [x] Reported all findings to sessions 2b2e50a5 and c63ab774.
- [x] Cleaned all scratch scripts; verified `ltmain.sh` (tracked) untouched and all 11 fix files intact.

Todos DB: 12 done / 12 total. Newest: `cygtls-padsize-audit`, `newstack-audit`, `opcode-data-sweep` all done.

Current state: The last c63ab774 message is informational and requested this compaction summary. It offered an OPTIONAL next target (child_copy/cygheap_max static read for the fork crash) but did not issue a binding assignment, and the coordinator (2b2e50a5) has not sent a new assignment. No task is currently in progress. Scratch is clean; nothing untested is pending.
</work_done>

<technical_details>
- **The real crash cause (for context):** `import_address()` in `mm/malloc_wrapper.cc:53` tested `*(uint16_t*)imp==0x25ff` (x86 `FF 25 = jmp *disp32(%rip)`) with NO arch guard. AArch64 import thunks are `adrp x16 / ldr x16, [x16,#:lo12:sym] / br x16`, never matching → `import_address` returns NULL → `use_internal` stays false → malloc/calloc recurse through the app's import thunk into themselves (unbounded). This was invisible to BOTH `#ifdef` sweeps and `$cpu eq` string sweeps because it is a bare literal opcode — a distinct defect class.
- **NEW DEFECT-CLASS CATALOGUE (three now):** (1) `#ifdef __x86_64__`/`#else` conditional fallthrough (bounded at 4: cygwin.sc.in ctor/dtor + OUTPUT_FORMAT, mkimport, gendef); (2) architecture STRING comparison `$cpu eq 'x86_64'` in generator scripts (mkimport, gendef); (3) x86 assumption encoded as DATA — a bare literal opcode/byte-pattern compared against a code pointer (import_address). Each class is invisible to the other classes' search instrument.
- **`_cygtls` MEASURED facts:** sizeof=5016, align=8, sizeof(_local_storage)=2200, sizeof(_reent)=1440. `__CYGTLS_PADSIZE__=12800` (config.h:31, NOT arch-conditional). Measured via template-instantiation-error trick (`template<unsigned long N> struct SizeIs; SizeIs<sizeof(_cygtls)> probe;` → compiler prints `SizeIs<5016>`). `_my_tls = StackBase - 12800`.
- **`create_new_main_thread_stack` (byte-correct, MEASURED):** matches source `create_posix_thread.cc:242-277`. PE offsets from NT header: SizeOfStackReserve@+96, SizeOfStackCommit@+104. `guardsize = DEFAULT_GUARD_PAGE_COUNT(=3) * page_size`. Guard VirtualAlloc: protect 0x104 = PAGE_READWRITE|PAGE_GUARD; commit VirtualAlloc: protect 4 = PAGE_READWRITE. TEB write `stp x1,x20,[x18,#8]` = StackBase(TEB+8)/StackLimit(TEB+16). Returns `allocbase+stacksize-16` (16-aligned since stacksize rounded to 64K allocation granularity). DLL's own `SizeOfStackCommit=0x1000`=4096.
- **`_dll_crt0` @0x180046c84 (MEASURED):** `bl create_new_main_thread_stack`; `mov sp,x0` (stack switch, x0=StackBase-16); later `mov x0,x18; ldr x0,[x0,#8]; mov x1,#-12800; add x0,x0,x1` = _my_tls; stores `_main_tls`; tail-calls `_cygtls::call(dll_crt0_1,NULL)` @0x180045b70. The aarch64 stack-switch block is `dcrt0.cc:1054-1061` (`mov sp,%[ADDR]; mov x29,sp`), guarded `#elif defined(__aarch64__)` with `#error` fallback (badly indented in source but correct).
- **`_cygtls::call` @0x180045b70 (MEASURED):** emits a `___chkstk` stack-clash probe touching each page in ≤4096B steps (`sub x10,...; str xzr,[x10,#4096]` ×3 then final), then `sub sp,sp,#12816` frame. The probe cooperates with guard-page autogrow — correct. `init_thread` @0x1800459b0 does `memset(cygtls,0,5016)` (exact sizeof); `_cygtls::call2` @0x180045ac0 receives x0=_my_tls and `bl init_thread`.
- **Opcode-data sweep results (MEASURED):** `path.cc find_fast_cwd_pointer` (4859 memchr 0xe8; 4945 `lock[0]!=0xe8`; memmem `\x48\x8b\x1d`,`\x48\x8d\x0d`,`\x4c\x8d\x25`,`\x4c\x8d\x2d`,`\xf0\x0f\xba\x35`; strides +5/+7/+9) is x86-64 only but NOT REACHED — `find_fast_cwd()` (path.cc:4972-4976) returns NULL when `wincap.host_machine()==IMAGE_FILE_MACHINE_ARM64` before it's called; `override_win32_cwd` falls back to `RtlSetCurrentDirectory_U` (path.cc:5036-5077). `hookapi.cc` (`hook_api`/`RedirectIAT`/`putmem`, `THUNK_FUNC_TYPE=ULONGLONG`) is pure PE IAT/EAT data manipulation — no opcode decode. `exceptions.cc` register macros `_CX_*`/`_MC_*` are `#ifdef __x86_64__`/`#elif __aarch64__`/`#error` (ARM64: Pc@0x108, Sp@0x100, Fp@0xf0; _MC_retReg=x0, _MC_uclinkReg=x19). sigaltstack aarch64 asm (exceptions.cc:1981-2019) is exemplary (reads operands first, `sub x9,#32` for 16B align, saves sp/x29, complete clobber list, NO x18 write, blr). EFlags-TF single-step (exceptions.cc:1006) x86-only `#ifdef`. `__unwind_single_frame` (exceptions.cc:354) uses RtlLookupFunctionEntry+RtlVirtualUnwind (SEH, correct on ARM64). `__tlsstack_t=uintptr_t` (cygtls.h:163), `TLS_STACK_SIZE=5` slots. fork.cc stack copy via TEB StackBase/StackLimit/DeallocationStack; SP read arch-guarded (fork.cc:668/670).
- **The one cosmetic imperfection:** `exceptions.cc:397-401` `stack_info::walk` sets `sf.Params[i]=p[i+1]` reading args off the stack (x86 args-on-stack). On AArch64 first 8 args are in x0-x7, so values are wrong, but `needargs` is set only for `dumpstack()` (exceptions.cc:453-462) crash-trace "Args" column — cosmetic, never affects execution. DERIVED from AAPCS64.
- **c63ab774's current fork failure (context for possible next task):** `fork()` fails in `cygheap_fixup_in_child(bool)` at `mm/cygheap.cc:116`, walking `cygheap->chain` onto an unmapped `prev` pointer after `child_copy`/`cygheap_init`. `CYGHEAP_STORAGE_*` in memory_layout.h are NOT arch-conditional (x22=0x800300000 confirms constants correct), so it's NOT the `#else` pattern. Open question: why does the child's cygheap chain contain a pointer to memory not mapped in the child, given the chain is partially valid first. c63ab774's unverified lead (do NOT build on): `x18=0` in the faulting child thread.
- **Live session IDs:** coordinator `2b2e50a5-63c5-49f9-8b89-d825396b5ff9`; runtime owner `c63ab774-a023-4e57-9bc4-53f727507ada`. Report via `send_session_message`.
- **PowerShell→WSL quoting gotcha (recurring):** inline `bash -c "...$VAR..."` mangles shell vars. RELIABLE PATTERN: write script via `create` tool, then `wsl -d Ubuntu -- bash -c "sed -i 's/\r$//' /path/script.sh; bash /path/script.sh"` (sed strips the CRLF that `create` inserts). PowerShell also chokes on `<=`, `<`, `{...}` in inline python `-c`; put python in a `.py` file instead.
- **Tools:** objdump `/root/xc/inst/bin/aarch64-pc-cygwin-objdump`; g++ `/root/xc/inst/bin/aarch64-pc-cygwin-g++`. Cannot EXECUTE aarch64 binaries in WSL — measure via compile/disasm/static_assert only. Shipped crash DLL: `/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll`, ImageBase 0x180040000. ALWAYS read ImageBase from the PE header, never assume.
</technical_details>

<important_files>
- `/root/xc/w-defects/winsup/cygwin/mm/malloc_wrapper.cc` (READ-ONLY; c63ab774 fixed it)
  - Home of the real crash bug. `import_address()` @49-64: line 53 `*(uint16_t*)imp==0x25ff` (x86 jmp decoder, +6/+2 strides). Line 318-323 uses it via `use_internal`. `caller_return_address` @39 uses `_sigbe`.
- `/root/xc/w-defects/winsup/cygwin/path.cc` (READ-ONLY)
  - `find_fast_cwd_pointer()` @4846 = x86-64 ntdll opcode scanner (NOT reached on aarch64). Guarded by `find_fast_cwd()` @4967, which returns NULL for ARM64 @4972-4976. `override_win32_cwd()` @4993 fallback @5036-5077.
- `/root/xc/w-defects/winsup/cygwin/create_posix_thread.cc` (READ-ONLY; c63ab774 owns)
  - `create_new_main_thread_stack()` @242-277 — the stack allocator; byte-verified correct. Source for the disasm mapping.
- `/root/xc/w-defects/winsup/cygwin/dcrt0.cc` (READ-ONLY)
  - `_dll_crt0()` @1027; aarch64 stack-switch asm @1054-1061 (`mov sp,%[ADDR]; mov x29,sp`, `#elif __aarch64__`/`#error`).
- `/root/xc/w-defects/winsup/cygwin/exceptions.cc` (READ-ONLY)
  - Signal path. Register macros @38-61; register dump @248-291; `__unwind_single_frame` @354; `stack_info::walk` @377 (cosmetic Params issue @397-401); EFlags-TF x86-only @992-1029; sigaltstack switch x86 @1943 / aarch64 @1981-2019; rip/pc @1859-1864.
- `/root/xc/w-defects/winsup/cygwin/hookapi.cc` (READ-ONLY)
  - Hook engine — verified clean PE-data manipulation. `putmem`/`RedirectIAT` @72-130, `hook_or_detect_cygwin` @333, `hook_api` @416.
- `/root/xc/w-defects/winsup/cygwin/fork.cc` (READ-ONLY)
  - Fork path. Stack copy via TEB @292-312; SP read arch-guarded @667-674. (c63ab774's current crash is downstream in `mm/cygheap.cc:116` `cygheap_fixup_in_child`.)
- `/root/xc/w-defects/winsup/cygwin/local_includes/cygtls.h` (READ-ONLY)
  - `TLS_STACK_SIZE 5` @31, `__tlsstack_t=uintptr_t` @163, `_cygtls` class @167, `retaddr()` @226, `_my_tls` macro @316-317.
- `/root/xc/w-defects/winsup/cygwin/include/cygwin/config.h` (has prior-turn TEB fix)
  - `__CYGTLS_PADSIZE__ 12800` @31; `__getreent()` @36-57 (TEB via `mov %0, x18`).
- The 11 prior-turn fix files (all intact, NONE edited this session): gentls_offsets, newlib ctype_.c, Makefile.am, aarch64 fenv.h/fenv.c, cygwin.din+gendef, exception.h+cygtls.h (SEH), autoload.cc (comment-only, c63ab774's), config.h (TEB).
</important_files>

<next_steps>
No binding assignment is currently pending. The last inbound message (from c63ab774) is informational and requested this summary. It OFFERED an optional next target that this session could pick up if the coordinator confirms:

- **Optional (offered by c63ab774, not yet a binding assignment):** Static read of `child_copy` and what bounds `cygheap_max` in the forked child, to explain why the child's `cygheap->chain` contains a pointer to memory not mapped in the child (fork crash in `cygheap_fixup_in_child` at `mm/cygheap.cc:116`). Would start by reading `mm/cygheap.cc` (`cygheap_fixup_in_child`, `child_copy`, `cygheap_init`, `cygheap_max`) and `fork.cc` `frok::child`/`frok::parent` for how cygheap bounds are computed/copied parent→child.
- **Explicitly DO NOT build on:** c63ab774's `x18=0` lead in the faulting child (single sample, no control; unverified whether GetThreadContext reports the platform-reserved x18 faithfully).
- **Standing hardening items already accepted/applied** (no further action needed): cygwin.sc.in:82 `.xdata`, pseudo-reloc.cc `_WIN64` — both applied by c63ab774.

Immediate next step: await the coordinator's (2b2e50a5) next assignment, OR if picking up the offered fork/cygheap target, begin a read-only static analysis of `mm/cygheap.cc` + `fork.cc` child-copy path and report MEASURED/DERIVED to both sessions. Maintain all constraints: read-only, edit nothing, never claim a product PASS, non-match is never absence (open the file), measure what the compiler/linker emits (disassemble, don't assume), read ImageBase from the header. Remember to reply to c63ab774 acknowledging its status update if continuing coordination.
</next_steps>