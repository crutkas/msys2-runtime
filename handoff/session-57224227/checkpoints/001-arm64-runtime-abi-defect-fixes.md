<overview>
The task is to close the four remaining known runtime-ABI defects for the ARM64 vNext port of the MSYS2 runtime (msys-2.0.dll), so it stops blocking a genuinely native ARM64 Git-for-Windows toolchain. All work is local compile/test/experimentation in an isolated WSL cross-compilation tree; commits, pushes, branches, PRs, and upstream contact are forbidden. The approach: for each defect, measure the actual root cause empirically (compile/nm/preprocess), then apply an honest fix and validate it produces the correct symbols/output for aarch64 while not regressing x86_64.
</overview>

<history>
1. Task kickoff (autopilot, from General Chat session 2b2e50a5-63c5-49f9-8b89-d825396b5ff9): close FOUR known runtime defects, working in an isolated WSL tree, reusing the existing cross-toolchain at `/root/xc/inst`.
   - Renamed branch to `crutkas-runtime-remaining-defects` (tool prefixed it to `crutkas-runtime-remaining-defects`).
   - Verified WSL Ubuntu access; inspected `/root/xc/` tree layout.
   - Created my own isolated detached-HEAD git worktree at **`/root/xc/w-defects`** (from `/root/xc/runtime` at commit d890a845e) — this is my tree; I do not touch `/root/xc/runtime`, `/root/xc/inst`, `/root/xc/bld`, `w-autoload`, `w-gendef`, or Windows worktrees.
   - Discovered the ARM64 port lives as **uncommitted working-tree changes + untracked files** in `/root/xc/runtime`; captured `git diff` to `/tmp/arm64-working.patch`, applied it to `w-defects`, and copied untracked `winsup/cygwin/math/aarch64/`.

2. Item 2 (gentls_offsets awk pattern) — COMPLETED & VERIFIED.
   - Measured: aarch64 GCC emits `.word` (not `.long`) for 4-byte uint32_t constants; zero values emit `.space 4 // skip`.
   - Fixed both `.long` awk matchers in `scripts/gentls_offsets` to `(.long|.word)`.
   - Ran the fixed script → produced a correct **59-line** `tlsoffsets` (was broken 2-line), with `context_p=3744` (16-byte aligned, self-check passed).

3. Item 1 (eight orphan cygwin.din exports) — COMPLETED & VERIFIED.
   - Measured each symbol's true status via source inspection, compilation, and nm.
   - `_ctype_`: fixed ctype_.c asm-alias guard to include `__aarch64__` (verified emits `_ctype_`).
   - `msys_dll_init`: root cause is cross toolchain predefines `__CYGWIN__` but NOT `__MSYS__`; added `-D__MSYS__` under TARGET_AARCH64 in Makefile.am (verified dcrt0.o then exports `msys_dll_init` instead of `cygwin_dll_init`).
   - `feenableexcept`/`fedisableexcept`/`fegetexcept`: real ARM64 FPCR impl; fixed via header prototype-ordering + `__fenv_static` (verified libm fenv.o emits all three; 11→14 fe* externals).
   - `fegetprec`/`fesetprec`/`_fe_nomask_env`/`__alloca`(`_alloca`): x86-only; added new `X86_64_ONLY` din tag handled in gendef; verified excluded on aarch64, retained on x86_64.

4. Item 3 (version-robust SEH handler name) — IN PROGRESS.
   - Measured: `%c0` asm operand with `"i" (&exception::handle)` makes the compiler emit the correct mangled name (P19 for default `_DISPATCHER_CONTEXT` tag, P25 for `_DISPATCHER_CONTEXT_ARM64` tag) — proven via seh-probe.cc for both header variants.
   - Applied the derived-name fix to exception.h aarch64 branch; fixed the false comment at exception.h:13-18.
   - Was about to fix cygtls.h (the `_CYG_SEH_MYFAULT_SYM` macro at lines 367-379 hard-codes P19, plus false comment at line 365).

5. Item 4 (v0-v7 FP register audit) — NOT STARTED.
</overview>
</history>

<work_done>
Files modified in `/root/xc/w-defects` (all validated except where noted):

1. `winsup/cygwin/scripts/gentls_offsets` — widened both awk `.long` patterns to `(.long|.word)` for aarch64. VERIFIED produces correct 59-line tlsoffsets.

