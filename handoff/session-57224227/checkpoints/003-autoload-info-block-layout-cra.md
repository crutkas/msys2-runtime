<overview>
This session is part of a multi-session programme to make the MSYS2 runtime (msys-2.0.dll) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). Four original runtime-ABI defects were closed and verified in prior turns; a critical TEB-read defect was also fixed. Work then pivoted through a series of cross-session coordination messages: an FP-register (v0-v7) audit (closed at measured zero), a read-only binutils base-relocation investigation (now RETRACTED — no defect exists), and finally the current active task: a **read-only field-by-field comparison of the C++ `dll_info`/`func_info` structs against the assembly that emits those blocks in `autoload.cc`**, to explain a runtime crash (EXECUTE to `0xFFFFFFFF00000000`). All work is local compile/inspect/experimentation only; commits, pushes, PRs, CI, upstream contact, and editing `.copilot\repos\` or `autoload.cc` (owned by session c63ab774) are forbidden.
</overview>

<history>
1. (Prior context) Closed four runtime-ABI defects (gentls_offsets awk, 8 orphan cygwin.din exports, SEH handler name derivation, v0-v7 FP audit) and a critical TEB `__getreent` fix (`mrs tpidr_el0` → `mov x18`). All verified.

2. Cross-session message (2b2e50a5) reassigned me to a **binutils base-relocation source investigation**: find why `ld`/BFD emits PE base relocations for only "10 of 424" identical `IMAGE_REL_ARM64_ADDR64` relocations in `.autoload_text`.
   - Read `ld/pe-dll.c generate_reloc()` (line 1561): iterates per-relocation-SITE, not per-symbol; `case BITS_AND_SHIFT(64,0)` → DIR64 under `#ifdef pe_use_plus`; default emits ERROR not silent drop.
   - Read `bfd/coff-aarch64.c`: `arm64_reloc_howto_64` (line 254) has rightshift=0, size=8, bitsize=64, pc_relative=false → correctly hits case(64,0). Howto is correct.
   - Read the `ldexp_is_final_sym_absolute` filter (pe-dll.c:1684) — only skips symbols defined in `bfd_abs_section_ptr`; section symbols are NOT absolute, so not skipped.

3. **Empirical reproduction (key work this session):**
   - Built a hand-written minimal autoload repro (`repro-autoload.s`, 3 DLLs × 2 funcs) → 12 ADDR64 relocs in object; linked `-shared` → all 12 DIR64 base relocs emitted. NO drop.
   - Scaled to 40 DLLs × 5 funcs (400 relocs) → all 400 base relocs emitted. NO drop.
   - Compiled the REAL `autoload.cc` for aarch64 (two-stage: `g++ -S`, strip 213 `.if/.error/.endif` self-check triples, rewrite `.align 16`→`.align 4` [aarch64 GAS `.align N` = 2^N bytes]) → 543 ADDR64 relocs (218 → `.data_cygwin_nocopy`, 213 → `.<dll>_autoload_text`, rest to `.text`/`dll_func_load`/DWARF). Linked with 13 stub symbols → all allocatable base relocs emitted.
   - Linked real autoload.o with the **real linker script `cygwin.sc`** (merges `*(.*_autoload_text)` into one `.autoload_text` output section) + `--gc-sections` + `--image-base 0x180000000` → **426 DIR64 base relocs in autoload_text, all present.** Still NO drop.
   - Inspected the **shipped `new-msys-2.0.dll`**: measured `.autoload_text` at VMA 0x180218000, ImageBase 0x180040000. Computed (using WRONG assumed base 0x180000000) RVA 0x218000 → found only 48 relocs in that range → *appeared* to confirm a drop. **This was an image-base arithmetic error.**

