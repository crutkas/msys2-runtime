<overview>
This session is part of a multi-session programme to make the MSYS2 runtime (msys-2.0.dll) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). The original task was to close four known runtime-ABI defects; those were completed and verified. The work then pivoted, via cross-session coordination messages, first to fixing a critical TEB-read defect, then to answering an FP-register audit explicitly, and finally to the current active task: a **read-only source investigation of binutils** to find why the linker (`ld`/BFD) emits PE base relocations for only 10 of 424 identical `IMAGE_REL_ARM64_ADDR64` relocations in the autoload sections. All work is local compile/inspect/experimentation only; commits, pushes, PRs, CI, upstream contact, and editing `.copilot\repos\` are forbidden. Binding method rules: distinguish MEASURED/DERIVED/PRESUMED, a non-match is never evidence of absence (open the file), prove detectors can fire before reporting zero, never claim a product PASS.
</overview>

<history>
1. (Prior context, summarized) The user asked to close FOUR known runtime-ABI defects in an isolated WSL tree reusing the `/root/xc/inst` aarch64-pc-cygwin cross-toolchain (GCC 15.0.1, binutils 2.44.50). All four were completed and verified:
   - Item 2 (gentls_offsets): widened awk `.long`→`(.long|.word)` for aarch64; produces correct 59-line tlsoffsets.
   - Item 1 (8 orphan cygwin.din exports): fixed `_ctype_`, `msys_dll_init`, `feenableexcept/fedisableexcept/fegetexcept`; excluded `fegetprec/fesetprec/_fe_nomask_env/__alloca` via new `X86_64_ONLY` din tag.
   - Item 3 (SEH handler name): replaced hard-coded P19 mangled name with compiler-derived `%c0` + `"i"(&exception::handle/myfault)`.
   - Item 4 (v0-v7 FP audit): started but not finished at that point.

2. This session began mid-Item-3/Item-4. I completed Item 3's cygtls.h fix:
   - Proved via isolated probe (`seh-myfault-probe.cc`) that `asm goto` with `"i"(&exception::myfault)` + `%c0` derives P19 (default tag) / P25 (`_DISPATCHER_CONTEXT_ARM64` tag) correctly.
   - Discovered `myfault` is private and `__try` is used in 41 TUs where `class exception` isn't in scope → made `myfault`/`handle` public in exception.h, added `#include "exception.h"` to cygtls.h.
   - Verified flock.cc (EXIT=0, P19) and exceptions.cc (EXIT=0, no redefinition, both names P19).

3. Completed Item 4 (v0-v7 FP audit):
   - Enumerated 215 autoloaded functions (measured; task estimated ~192).
   - Built a 73MB corpus from 1635 w32api headers; ran a Python single-pass audit. Result: 212 clean, 3 NODECL, 0 FP candidates.
   - Resolved the 3 NODECL by opening files: NtMapViewOfSectionEx, RtlSetProcessPlaceholderCompatibilityMode, SystemFunction036(=RtlGenRandom) — all integer/pointer/handle, no FP.
   - Proved detector could fire (corpus has 7210 float/double lines like `_FSinh(float,float)`).
   - Conclusion: ZERO exposure → did NOT modify the stub; added documentary comment.
   - Persisted `ITEM4-fp-audit-result.txt`, `ITEM4-autoload-funcs.txt`, `SESSION-REPORT.txt`.

4. First cross-session message (from 2b2e50a5, "General Chat") — URGENT TEB fix:
   - Warned `/root/xc/bld/newlib` archives are contaminated with the stale `mrs tpidr_el0` TEB read (wrong on Windows ARM64; returns 0; faults at address 8). Corrected binding rule: read TEB from x18 directly (`mov`), never `tpidr_el0`, never write x18.
   - I MEASURED that I authored zero `tpidr_el0`; the defect was in inherited `config.h:48` (`__getreent`).
   - Applied `mov %0, x18` fix mirroring the reference at `/root/xc/w-link/runtime/.../config.h`.
   - PROVEN by encoding scan: probe compiles EXIT=0, disasm shows `mov x0, x18` (aa1203e0), byte-scan for stale `D0 3B D5` = 0 occurrences. My tree is source-only (0 archives).
   - Replied to sender with full measured Item 4 answer + TEB proof; asked about autoload.cc ownership boundary.