2. `newlib/libc/ctype/ctype_.c` (~line 98) — changed `#ifdef __x86_64__` to `#if defined(__x86_64__) || defined(__aarch64__)` so the `.set _ctype_,_ctype_b+127` asm alias fires on aarch64. VERIFIED emits `_ctype_`.

3. `winsup/cygwin/Makefile.am` (TARGET_AARCH64 block ~line 19-27) — added `COMMON_CFLAGS+=-D__MSYS__` with explanatory comment. VERIFIED via manual dcrt0.cc compile that `msys_dll_init` is emitted.

4. `newlib/libc/machine/aarch64/sys/fenv.h` (~lines 81-116) — changed `feenableexcept`/`fedisableexcept`/`fegetexcept` from `static inline` to `__fenv_static __inline`, and added plain prototypes BEFORE their inline bodies inside the `#if __BSD_VISIBLE` block. VERIFIED.

5. `newlib/libm/machine/aarch64/fenv.c` (~lines 54-66) — kept `extern inline` declarations for the three functions under `#if __BSD_VISIBLE` with explanatory comment. VERIFIED all three emitted (via private targ-include overlay test).

6. `winsup/cygwin/cygwin.din` — tagged `_fe_nomask_env DATA X86_64_ONLY` (line 18), `_alloca = __alloca NOSIGFE X86_64_ONLY` (line 138), `fegetprec NOSIGFE X86_64_ONLY` (line 535), `fesetprec NOSIGFE X86_64_ONLY` (line 545).

7. `winsup/cygwin/scripts/gendef` (~line 39-40, in `for (@in)` loop) — added `X86_64_ONLY` tag handling: `if (s/\s+X86_64_ONLY\s*$//) { next unless $is_x86_64; }`. VERIFIED both arches.

8. `winsup/cygwin/local_includes/exception.h` — (a) fixed false comment at lines 13-18 describing header-set tag variance accurately; (b) replaced hard-coded P19 mangled name in aarch64 `#else` asm block with `%c0` operand + `:: "i" (&exception::handle) : "memory"`. VERIFIED via seh-probe.cc that this derives P19/P25 correctly.

Temporary scratch files created in `/root/xc/w-defects` (NEED CLEANUP): run-gentls.sh (deleted), scan-syms.sh, test-ctype.sh, test-dcrt0.sh, test-fenv.sh, test-fenv2.sh, test-fenv3.sh, test-fenv4.sh, test-bv.sh, test-pp.sh, test-gendef.sh, seh-probe.cc, seh-probe.sh.

Todos: item2-gentls=done, item1-orphans=done, item3-seh=in_progress, item4-fpaudit=pending.
</work_done>

<technical_details>
- **Isolated tree**: `/root/xc/w-defects` (detached HEAD from d890a845e). The ARM64 port was applied from `/root/xc/runtime`'s uncommitted `git diff` (`/tmp/arm64-working.patch`) plus untracked `winsup/cygwin/math/aarch64/`. My worktree therefore mirrors the preserved ARM64 source.

- **PowerShell→WSL quoting gotcha (CRITICAL, recurring)**: Inline `wsl -d Ubuntu -- bash -c '...$VAR...'` frequently mangles `$VAR` (Windows PATH with spaces leaks in as "not a valid identifier" errors, or vars expand empty). RELIABLE PATTERN: write a bash script to a file via the `create` tool, then `wsl -d Ubuntu -- bash -c "sed -i 's/\r$//' /path/script.sh; bash /path/script.sh"`. The `sed` strips CRLF that the Windows `create` tool inserts (otherwise `set: -\r invalid option`, `cd: $'...\r'`).

- **Toolchain**: `/root/xc/inst/bin/aarch64-pc-cygwin-{gcc,g++,nm}`, GCC 15.0.1, binutils 2.44.50. Target is `*-pc-cygwin` (predefines `__CYGWIN__`, `__unix__`; NOT `__MSYS__`). Baseline ARMv8-A (`+v8a`, no LSE atomics — use ldaxr/stlxr).

