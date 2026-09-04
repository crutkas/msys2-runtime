<overview>
This session is part of a multi-session coordinated programme to make the MSYS2 runtime (`msys-2.0.dll`) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). This session is the "defects" investigator (session `57224227`), working read-only under coordination from a chat session (`2b2e50a5`, "General Chat") and reporting findings to session `c63ab774` ("Link arm64 msys runtime dll") which owns the runtime tree and all edits. Prior turns closed four original runtime-ABI defects plus a critical TEB-read fix; the current focus has pivoted through several read-only audits, culminating in the **active task: a static audit of `_cygtls` layout and `__CYGTLS_PADSIZE__` for ARM64**, to explain a stack-reserve-dependent crash inside Cygwin startup (`crt0`/`dcrt0`) that c63ab774 is actively blocked on. All work is local compile/inspect/disassemble only; commits, pushes, PRs, CI, upstream contact, editing `.copilot\repos\`, and editing `autoload.cc` (owned by c63ab774) are forbidden.
</overview>

<history>
1. (Prior turns, pre-summary) Closed four runtime-ABI defects (gentls_offsets awk fix, 8 orphan cygwin.din exports, SEH handler name derivation, v0-v7 FP audit at measured zero) and a critical TEB `__getreent` fix (`mrs tpidr_el0` → `mov x18`). All verified. A binutils base-relocation investigation was RETRACTED (no defect; the "10/414 drop" was an ImageBase arithmetic error — actual ImageBase is 0x180040000 not 0x180000000).

2. **dll_info/func_info layout audit** (start of this session's visible history): Coordinator asked me to compare the C++ `dll_info`/`func_info` structs against the assembly emitting those blocks, to explain a crash (EXECUTE to `0xFFFFFFFF00000000`, from a 64-bit read at info-block +0x0C).
   - Dumped the shipped DLL's `.advapi32_info` block bytes at VMA 0x18024a1a0: `+0`=_std_dll_init (0x1800438b8, relocated ✓), `+8`=0 (handle), `+16`=0xffffffff (`.long -1` here), `+24`=dll_func_load (0x18004386c ✓), `+32`="advapi32.dll".
   - Scanned all 19 `.<dll>_info` blocks: 19/19 have correctly relocated load_state and init pointers (high32==0x1). Zero bad.
   - CONCLUSION: the `0xFFFFFFFF00000000` at +0x0C is a COINCIDENTAL artifact = upper32(handle=0) ++ lower32(here=`.long -1`). No correct aarch64 path reads +0x0C. Layout hypothesis DISPROVEN by measurement.
   - Attempted to report to sessions `2b2e50a5` and `c63ab774` — both returned "not found" (they were prior-turn IDs). Recorded in todo DB, cleaned scratch, called task_complete.

3. **Arch-conditional sweep** (new assignment via cross_session_message from 2b2e50a5): sweep winsup/cygwin for every place aarch64 falls into a 32-bit/x86 `#else` branch (the class behind the confirmed ctor/dtor `0xFFFFFFFF00000000` bug in `cygwin.sc.in`).
   - Swept sources, headers, AND linker scripts. Found: `cygwin.sc.in:27-38` ctor/dtor (the KNOWN reached bug), `cygwin.sc.in:82-87` `.xdata` placement (NEW but latent — MEASURED the DLL gets .xdata correctly via orphan placement, PE Exception Directory points at .pdata). All runtime `.cc`/`.h` conditionals have correct `#elif __aarch64__` branches. `pseudo-reloc.cc` case 64 guarded by `||defined(_WIN64)` — MEASURED `_WIN64` IS defined for aarch64 (from w32api fix) by preprocessing.
   - Reported to `2b2e50a5-63c5-49f9-8b89-d825396b5ff9` (chat) and `c63ab774-a023-4e57-9bc4-53f727507ada` (found live IDs via list_sessions_and_chats). Cleaned scratch, task_complete.

4. **Reply from c63ab774**: accepted both hardening items; noted a THIRD reached instance I missed — `scripts/mkimport` (`$cpu eq 'x86_64'` with legacy `jmp *$imp_sym` fallback, blocked building libmsys-2.0.a, fixed with aarch64 import thunk). Told me to widen sweep to `scripts/*` and `$cpu eq` Perl tests. Also gave live status: ctor fix landed, DllMain now completes, a rung-3 executable dies inside Cygwin startup with stack-reserve-dependent fault (2MB→STACK_OVERFLOW, 64MB→ACCESS_VIOLATION) pointing at `_cygtls`/`__CYGTLS_PADSIZE__`.