5. Called task_complete (twice — once after Item 4, once after the TEB-fix turn when reminded).

6. Second cross-session message — ownership + reassignment #1:
   - EXPLICIT: session `c63ab774` OWNS `autoload.cc` and the thunk mechanism. DO NOT EDIT IT. Hand my comment-only change to c63ab774.
   - Praised the FP audit and TEB verification standard.
   - Asked me to tighten the FP-audit comment with provenance (what measured, when, which corpus).
   - NEW TASK: generate x86_64 vs AArch64 autoload thunk constructs (generate & inspect, do NOT edit) — does x86_64 use PC-relative where AArch64 uses absolute `.quad`? Context: c63ab774 measured 414 of 424 absolute quads in `.autoload_text` carry NO base relocation; image ASLR-relocated (base 0x7FFDAD3D0000 vs preferred 0x180000000); slot holds 0x0000000180218008 (correct `1b` address, never relocated). Hypothesis: numeric local label `1b` resolved at assembly time so no reloc, while external `.<dll>_info` symbol emits one → predicts surviving 10.

7. I tightened the FP-audit comment (added MEASURED date/corpus/re-run instructions), then began the x86_64/AArch64 differential:
   - No x86_64 cygwin/mingw compiler available (host has native gcc 13.3, as 2.42, aarch64 cross only).
   - Read the x86_64 thunk source (autoload.cc:125-150) vs AArch64 (151-200): BOTH store absolute `.quad` payloads; the PC-relative part is only how the slot is reached. Measured this directly.
   - Compiled the real autoload.cc for aarch64 (with diagnostic-only transforms: strip `.if/.error/.endif` self-checks that fail in standalone assembly; change `.align 16`→`.align 4` because aarch64 GAS `.align` is 2^n and 2^16 is nonrepresentable) → assembled EXIT=0, 20 autoload_text sections.
   - Dumped relocations: **426 IMAGE_REL_ARM64_ADDR64** in autoload_text sections; 213 target `.data_cygwin_nocopy`, 213 target various `.<dll>_autoload_text` sections.

8. Third cross-session message (arrived mid-work) — STOP differential + reassignment #2:
   - Differential already done by a sibling: BOTH arches use identical construct, assembler correct on both. Defect localised to LINKER base-reloc emission.
   - NEW ASSIGNMENT (current): READ the ARM64 PE base-relocation emission path in binutils source and find the discriminator. Repo `crutkas/binutils-woarm64`, READ-ONLY clone at `C:\Users\crutkasLocal\.copilot\repos\binutils-woarm64`. Question: WHY emit base relocs for 10 of 424 identical ADDR64 and drop 414? Hypothesis to test first: does the code key on unique target SYMBOL vs relocation SITE (~10 distinct per-DLL `_info` symbols would explain it)? Compare coff/pe-aarch64 vs AMD64 path. c63ab774 attacks empirically from the image; I attack from source. Report to 2b2e50a5 and c63ab774; do not edit its tree or autoload.cc.

9. I began the binutils investigation (current active work):
   - Verified clone exists.
   - Located `bfd/coff-aarch64.c` and `ld/pe-dll.c`.
   - Found `generate_reloc()` in pe-dll.c:1561 — the base-reloc generator, called at line 3837.
   - Analyzed the per-reloc filter (lines 1631-1752): it iterates per-relocation-SITE, not per-symbol.
   - Found the `switch BITS_AND_SHIFT(bitsize, rightshift)` at line 1704; `case (64,0)` under `#ifdef pe_use_plus` → IMAGE_REL_BASED_DIR64. `default` (line 1747) emits an ERROR (`%X`), not silent drop.
   - Confirmed `pep-dll.c:61 #define pe_use_plus` then includes pe-dll.c → for ARM64 PE+, the 64-bit case IS active.
   - Decoded `arm64_reloc_howto_64` (coff-aarch64.c:254-256): `HOW(type, right=0, size=8, bits=64, pcrel=false,...)` → bitsize=64, rightshift=0, pc_relative=false → correctly hits case (64,0). Howto is correct.
   - Was reading `ldexp_is_final_sym_absolute()` (ldexp.c:1748) — the line-1684 filter that could `continue`/skip a reloc if the target symbol is classified absolute. This is the leading candidate for the discriminator.