4. **Cross-session message (2b2e50a5) RETRACTED the binutils defect** (arrived during step 3's final analysis):
   - The "missing base relocation" finding was an artifact of assuming ImageBase 0x180000000. The ACTUAL ImageBase is **0x180040000**, so `.autoload_text`'s true RVA is **0x1D8000** not 0x218000. Every lookup was displaced by exactly 0x40000.
   - Re-measured with the section table's own RVA: **424 absolute image-range qwords in `.autoload_text`, 424 with base relocations, 0 missing.** Image-wide all correct. `ld`/BFD is NOT at fault. No binutils defect.
   - Lesson: read ImageBase from the header, never assume it. My own dumped reloc pages actually started at 0x1D7000/0x1D8000 — corroborating 424/424; I had mismatched them against the wrong range.
   - **NEW ASSIGNMENT (current):** the `0xC0000005` crash in `dll_entry` is unexplained again. A vectored handler captured an EXECUTE to `0xFFFFFFFF00000000`, and a 64-bit read at offset **+0x0C** of the autoload info block yields exactly that value. Compare the C++ `dll_info` struct against the assembly that emits the block, field-by-field under LP64/natural alignment; find the divergence; then do the x86_64 differential. Read-only; don't edit `autoload.cc`. Report to 2b2e50a5 and c63ab774.

5. Began the layout audit (current work):
   - Read both structs and all emission macros in autoload.cc.
   - Computed `dll_info` emission layout (LoadDLLprime) vs C struct → MATCH (0/8/16/24/32).
   - Computed `func_info` emission: x86_64 = dll@0, decoration@8, **func_addr@12**, name@20 (unaligned quad, OK on x86); aarch64 = dll@0, decoration@8, **func_addr@16**, name@24 (matches C struct + static_asserts).
   - Analyzed `std_dll_init`/`retchain`/`dll_chain` two_addr_t path → self-consistent on both arches (x0=func, x1=dll->init).
   - Disassembled the real DLL: `dll_func_load` uses `str x0,[x19,#16]` (func_addr@16, correct), `ldr x0,[x0,#8]` (handle@8). Thunk uses `ldr x17,[x16]; ldr x17,[x17]; blr x17`. All aarch64 offsets internally consistent. Was mid-analysis of the info-block raw bytes when compaction hit.
</history>

<work_done>
Files modified in `/root/xc/w-defects` (isolated worktree; all from PRIOR turns, all verified — NONE modified this session):
1. `winsup/cygwin/scripts/gentls_offsets` — awk `.long`→`(.long|.word)`.
2. `newlib/libc/ctype/ctype_.c` — `_ctype_` guard.
3. `winsup/cygwin/Makefile.am` — `-D__MSYS__` for msys_dll_init.
4. `newlib/libc/machine/aarch64/sys/fenv.h`, `newlib/libm/machine/aarch64/fenv.c` — fe*except.
5. `winsup/cygwin/cygwin.din` + `scripts/gendef` — X86_64_ONLY tags.
6. `winsup/cygwin/local_includes/exception.h` + `cygtls.h` — SEH `%c0` handler derivation.
7. `winsup/cygwin/autoload.cc` — COMMENT-ONLY v0-v7 audit note (lines ~165-188). NOTE: c63ab774 owns this file; comment-only change to be handed off. NOT edited this session.
8. `winsup/cygwin/include/cygwin/config.h` — TEB fix `mov %0, x18`.

Scratch scripts created THIS session (in `/root/xc/w-defects`, need cleanup): `repro-autoload.s`, `repro-link.sh`, `repro-reloc-dump.sh`, `repro-decode.sh`, `gen-scaled.sh`, `link-scaled.sh`, `link-real-autoload.sh`, `link-real-autoload2.sh`, `link-with-stubs.sh`, `link-with-stubs2.sh`, `link-with-stubs3.sh`, `regen-undefs.sh`, `check-real-autoload-obj.sh`, `check-build-state.sh`, `find-link-inputs.sh`, `find-libs2.sh`, `definitive-variants.sh`, `repro-production-link.sh`, `inspect-real-dll.sh`, `autoload-reloc-coverage.sh`, `inspect-reloc-symbols.sh`, `compare-amd64.sh`, `disasm-real.sh`. Plus /tmp files (repro*, al*, autoload-real*, stubs*, *reloc*.txt).

Work completed:
- [x] Items 1-4 + TEB fix (prior turns) — done, verified
- [x] Binutils base-reloc investigation — CLOSED (retracted; no defect; 424/424 relocs correct once ImageBase read correctly)
- [ ] dll_info/func_info struct-vs-asm layout audit — IN PROGRESS (current task)

Todos DB: item1-orphans, item2-gentls, item3-seh, item4-fpaudit, teb-getreent-fix, binutils-basereloc all=done (binutils marked done with RETRACTED note); dllinfo-layout=in_progress.
</work_done>

<technical_details>
- **RETRACTED binutils finding**: The "10/414 base-reloc drop" was entirely an ImageBase arithmetic error. ACTUAL ImageBase = **0x180040000** (NOT the conventional 0x180000000). `.autoload_text` VMA 0x180218000 → true RVA **0x1D8000**. `.reloc` stores TRUE RVAs. Measured correctly: 424/424 autoload absolute qwords have base relocs. `ld`/BFD is correct. **Standing rule: READ ImageBase from the PE header, never assume it.** A uniform offset error yields a self-consistent, plausible, entirely false result.

- **Current crash (MEASURED by sender)**: `0xC0000005` in `dll_entry`; vectored handler captured EXECUTE to `0xFFFFFFFF00000000`. A 64-bit read at info-block **+0x0C** yields exactly that value. In the emitted dll_info block, bytes 12-19 = (upper half of the offset-8 `.quad no_resolve_on_fork`, usually 0x00000000) ++ (`.long -1` at offset 16 = 0xFFFFFFFF) → little-endian `0xFFFFFFFF00000000`. This is the x86_64 func_info's func_addr offset (12), NOT any aarch64 offset. The sender's hypothesis: a reader treating an 8-byte field as 4-byte lands at +0x0C, loads it as a function pointer, and branches to it. **This byte observation survives the ImageBase retraction because it was read at a virtual address directly (no RVA arithmetic).**

- **Struct layouts (MEASURED from autoload.cc + LP64 natural alignment):**
  - `struct dll_info` (line 375): load_state@0 (UINT_PTR/8), handle@8 (HANDLE/8), here@16 (LONG/4), init@24 (fn ptr/8, after 4 pad), name@32 (WCHAR[]). **Emission (LoadDLLprime, lines 92-110) MATCHES:** `.quad`@0, `.quad`@8, `.long -1`@16, `.align 8`(pad), `.quad init_also`@24, UTF-16 name@32.
  - `struct func_info` (line 384): dll@0, decoration@8 (LONG), func_addr@16 (UINT_PTR), name@24 (char[]). static_asserts (401-408) enforce 0/8/16/24.
  - **x86_64 func_info emission (lines 144-148): dll@0, decoration@8, func_addr@12 (unaligned .quad), name@20** — deliberately DIFFERENT from C struct; comment (397-400) claims "harmless only because C never reads those two fields."
  - **aarch64 func_info emission (lines 211-217): dll@0, decoration@8, pad@12-15 (two `.hword 0`), func_addr@16, name@24** — MATCHES C struct.

- **retchain/dll_chain path (MEASURED, self-consistent)**: `union retchain { struct {uintptr_t high; uintptr_t low;}; __uint128_t ll; }`. `ret.high`@byte0, `ret.low`@byte8. AAPCS64 returns 16-byte composite in x0(bytes0-7=high=func), x1(bytes8-15=low=dll->init). aarch64 `dll_chain` (362-366): `mov x30,x0` (func), `br x1` (dll->init). x86_64 equivalent identical semantics. No divergence here.

- **Real DLL disassembly (MEASURED, no RVA assumptions)**: `dll_func_load` at 0x18004386c: `ldr x0,[x19]` (dll@0), `ldr x0,[x0,#8]` (handle@8), `add x1,x19,#0x18` (name@24), `str x0,[x19,#16]` (func_addr@16). Thunk (CheckTokenMembership@0x180218000): `ldr x16,[+0x40]; br x16` then stub `stp`s, `adr x16,[+0x30]; ldr x17,[x16]; ldr x17,[x17]; blr x17`. The `3f` slot at +0x40 holds `0x180218008` (address of `1b`, correctly relocated). The `2f` slot at +0x30 holds `0x8024a1a0`+`0x00000001` = `0x0000000180... _info` (correct). All aarch64 offsets correct and self-consistent.

- **KEY OPEN REASONING**: On aarch64, struct = emission = static_asserts = disassembly, all consistent. Nothing on the aarch64 path reads offset +0x0C. Yet the crash value is precisely the x86_64 func_addr-at-12 offset. This suggests EITHER (a) some code path (possibly compiler-generated C, or a shared header, or the `dll_entry`/DllMain path) reads a field at +0x0C on aarch64 due to a struct mismatch NOT yet located, OR (b) an x86_64-layout assumption leaked into an aarch64 code path, OR (c) the fault is a red herring and the +0x0C coincidence is being over-fitted. Need to find what actually reads +0x0C at runtime — likely NOT in autoload.cc's own asm (which is clean) but in a consumer of these structs elsewhere, or in how `dll_entry`/`_std_dll_init` is first invoked. The x86_64 differential (does x86_64's layout ever get read by C, since both arches read the SAME struct?) is the sender's requested next comparison.