- **Item 1 root causes (all MEASURED)**:
  - `_ctype_`: In ctype_.c, the `#ifdef __x86_64__` branch emits `.globl _ctype_; .set _ctype_,_ctype_b+127`; the `#else` emitted `__ctype_` (wrong). aarch64-pe has NO leading-underscore symbol prefix (verified: C `_ctype_x` → asm `_ctype_x`), so aarch64 needs the same branch as x86_64.
  - `msys_dll_init`: dcrt0.cc:1100-1105 defines `msys_dll_init` under `#ifdef __MSYS__`, else `cygwin_dll_init`. Native x86 msys2 gcc predefines `__MSYS__`; the aarch64 cross does not. Fix = build flag. `__MSYS__` is consumed by ~20 source sites but defined nowhere in-tree.
  - fe-except functions: newlib libm builds with `-D_GNU_SOURCE` → `_DEFAULT_SOURCE` → `__BSD_VISIBLE=1`. The three functions were `static inline` in sys/fenv.h (never external). C99 emission rule (§6.7.4): an external definition is emitted only if a non-inline (plain) declaration and the inline body both appear, AND ordering matters with the `extern inline` re-declaration in fenv.c. The working sibling functions (feclearexcept etc.) get a plain prototype from `<fenv.h>` (line 22+) BEFORE their inline bodies in `<machine/fenv-fp.h>` (included later). The three broken ones had body-before-prototype. FIX: add plain prototypes inside sys/fenv.h's `#if __BSD_VISIBLE` block BEFORE the inline bodies, and use `__fenv_static __inline` (so fenv.c's `#define __fenv_static` empty makes them non-static). MEASURED: 11→14 fe* externals.
  - `__alloca`: aarch64 GCC inlines alloca entirely (`sub sp, sp, x0`), never calls external `__alloca` (x86 stack-probe helper). x86-only.
  - `fegetprec`/`fesetprec`/`_fe_nomask_env`: x87-precision / x86 FE_NOMASK, defined only in newlib shared_x86. Meaningless on ARM64.

- **Item 1 validation quirk**: `/root/xc/bld` generated headers hard-reference `/root/xc/runtime` paths, causing collisions if mixed with w-defects headers. For fenv validation, built a private targ-include at `/tmp/ti` overlaying edited machine headers (test-fenv4.sh) because the real build uses `/root/xc/bld/newlib/targ-include/sys/fenv.h` (installed copy, stale relative to my source edits — `__fenv_static` was still `static` there).

- **X86_64_ONLY din tag**: gendef processes cygwin.din via `scripts/gendef --cpu=@target_cpu@`. Added tag-strip at top of the `for (@in)` loop (before DATA/`=`/SIGFE parsing) so it works for both `_ctype_ DATA X86_64_ONLY` and `_alloca = __alloca NOSIGFE X86_64_ONLY` forms.

- **Item 3 SEH (MEASURED)**: C++ mangling of `exception::handle`/`myfault` embeds the tag of the struct `PDISPATCHER_CONTEXT` points to. P19_DISPATCHER_CONTEXT (w32api v12.0.0 / Windows SDK 10.0.26100.0 / widl — these normalise the tag) vs P25_DISPATCHER_CONTEXT_ARM64 (CLANGARM64 / mingw-w64 master). Token swap breaks half the header sets. The robust derivation: asm `"%c0"` operand with `:: "i" (&exception::handle)` — the compiler mangles it correctly per-header-set. PROVEN with seh-probe.cc (default→P19, -DUSE_ARM64_TAG→P25). `&exception::handle` is accessible because the asm is inside a member of the same class (handle is private static).

- **x18 rule**: NEVER write x18 (Windows ARM64 TEB platform register). Read TEB via `mrs x16, tpidr_el0; ldr [x16,#8]`.

- **Item 4 pending**: The autoload resolution stub saves x0-x8, x30 but NOT v0-v7 (SIMD/FP arg registers). Mirrors x86-64 (saves no xmm0-3). Would corrupt on first call to any autoloaded function taking float/double params. Must AUDIT the ~192 autoloaded functions for FP parameters; only fix if real exposure exists. Autoload code is in `winsup/cygwin/autoload.cc` (was in the ARM64 patch, `M winsup/cygwin/autoload.cc`).
</technical_details>