5. **Generator-script sweep + _cygtls assignment** (cross_session_messages from 2b2e50a5): (a) widen sweep to scripts/, Makefile.am, configure.ac, .m4, any `$cpu eq` string comparison; (b) NEW high-priority assignment — audit `_cygtls` layout and `__CYGTLS_PADSIZE__` for ARM64 (size/alignment vs pad, field ordering, __getreent stack arithmetic, 16-byte alignment, x86_64 differential). This is the hottest item; c63ab774 blocked on it now.
   - Swept scripts/: mkimport (fixed by c63ab774), gendef (`$is_x86_64`), gentls_offsets (mine, fixed).
   - Investigated gendef: source shows x86-only sigfe/setjmp/longjmp blocks, but MEASURED the shipped `sigfe.s` is genuine aarch64 (14162 lines, 1006 br/blr, 0 x86, uses `mov x16,x18` + `ldaxr/stlxr`) — the aarch64 gendef backend lives in the `w-gendef` session's copy, not my worktree. No unhandled defect.
   - **Began _cygtls audit (current, in progress):** MEASURED `sizeof(_cygtls)=5016`, alignof=8, sizeof(_local_storage)=2200, sizeof(_reent)=1440, `__CYGTLS_PADSIZE__=12800` (NOT arch-conditional). Struct fits with 7784 bytes headroom → pad-too-small hypothesis DISPROVEN. tlsoffsets is 59 lines (my awk fix works), offsets internally consistent (e.g. `initialized_p=5008`, `initialized=-7792=5008-12800`). Disassembled `_dll_crt0`: uses `mov x0,x18; ldr x0,[x0,#8]` (StackBase); `mov x1,#-12800; add x0,x0,x1` (correct PADSIZE arithmetic). Disassembled `init_thread`: `memset(cygtls,0,5016)` (exactly sizeof), stackptr setup correct. Was disassembling `create_new_main_thread_stack` (0x1800444c8) when compaction hit — this function switches to a fresh stack via `mov sp, x0` and is the current prime suspect for the reserve-dependent fault.
</history>

<work_done>
Files modified in `/root/xc/w-defects` (isolated worktree; ALL from PRIOR turns — NONE modified this session; this session is entirely read-only investigation):
1. `winsup/cygwin/scripts/gentls_offsets` — awk `.long`→`(.long|.word)` (verified: produces 59-line tlsoffsets).
2. `newlib/libc/ctype/ctype_.c` — `_ctype_` guard.
3. `winsup/cygwin/Makefile.am` — `-D__MSYS__` for msys_dll_init.
4. `newlib/libc/machine/aarch64/sys/fenv.h`, `newlib/libm/machine/aarch64/fenv.c` — fe*except.
5. `winsup/cygwin/cygwin.din` + `scripts/gendef` — X86_64_ONLY tags.
6. `winsup/cygwin/local_includes/exception.h` + `cygtls.h` — SEH `%c0` handler derivation.
7. `winsup/cygwin/autoload.cc` — COMMENT-ONLY v0-v7 audit note (c63ab774 owns this; comment to hand off; NOT edited this session).
8. `winsup/cygwin/include/cygwin/config.h` — TEB fix `mov %0, x18`.