- **Compile recipe for real autoload.cc** (reusable): `g++ -U_FORTIFY_SOURCE -I $W/winsup/cygwin/local_includes -I /root/xc/bld/winsup/cygwin -isystem $W/winsup/cygwin/include -isystem /root/xc/bld/newlib/targ-include -isystem $W/newlib/libc/include -fno-rtti -fno-exceptions -fno-use-cxa-atexit -g -O2 -mcmodel=small -DHAVE_CONFIG_H -S ...` then strip `.if/.error/.endif` triples + `.align 16`→`.align 4`, then `as`. Undefined symbols when linking alone: 13 (GetLastError, GetProcAddress, LoadLibraryW, SetLastError, `_ZN6strace5prntfEjPKcS1_z`, `__aarch64_ldadd4_sync`, api_fatal, fegetenv, fesetenv, strace, wcpcpy, windows_system_directory, yield).

- **Production link recipe** (from Makefile:3236-3245): `g++ -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -e dll_entry $(DEF) -Wl,-whole-archive libdll.a -Wl,-no-whole-archive $(VERSION_OFILES) libm.a libc.a -lgcc -lkernel32 -lntdll`. Could NOT fully reproduce: `libgcc.a`, `libkernel32.a`, `libntdll.a` are NOT present in this environment.