</history>

<work_done>
Files modified in `/root/xc/w-defects` (isolated worktree; all prior items verified):
1. `winsup/cygwin/scripts/gentls_offsets` — awk `.long`→`(.long|.word)` (both matchers). VERIFIED 59-line output.
2. `newlib/libc/ctype/ctype_.c` (~line 98) — guard `#if defined(__x86_64__) || defined(__aarch64__)`. VERIFIED emits `_ctype_`.
3. `winsup/cygwin/Makefile.am` (~line 21-27) — `-D__MSYS__` in TARGET_AARCH64. VERIFIED emits `msys_dll_init`.
4. `newlib/libc/machine/aarch64/sys/fenv.h` (~lines 89-120) — prototypes-before-bodies + `__fenv_static __inline` for feenableexcept/fedisableexcept/fegetexcept. VERIFIED.
5. `newlib/libm/machine/aarch64/fenv.c` — extern inline decls. VERIFIED 11→14 externals.
6. `winsup/cygwin/cygwin.din` — X86_64_ONLY tags on lines 18, 138, 535, 545. VERIFIED.
7. `winsup/cygwin/scripts/gendef` (~line 41-47) — X86_64_ONLY tag handler. VERIFIED both arches.
8. `winsup/cygwin/local_includes/exception.h` — made myfault/handle public (lines ~25-38), `%c0` + `"i"(&exception::handle)` in ctor, fixed false comment (13-18). VERIFIED.
9. `winsup/cygwin/local_includes/cygtls.h` — `_CYG_SEH_MYFAULT_SYM`="%c0" + `_CYG_SEH_MYFAULT_INPUT`="i"(&exception::myfault) for aarch64 (lines ~367-406), `#include "exception.h"` (line 367), fixed false comment (365). VERIFIED flock.cc + exceptions.cc EXIT=0.
10. `winsup/cygwin/autoload.cc` — COMMENT-ONLY documentary note about v0-v7 audit (lines ~165-184), now with MEASURED provenance (date 2026-09-03, w32api v12.0.0 corpus, re-run instructions). NO v0-v7 save added. NOTE: coordinator says c63ab774 owns this file; my change is comment-only and is to be handed to c63ab774.
11. `winsup/cygwin/include/cygwin/config.h` (lines ~41-52) — TEB fix: `mrs %0, tpidr_el0` → `mov %0, x18`, corrected comment. VERIFIED byte-scan D0 3B D5 = 0.

Persisted artifacts in `/root/xc/w-defects`: `ITEM4-fp-audit-result.txt` (215 rows), `ITEM4-autoload-funcs.txt` (215), `SESSION-REPORT.txt`.

Scratch files created THIS session that need cleanup: `probe-tc.sh`, `reloc-autoload.sh`, `reloc2.sh`, `reloc3.sh`, `reloc4.sh` (in /root/xc/w-defects), plus /tmp files (al.s, al2.s, al3.s, al.o, al-reloc.txt, al-aut-reloc.txt, getreent-probe.*, etc.). Earlier-session scratch (seh-myfault-probe.*, scan-tpidr.sh, scan-getreent.sh) already removed.

Work completed:
- [x] Items 1-4 (all four original defects) — done and verified
- [x] Critical TEB `__getreent` fix — done, proven by encoding scan
- [x] FP-audit comment provenance tightening — done
- [x] x86_64/AArch64 thunk differential — done (stopped per coordinator; both use identical absolute ADDR64 construct; 426 relocs measured)
- [ ] Binutils base-reloc discriminator investigation — IN PROGRESS (current task)