Work completed this session:
- [x] dll_info/func_info layout audit — layout hypothesis DISPROVEN (19/19 info blocks correct); reported.
- [x] Arch-conditional sweep (sources/headers/linker scripts) — 1 known reached (ctor), 1 latent (.xdata), rest clean; reported to both sessions.
- [x] Generator-script sweep (scripts/*) — mkimport & gendef already owned/fixed by other sessions; no new unhandled instance.
- [ ] **_cygtls / __CYGTLS_PADSIZE__ audit — IN PROGRESS.** Pad-size and layout arithmetic MEASURED correct so far; crash NOT yet explained. Was disassembling `create_new_main_thread_stack` (the fresh-stack allocator, prime remaining suspect).

Todos DB (session db): item1-orphans, item2-gentls, item3-seh, item4-fpaudit, teb-getreent-fix, binutils-basereloc, dllinfo-layout, arch-cond-sweep, scripts-sweep all = done. cygtls-padsize-audit = in_progress.

IMPORTANT cleanup note: In a prior turn I accidentally `rm`'d tracked `ltmain.sh` and restored it via `git checkout`. Scratch scripts from THIS turn still need cleanup: `check-xdata.sh`, `sweep-arch-cond.sh`, `triage1-5.sh`, `measure-win64.sh`, `check-pdata-dir.sh`, `dump-info-block.sh`, `verify-info-addr.sh`, `scan-all-info.sh`, `sweep-scripts.sh`, `check-sigfe.sh`, `peek-sigfe.sh`, `measure-cygtls-size.sh`, `measure-cygtls-size2.sh`, `measure-x64-diff.sh`, `find-crt0.sh`, `disasm-crt0.sh`, `disasm-newstack.sh`, plus /tmp files (csz.cc, csz64.cc, cygtls_size.*, pr.i, etc.).
</work_done>

<technical_details>
- **_cygtls MEASURED facts (aarch64, LP64)**: `sizeof(_cygtls)=5016`, `alignof=8`, `sizeof(_local_storage)=2200`, `sizeof(_reent)=1440`. `__CYGTLS_PADSIZE__=12800` (config.h:31, NOT arch-conditional, shared with x86_64). Struct fits with 7784-byte headroom. **Pad-too-small hypothesis DISPROVEN.** Measured via template-instantiation-error trick: `template<unsigned long N> struct SizeIs; SizeIs<sizeof(_cygtls)> probe;` → compiler prints `SizeIs<5016>` in the error.
- **TLS offset scheme**: tlsoffsets pairs each field: negative offset (from StackBase, e.g. `_cygtls.initialized=-7792`) and positive `_p` offset (from `_my_tls`=StackBase-12800, e.g. `initialized_p=5008`). Relationship: `negative = positive - 12800`. All internally consistent and MEASURED correct. tlsoffsets = 59 lines (confirms gentls_offsets awk fix; broken version gave 2 lines).
- **__getreent / _my_tls arithmetic (MEASURED in disasm)**: `_dll_crt0` @VMA 0x180046c84 does `mov x0,x18; ldr x0,[x0,#8]` (StackBase=TEB+8), `mov x1,#-12800; add x0,x0,x1` → `_my_tls = StackBase - 12800`. Correct. Uses x18 (my TEB fix is live in the binary).
- **init_thread @0x1800459b0**: `memset(cygtls,0,5016)` — exactly sizeof(_cygtls), no overflow. Sets stackptr(off 4960)→cygtls+4968(stack field). Correct.
- **create_new_main_thread_stack @0x1800444c8**: called by `_dll_crt0`, returns a new stack top; `_dll_crt0` then does `mov sp, x0` (switches stacks). Uses GetModuleHandleA, reads PE headers (SizeOfStackReserve/Commit from OptionalHeader), VirtualAlloc x2 (reserve+commit), writes `stp x1,x20,[x18,#8]` (updates TEB StackBase/StackLimit at x18+8/+16). **This is the current prime suspect** for the reserve-dependent fault — was mid-disassembly when compaction hit. The stack-reserve-dependent failure (2MB→overflow, 64MB→AV) is consistent with wrong stack size/commit computation here, NOT with the (correct) PADSIZE arithmetic.
- **gendef aarch64 sigfe**: My worktree's `scripts/gendef` shows only x86 `$is_x86_64` blocks, but the SHIPPED `sigfe.s` (in w-link/bld) is genuine aarch64 (14162 lines, `mov x16,x18` TEB reads, `tls_addr` macros, `ldaxr/stlxr` locks, TLS offsets ~-7000 to -12000). The aarch64 gendef backend lives in the `w-gendef` session's copy. NOT a defect; not my file to fix.
- **Arch-conditional sweep results**: Only `cygwin.sc.in:27-38` ctor/dtor is a reached-harmful `#else` fallthrough (known, fixed by c63ab774). `.xdata` (sc.in:82-87) is latent (orphan placement saves it today; PE Exception Dir points at .pdata RVA 0x2e9000). All runtime .cc/.h have proper `#elif __aarch64__`. exceptions.cc:961/992 are x86-only EFlags-TF workarounds correctly excluded. asm.h ENTRY macros used only by x86_64/*.S. math/*.S are x87-only, not built for aarch64.
- **_WIN64 landmine**: `pseudo-reloc.cc` case 64 guarded `||defined(_WIN64)`; `_WIN64` comes from w32api `_cygwin.h` fix (`#if defined(__x86_64__)||defined(__aarch64__)`). If w32api reverts, TWO breakages: loud (object count 271→116) AND silent (64-bit pseudo-relocs drop to `default:` error). Coordinator wants a build-time assertion recommended to c63ab774.
- **Live session IDs**: `2b2e50a5-63c5-49f9-8b89-d825396b5ff9` (chat "General Chat"/"Arm64 vnext resume", coordinator), `c63ab774-a023-4e57-9bc4-53f727507ada` (owns runtime tree + all edits, actively debugging the rung-3 startup crash). Use send_session_message to report.
- **PowerShell→WSL quoting gotcha (recurring, bit me 3× this session)**: inline `wsl -d Ubuntu -- bash -c "...\$VAR..."` mangles/empties shell vars and `$F` refs. RELIABLE PATTERN: write script via `create` tool, then `wsl -d Ubuntu -- bash -c "sed -i 's/\r$//' /path/script.sh; bash /path/script.sh"` (the sed strips CRLF the create tool inserts). For simple commands, single-quote the bash -c body and avoid variables.
- **DLL section VMAs (shipped new-msys-2.0.dll)**: ImageBase 0x180040000. .text @0x180041000 (section-relative symbol offsets add to this base). .data @0x18021e000. .autoload_text @0x180218000. Key symbols: `_dll_crt0`@0x180046c84, `init_thread`@0x1800459b0, `create_new_main_thread_stack`@0x1800444c8, `dll_crt0_0`@0x18004828c(0x728c+base), `_std_dll_init`@0x1800438b8, `dll_func_load`@0x18004386c.
- **Compile recipe for aarch64 probes**: `GXX=/root/xc/inst/bin/aarch64-pc-cygwin-g++`; `INC="-I $W/winsup/cygwin/local_includes -I /root/xc/bld/winsup/cygwin -isystem $W/winsup/cygwin/include -isystem /root/xc/bld/newlib/targ-include -isystem $W/newlib/libc/include"`; flags `-U_FORTIFY_SOURCE -fno-rtti -fno-exceptions -DHAVE_CONFIG_H -mcmodel=small`. For cygtls.h probes: `#define __INSIDE_CYGWIN__ 1` then `#include "winsup.h"` then `#include "cygtls.h"`.
- **objdump**: `/root/xc/inst/bin/aarch64-pc-cygwin-objdump`. Cannot execute aarch64 binaries in this WSL environment — measure via compile/disasm/static_assert, never runtime.
</technical_details>

<important_files>
- `/root/xc/w-defects/winsup/cygwin/include/cygwin/config.h`
  - Defines `__CYGTLS_PADSIZE__ 12800` (line 31) and `__getreent()` (lines 36-57). Central to current audit. TEB fix is here (lines 41-52: `mov %0, x18; ret=*(char**)(__teb+8); return (ret - PADSIZE)`). PADSIZE is NOT arch-conditional.
- `/root/xc/w-defects/winsup/cygwin/local_includes/cygtls.h`
  - `struct _local_storage` @line 89, `class _cygtls` @line 167 (locals @offset 0), `#pragma pack(push,8)` @line 42. `_my_tls` macro @316-317 = `*((_cygtls*)(StackBase - PADSIZE))`. sizeof measured = 5016.
- `/root/xc/w-defects/winsup/cygwin/init.cc`
  - `dll_entry`/DllMain @line 73. DLL_PROCESS_ATTACH does `alloca(PADSIZE)`+`ZeroMemory`+`memcpy(_REENT,_GLOBAL_REENT,...)` (lines 92-94) then `dll_crt0_0()`. DllMain COMPLETES (per c63ab774); crash is later in crt0/dcrt0.
- `/root/xc/w-defects/winsup/cygwin/dcrt0.cc`
  - Contains `_dll_crt0`/`dll_crt0_1` startup path. Line 1046 has correct `#elif __aarch64__` stack-setup (`mov sp,%[ADDR]; mov x29,sp`). Line 1093 comment on PADSIZE stack reservation.
- `/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll` (READ-ONLY, the shipped crash target)
  - ImageBase 0x180040000. Disassembly source for all startup arithmetic. `create_new_main_thread_stack`@0x1800444c8 is the current suspect.
- `/root/xc/w-link/bld/winsup/cygwin/tlsoffsets` (READ-ONLY, generated)
  - 59 lines, confirms gentls_offsets fix. Field offsets consistent with sizeof=5016 and PADSIZE=12800.
- `/root/xc/w-defects/winsup/cygwin/scripts/gendef` (my worktree copy; aarch64 sigfe backend actually lives in w-gendef session's copy)
  - `$is_x86_64` @line 24; x86-only sigfe/setjmp/longjmp emission @101-490. Shipped sigfe.s is genuine aarch64 — not a defect.
- `/root/xc/w-defects/winsup/cygwin/cygwin.sc.in` (READ-ONLY re fixes; c63ab774 owns)
  - ctor/dtor `#ifdef __x86_64__/#else` @27-38 (the known bug). `.xdata` `#ifdef __x86_64__` @82-87 (latent). Recommended `||defined(__aarch64__)` on both to c63ab774.
</important_files>

<next_steps>
Current active task: explain the stack-reserve-dependent crash in Cygwin startup (`crt0`/`dcrt0`; 2MB→STACK_OVERFLOW, 64MB→ACCESS_VIOLATION) via the `_cygtls`/`__CYGTLS_PADSIZE__` audit. Report MEASURED vs DERIVED vs PRESUMED to sessions `2b2e50a5-63c5-49f9-8b89-d825396b5ff9` and `c63ab774-a023-4e57-9bc4-53f727507ada`. Read-only; edit nothing.

Findings so far (all MEASURED, to report): PADSIZE=12800 is correct (sizeof(_cygtls)=5016 fits, 7784 headroom); tlsoffsets consistent (59 lines); `_dll_crt0`/`init_thread` PADSIZE arithmetic correct in disassembly; uses x18 TEB. The pad-size/layout hypothesis is DISPROVEN. The crash is NOT the PADSIZE arithmetic.

Immediate next steps:
1. **Finish disassembling `create_new_main_thread_stack` (@0x1800444c8)** — was in progress. This function reads PE OptionalHeader (SizeOfStackReserve/SizeOfStackCommit), does two VirtualAlloc calls (reserve then commit), and writes the new StackBase/StackLimit to TEB (`stp x1,x20,[x18,#8]`). Determine whether the stack SIZE/COMMIT computation or the TEB update is wrong for ARM64 — this is the prime suspect for the reserve-dependent fault. Check the register math around 0x180044504-0x180044588 (the `and`/`neg`/`sub` sequence computing aligned stack bounds) and whether it correctly reads SizeOfStackReserve from the PE header.
2. Consider the 16-byte SP-alignment angle the coordinator raised: a misaligned SP faults on the next `stp` on AArch64. Check whether the new `sp` value (`mov sp,x0` in _dll_crt0 after create_new_main_thread_stack returns) is guaranteed 16-aligned. In create_new_main_thread_stack, note `sub x19,x19,#0x10` @0x1800445bc before the final `add x0,x0,x19` — verify the returned stack top is 16-aligned.
3. Do the x86_64 differential: compare the x86_64 `create_new_main_thread_stack`/`_dll_crt0` stack setup against aarch64 (source is shared; the asm blocks in dcrt0.cc differ per-arch at line 1046). No x86_64-cygwin g++ is available here, so x86_64 sizes/behavior are DERIVED.
4. Report to both live sessions via send_session_message.
5. Clean up scratch scripts (list in Work Done) from /root/xc/w-defects and /tmp.

Blockers/constraints: cannot execute aarch64 binaries (measure statically). Read-only everywhere; c63ab774 owns all edits. Never claim product PASS. Read ImageBase from header, never assume. Prove detectors can fire before reporting a zero. A non-match is never evidence of absence — open the file.
</next_steps>