- **PowerShell→WSL quoting gotcha (recurring)**: inline `wsl -d Ubuntu -- bash -c '...$VAR...'` mangles/empties shell vars. RELIABLE PATTERN: write script with `create`, then `wsl -d Ubuntu -- bash -c "sed -i 's/\r$//' /path/script.sh; bash /path/script.sh"`. The `sed` strips CRLF the Windows `create` tool inserts. Bit me repeatedly.

- **Ownership boundaries**: c63ab774 OWNS `autoload.cc` and the thunk mechanism — do NOT edit in any tree. `.copilot\repos\binutils-woarm64` is strictly READ-ONLY. My worktree `/root/xc/w-defects` is source-only (0 archives), never linked against contaminated `/root/xc/bld/newlib`.
</technical_details>

<important_files>
- `/root/xc/w-defects/winsup/cygwin/autoload.cc` (in worktree; READ-ONLY for me — c63ab774 owns it)
  - Central to current task. Contains BOTH the C++ structs and the assembly emitting the blocks.
  - `struct dll_info` line 375; `struct func_info` line 384; static_asserts 401-408.
  - LoadDLLprime (dll_info emission): x86_64 lines 71-85, aarch64 lines 92-110.
  - LoadDLLfuncEx3 (func_info emission): x86_64 lines 126-150, aarch64 lines 189-222.
  - dll_func_load/noload/dll_chain: x86_64 lines 242-302, aarch64 lines 304-367.
  - std_dll_init / retchain / two_addr_t / INIT_WRAPPER: lines 411-572.
  - My comment-only v0-v7 note: lines ~165-188.