Todos table (session DB): item1-orphans, item2-gentls, item3-seh, item4-fpaudit, teb-getreent-fix all=done; binutils-basereloc=in_progress.
</work_done>

<technical_details>
- **Isolated tree**: `/root/xc/w-defects` (detached HEAD off d890a845e). Source-only, 0 `.a` archives, no `bld/` dir — never linked against contaminated `/root/xc/bld/newlib`. This is a MEASURED clean statement.

- **PowerShell→WSL quoting gotcha (CRITICAL, recurring)**: Inline `wsl -d Ubuntu -- bash -c '...$VAR...'` mangles/empties shell variables (e.g. `$f`, `$c`, `$D` expand empty; loops run once). RELIABLE PATTERN: write bash to a file with `create`, then `wsl -d Ubuntu -- bash -c "sed -i 's/\r$//' /path/script.sh; bash /path/script.sh"`. The `sed` strips CRLF that the Windows `create` tool inserts. This bit me ~4 times this session.

- **TEB defect (MEASURED)**: config.h `__getreent` used `mrs %0, tpidr_el0`. On Windows ARM64, tpidr_el0 is the ELF/Linux TLS register and is 0 for user-mode threads → `ldr [x+8]` faults at address 8. Correct: `mov %0, x18` (x18 = Windows platform register holding TEB; READ ONLY, never write). Reference fix at `/root/xc/w-link/runtime/winsup/cygwin/include/cygwin/config.h:41-52`. Because `__getreent` is inlined, already-compiled archives are frozen-defective; a source fix does NOT clean binaries — must rebuild + byte-scan for `D0 3B D5` (the invariant bytes of `mrs Xt,tpidr_el0` = 0xD53BD040|Rt).

- **Encoding scan method**: `mov x0,x18` = 0xAA1203E0; `mrs Xt,tpidr_el0` invariant bytes = `D0 3B D5`. Prove propagation by byte-scanning the OBJECT, not reading source.

- **Autoload thunk construct (MEASURED, both arches use absolute payload)**:
  - x86_64 (autoload.cc:125-150): `movq 3f(%rip),%rax; jmp *%rax` — RIP-relative to REACH slot; slot content `.quad 1b` and `.quad .<dll>_info` are ABSOLUTE.
  - aarch64 (autoload.cc:151-200): `ldr x16, 3f` (PC-rel literal) + `adr x16,2f; ldr x17,[x16]`; slot content `.quad 1b` / `.quad .<dll>_info` ABSOLUTE. Stub saves x0-x8, x30; NOT v0-v7.
  - Object-level: x86_64 emits IMAGE_REL_AMD64_ADDR64, aarch64 emits IMAGE_REL_ARM64_ADDR64, two per thunk, structurally identical. Assembler CORRECT on both.

- **My autoload.cc reloc measurement (MEASURED)**: real autoload.cc compiled for aarch64 → 426 IMAGE_REL_ARM64_ADDR64 in autoload_text sections; 213 → `.data_cygwin_nocopy` (the `_info` quad), 213 → per-DLL `_autoload_text` (the `1b` func_addr quad). Diagnostic transforms needed to assemble standalone: strip `.if (2b-NAME)%8 / .error / .endif` triples (cross-section subtraction nonconstant in standalone), and `.align 16`→`.align 4` (aarch64 GAS `.align` is 2^n; `.align 16`=2^16 nonrepresentable for section). These are DIAGNOSTIC-ONLY, not source edits.