<important_files>
- `winsup/cygwin/local_includes/cygtls.h` (in w-defects)
   - IN-PROGRESS Item 3 target. Lines 363-379: `_CYG_SEH_MYFAULT_SYM` macro hard-codes P19 for both x86_64 (line 369) and aarch64 (line 375). Line 365 has a FALSE comment ("winnt.h names the struct _DISPATCHER_CONTEXT_ARM64" — opposite of the P19 code below it, per task).
   - The `__try` macro (lines 381-392) uses `_CYG_SEH_MYFAULT_SYM` inside `__asm__ goto`. Challenge: it references `exception::myfault`, and being a macro (not inside the class), `&exception::myfault` access + operand substitution needs care. myfault is a private static member of class `exception`. The `__asm__ goto` form uses `%l[...]` label operands; adding an `"i"` input operand to asm-goto requires GCC that supports outputs/inputs on asm goto (GCC 15 does). Alternatively derive the symbol via a different mechanism. NEEDS SOLUTION.

- `winsup/cygwin/local_includes/exception.h` (in w-defects)
   - COMPLETED Item 3 (partial). Comment lines 13-18 rewritten; aarch64 asm block now uses `%c0` + `"i" (&exception::handle)`. x86_64 branch (lines 35-43) left with hard-coded P19 (out of ARM64 scope, still works).

- `newlib/libc/machine/aarch64/sys/fenv.h` (in w-defects)
   - Item 1 fe-except fix. Lines ~81-116: prototypes-before-bodies + `__fenv_static __inline`.

- `newlib/libm/machine/aarch64/fenv.c` (in w-defects)
   - Item 1 fe-except fix. Lines ~54-66: `extern inline` decls under `#if __BSD_VISIBLE`. `#define __fenv_static` empty at line 30 is what makes it work.

- `newlib/libc/ctype/ctype_.c` (in w-defects)
   - Item 1 `_ctype_` fix at ~line 98.

- `winsup/cygwin/Makefile.am` (in w-defects)
   - Item 1 `msys_dll_init` fix: `-D__MSYS__` in TARGET_AARCH64 block ~line 19-27.

- `winsup/cygwin/cygwin.din` and `winsup/cygwin/scripts/gendef` (in w-defects)
   - Item 1 X86_64_ONLY exclusions and the gendef tag handler.

- `winsup/cygwin/scripts/gentls_offsets` (in w-defects)
   - Item 2 fix (both awk `.long`→`(.long|.word)`).

- `winsup/cygwin/autoload.cc` (in w-defects)
   - Item 4 target (v0-v7 audit). Not yet examined in detail.
</important_files>

<next_steps>
Remaining work:
- FINISH Item 3: Fix cygtls.h. Replace the hard-coded P19 in `_CYG_SEH_MYFAULT_SYM` (aarch64 branch, line 374-375) with a compiler-derived name, mirroring the exception.h `%c0` approach but adapted for the `__try` macro's `__asm__ goto` context (myfault is `class exception`'s private static member). Options to investigate: (a) add an `"i" (&exception::myfault)` input operand to the asm goto and use `%cN`; (b) verify GCC 15 asm-goto supports input operands; (c) if the macro context blocks operand substitution, consider a compile-time-derived string constant. Also DELETE/fix the false comment at cygtls.h:365. Then VERIFY by preprocessing/compiling a snippet that uses `__try`/`__except` on aarch64 and checking the emitted `.seh_handler` uses the derived name (test P19 default + P25 with _DISPATCHER_CONTEXT_ARM64 tag). Then mark item3-seh done.
- Item 4: Audit ~192 autoloaded functions in `winsup/cygwin/autoload.cc` for FP (float/double) parameters. The stub saves x0-x8, x30 but not v0-v7. Enumerate the autoloaded function list, cross-reference each against its Win32 signature for float/double params. Report the full list either way. Only fix the stub (add v0-v7 save/restore) if the audit shows real exposure. Remember x18 must never be written.

Immediate next steps:
- View cygtls.h lines 363-395 (partially viewed) and design the myfault-name derivation for the asm-goto macro context.
- Test the cygtls.h fix with a small `__try`/`__except` compile probe for both header-tag variants.

Cleanup before finishing: remove scratch files in `/root/xc/w-defects` (scan-syms.sh, test-*.sh, seh-probe.cc, seh-probe.sh, and any tlsoffsets.generated).

Reporting requirements (binding): distinguish MEASURED/DERIVED/PRESUMED; report full labelled progression of object/error counts; never claim a product PASS (nothing has executed on ARM64; compiling ≠ correctness); a non-match is never evidence of absence (open the file); persist values to files in the same command that produces them.
</next_steps>