- `/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll` (real shipped DLL, read-only)
  - The crash target. ImageBase 0x180040000; `.autoload_text` VMA 0x180218000 (RVA 0x1D8000). dll_func_load@0x18004386c, dll_chain@0x1800438b0, _std_dll_init@0x1800438b8.
- `/root/xc/w-link/bld/winsup/cygwin/cygwin.sc` (linker script, read-only)
  - Merges `*(.*_autoload_text)` → `.autoload_text` (lines 22-25); `.data_cygwin_nocopy` → `.data` (line 33); `.reloc` (65-68). Explains section merging.
- `/root/xc/w-link/bld/winsup/cygwin/Makefile` (read-only)
  - Production link recipe at lines 3230-3250; AM_CPPFLAGS around line with local_includes.
- `C:\Users\crutkasLocal\.copilot\repos\binutils-woarm64\ld\pe-dll.c` (READ-ONLY) — binutils investigation now CLOSED; generate_reloc at 1561, filter 1631-1755, pe_detail_list 257-375 (aarch64 entry 351-361: imagebase_reloc=2, secrel [8,11], section=13). No defect.
- `/root/xc/w-defects/disasm-real.sh` — most recent scratch; disassembles dll_func_load + a thunk from the real DLL.
</important_files>

<next_steps>
Current active task: explain the runtime crash (EXECUTE to 0xFFFFFFFF00000000, from a 64-bit read at info-block +0x0C) via a field-by-field struct-vs-asm layout audit. Report to 2b2e50a5 and c63ab774; read-only, do not edit autoload.cc anywhere.

Findings so far to REPORT (all MEASURED): On aarch64, `dll_info` and `func_info` struct definitions, the assembly emission, the static_asserts, and the real DLL disassembly are ALL mutually consistent (dll@0, decoration@8, func_addr@16, name@24; dll_info load_state@0, handle@8, here@16, init@24). Nothing in autoload.cc's own aarch64 asm reads +0x0C. The +0x0C value matches the x86_64 layout (func_addr@12), NOT aarch64.

Immediate next steps:
1. Find WHAT reads info-block +0x0C at runtime on aarch64 — it is NOT autoload.cc's own asm (proven clean). Candidates: (a) the `dll_entry`/DllMain first-call path that invokes `_std_dll_init`; (b) any OTHER consumer of `struct dll_info`/`func_info` outside autoload.cc (grep the tree for `->func_addr`, `->init`, `->handle`, `dll_info`, `func_info` usages); (c) a shared/global header defining a conflicting struct; (d) whether the FIRST autoloaded call in DllMain resolves before relocations/init are ready.
2. Do the x86_64 differential the sender asked for: since BOTH arches read the SAME C `struct func_info`/`dll_info`, and x86_64 EMITS a different layout (func_addr@12, name@20) that disagrees with the struct, determine whether any C code reading `func->func_addr` would be wrong on x86_64 too — i.e., is the x86_64 "harmless because C never reads those fields" claim actually true, and does the same reasoning hold on aarch64? The divergence the sender predicts is "a reader treating an 8-byte field as 4-byte lands at +0x0C."
3. Re-verify the +0x0C byte observation independently by reading the real DLL's `.<dll>_info` block bytes at a virtual address (no RVA arithmetic) — the `-t` symbol dump earlier only matched `.debug_info`; need to find the actual `.<dll>_info` data symbols (e.g. `.kernel32_info`) and dump their bytes with `objdump -s` addressed by VMA.
4. Report MEASURED vs DERIVED vs PRESUMED findings to sessions 2b2e50a5 and c63ab774 via send_session_message.
5. Clean up scratch scripts in /root/xc/w-defects and /tmp.

Constraints reminder: no commits/pushes/PRs/CI/upstream; `.copilot\repos\` and `autoload.cc` read-only; local build/test/execute permitted; read ImageBase from header never assume; never claim product PASS; prove detectors can fire before reporting a zero.
</next_steps>