- **aarch64 GAS `.align` semantics**: `.align N` means 2^N bytes on aarch64 (unlike x86 where it's N bytes). This is a known ARM64 differential the coordinator flagged. The source `.align 16` in autoload.cc may itself be latently wrong on aarch64 (would mean 2^16) — worth noting but NOT my area (c63ab774 owns autoload.cc).

- **binutils base-reloc path (investigation in progress)**:
  - `ld/pe-dll.c:generate_reloc()` (line 1561) is THE base-reloc generator, called from `pe_dll_generate_reloc_section` at line 3837.
  - It iterates per-relocation-SITE (`for i < nrelocs`, line 1631), NOT per-symbol → the "one-per-unique-symbol" hypothesis would be DISPROVEN if this is the operative path (needs confirming the split isn't upstream).
  - Filter gates that `continue`/skip a reloc: pc_relative (1638), undefined weak (1650), abs section/.eh_frame (1675), and **absolute symbol via `ldexp_is_final_sym_absolute(blhe)` (1684)** — leading candidate.
  - `switch BITS_AND_SHIFT(bitsize,rightshift)` (1704): `case(64,0)`→DIR64 under `#ifdef pe_use_plus`; `default`(1747) emits ERROR not silent drop.
  - `pep-dll.c:61 #define pe_use_plus` then includes pe-dll.c → ARM64 PE+ has 64-bit case active.
  - `coff-aarch64.c`: `HOW(type,right,size,bits,pcrel,left,ovf,func,mask)` macro (line 246). `arm64_reloc_howto_64` (line 254): right=0, size=8, bits=64, pcrel=false → correctly hits case(64,0). Howto is CORRECT.
  - `ldexp_is_final_sym_absolute` (ldexp.c:1748): returns true if `h->type==bfd_link_hash_defined && h->u.def.section==bfd_abs_section_ptr` (and not ldscript_def, or def->final_sec is abs). Was mid-read when compaction hit.

- **KEY OPEN REASONING**: Since generate_reloc iterates per-site and the howto is correct, all 426 SHOULD get DIR64 base relocs. The 10/414 split must come from either (a) the line-1684 absolute-symbol filter mis-classifying local section-symbol targets, (b) `bfd_wrapped_link_hash_lookup(sym->name)` returning NULL/unexpected for numeric-local-label-derived section symbols, or (c) an upstream difference in how section symbols vs external `_info` symbols reach generate_reloc. The coordinator's own hypothesis: local label `1b` resolved at assembly time (no reloc surviving to linker) while external `.<dll>_info` emits one — but my MEASUREMENT shows BOTH 213+213=426 relocs DO exist in the object, so the assembler is NOT dropping the `1b` ones; the drop is in the linker. This partially contradicts the coordinator's assembly-time hypothesis and needs to be reported.

- **The unexplained `0xFFFFFFFF00000000` fault**: after TEB fix, fault moved to a branch to this value (32-bit all-ones in high half). c63ab774 disproved sentinel theory (slot holds correct 0x180218008, just unrelocated). My hypothesis (passed on): 32-bit truncation/sign-extension of patched func_addr or the `ldr x16,3f;br x16` slot. Coordinator says it remains genuinely unexplained; cheapest discriminator = fix relocations and re-observe (if fault moves to 0x180218008 they're distinct).
</technical_details>

<important_files>
- `C:\Users\crutkasLocal\.copilot\repos\binutils-woarm64\ld\pe-dll.c` (READ-ONLY)
   - Central to current task. `generate_reloc()` at line 1561 is the PE base-reloc generator. Filter at 1631-1752; absolute-symbol skip at 1684; BITS_AND_SHIFT switch at 1704; default-error at 1747; called at 3837.
- `C:\Users\crutkasLocal\.copilot\repos\binutils-woarm64\ld\pep-dll.c` (READ-ONLY)
   - Line 61 `#define pe_use_plus` then includes pe-dll.c — confirms 64-bit case active for ARM64.
- `C:\Users\crutkasLocal\.copilot\repos\binutils-woarm64\bfd\coff-aarch64.c` (READ-ONLY)
   - ARM64 PE reloc backend. HOW macro line 246; arm64_reloc_howto_64 lines 254-256 (bits=64,right=0,pcrel=false, CORRECT); howto lookup 419-425. Compare against `coff-x86_64.c` (AMD64 known-good path) next.
- `C:\Users\crutkasLocal\.copilot\repos\binutils-woarm64\ld\ldexp.c` (READ-ONLY)
   - `ldexp_is_final_sym_absolute` at line 1748 — the absolute-symbol test used by the line-1684 skip. Was mid-read.
- `/root/xc/w-defects/winsup/cygwin/autoload.cc` (in worktree)
   - x86_64 thunk 125-150, aarch64 thunk 151-200. My comment-only edit at ~165-184 (v0-v7 audit provenance). DO NOT edit further (c63ab774 owns it).
- `/root/xc/w-defects/winsup/cygwin/include/cygwin/config.h`
   - TEB fix at 41-52 (`mov %0, x18`). Proven clean.
- `/root/xc/w-defects/SESSION-REPORT.txt`, `ITEM4-fp-audit-result.txt`, `ITEM4-autoload-funcs.txt`
   - Persisted evidence for items 1-4 and the FP audit.
- `/root/xc/w-link/runtime/winsup/cygwin/include/cygwin/config.h` (reference, other session's tree — read only for reference)
   - The corrected TEB reference I mirrored.
</important_files>

<next_steps>
Current active task: find the binutils discriminator for the 10-of-424 base-reloc split. Investigation only; report to 2b2e50a5 and c63ab774; do not edit binutils clone or autoload.cc.

Immediate next steps:
1. Finish reading `ldexp_is_final_sym_absolute` (ldexp.c:1748-1763) and reason about whether a reloc targeting a **local section symbol** (`.<dll>_autoload_text` or `.data_cygwin_nocopy`) would be classified absolute or have `blhe==NULL` from `bfd_wrapped_link_hash_lookup(sym->name)`. Note: `bfd_wrapped_link_hash_lookup` by NAME may fail for section symbols / numeric-local-label targets, so `blhe` could be NULL → the 1684 branch (which requires `blhe && ...`) would NOT skip; need to trace what happens when blhe is NULL through the rest of the gates.
2. Compare the ARM64 path against the AMD64 known-good path: diff `coff-x86_64.c` reloc/howto handling vs `coff-aarch64.c`, and check whether AMD64 has any special-casing in generate_reloc or in how section symbols are canonicalized that ARM64 lacks.
3. Test the coordinator's "keys on unique target symbol" hypothesis directly by re-reading whether generate_reloc dedups by symbol anywhere (it appears NOT to — it's per-site). Report that my object-level measurement shows 426 relocs DO exist (both the 213 `1b`/section-symbol and 213 `_info` ones), which means the assembler is NOT dropping local-label relocs — contradicting the pure assembly-time hypothesis and localizing the drop firmly to the linker's generate_reloc filtering or an upstream section/symbol-visibility difference.
4. Investigate whether the custom `"wx"` section flags on `.<dll>_autoload_text` cause `s->output_section->flags & SEC_LOAD` (pe-dll.c:1617) or another section-level gate to behave differently — but note a wholesale section exclusion would drop ALL (426), not 414, so this alone doesn't explain 10 surviving. The 10 survivors likely correspond to relocs targeting truly-external symbols (e.g. `_std_dll_init`, `dll_func_load` in `.data_cygwin_nocopy` via the LoadDLLprime block) that pass the name-hash lookup, while the 414 target local section symbols that fail it.
5. Once the discriminator is identified in source, report findings (MEASURED vs DERIVED vs PRESUMED, exact file:line) to sessions 2b2e50a5 and c63ab774 via send_session_message. Do NOT propose/apply edits to the binutils clone.
6. Clean up scratch files: `/root/xc/w-defects/{probe-tc.sh,reloc-autoload.sh,reloc2.sh,reloc3.sh,reloc4.sh}` and /tmp/al*.

Constraints reminder: no commits/pushes/PRs/CI/upstream; `.copilot\repos\` strictly read-only; local build/test/execute permitted; never claim product PASS (nothing has executed correctly on ARM64 yet); prove detectors can fire before reporting a zero.
</next_steps>