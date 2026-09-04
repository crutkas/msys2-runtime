# ARM64 vNext runtime — static-analysis lane handoff (session 57224227)

Recoverable handoff committed under explicit user authority ahead of a machine
reformat. This session was the **read-only static-analysis lane**: cross-compile,
disassemble, DWARF-inspect, source-read only. It never edited source, ran
binaries, committed, or pushed — except this handoff commit. All findings are
**source-derived and hash-independent.** Peer runtime-tree session (edits + dynamic
tests on real Windows-on-ARM64): `c63ab774`. Coordinator: `2b2e50a5`.

The authoritative durable record is `checkpoints/011-emutls-negative-mmap-correction-allocator-clean.md`
(77 KB, 850 lines) — RESULTS L/M/N/O and the entire exec appendix after them,
including falsified sealed lines retained for audit. This file indexes the rest.

## Programme headline (honest boundary — no product PASS)
An ARM64 `msys-2.0.dll` that links, loads and runs: process start, malloc/printf,
signals, ctype, fork (nested, pipes, child-side heap), intact argv, exec in four
shapes (incl. into a native Windows program and into a signal-handling target).
**NOT done:** no threads, no job control, no signals across fork, no real MSYS2
program has ever run. Compiling is not correctness.

## Three defects root-caused
1. **cygheap chain corruption (FIXED, commit `d9369d0bf`).** `str x4,[sp,#24]` @ RVA
   0x6CD8 in `_dll_crt0`: TEB spill landing on cygheap+8 via StackBase≡cygheap-base
   aliasing. Fix `sub sp,sp,#0x40`. Verified by instruction-level disasm of a static
   store target — barrier-independent.
2. **argv strcpy self-overlap (FIXED, commit `6397acaa5`).** Upstream `quoted()` in
   dcrt0.cc does `strcpy(X, X+1)` (UB), benign on x86 memcpy-style but corrupts under
   NEON `strcpy` — mangled exec target filenames (rung3.exe→runng3.exe→ENOENT). Fix
   memmove. Verified by source UB + byte-for-byte argv round-trips across 40 lengths;
   parent-side, pre-CreateProcess — barrier-independent.
3. **exec child_copy err6 (ROOT CAUSE, one-line fix awaiting user).** See below.

## THE EXEC ROOT CAUSE — machine-type allowlist missing ARM64
Single missing case label. `hookapi.cc` `PEHeaderFromHModule` (lines 43-51):
```c
switch (pNTHeader->FileHeader.Machine) {
  case IMAGE_FILE_MACHINE_AMD64: break;
  default: return NULL;          // aarch64 PE (Machine=0xAA64) lands here
}
```
comment @43 "valid ... only for supported architectures." **No ARM64 case.**

Full chain, every link source-read or measured:
aarch64 PE → `PEHeaderFromHModule` NULL (hookapi.cc:48) → `hook_or_detect_cygwin`
NULL (hookapi.cc:340) → `set_cygexec(NULL)` (spawn.cc:1225) clears `MOUNT_CYGWIN_EXEC`
(path.h:260-266) → `iscygexec()=0` → `_CI_ISCYGWIN` unset (sigproc.cc:923-927) →
**`iscygwin()=0`** → `!iscygwin()` guard fires (spawn.cc:594) →
`SetHandleInformation(parent, HANDLE_FLAG_INHERIT, 0)` (spawn.cc:597) → parent not
inherited → absent from child table → `child_copy` ERROR_INVALID_HANDLE (err6).

**It is a genuine ARM64 defect (PE auto-detection, architecture-dependent), NOT a
mount-table/harness artefact.** Tree-wide sweep (all hits opened): ARM64 IS handled
at exit_process.h:76, uname.cc:66, path.cc:4975; hookapi.cc:46 is the SOLE allowlist
missing it; exit_process.h:69+76 lists BOTH AMD64 and ARM64 in the same idiom → the
omission is a port oversight, not intent. Arch-specificity is true **by
construction** from the switch (x86_64 takes the AMD64 case by definition), so no
x86_64 differential build is needed to prove it.

**Fix (derived here, verified dynamically by c63ab774):** add
`case IMAGE_FILE_MACHINE_ARM64: break;` at hookapi.cc:46. Measured before→after with
the fix AND the get_parent_handle() workaround reverted in the same build (clean
isolation): iscygwin 0→1; clear fires yes→no; GetHandleInformation at CreateProcessW
0x0→0x1 (INHERIT_SET=1); child in_table 0→1; err6→EXEC WORKS. The workaround was
correctly DROPPED (redundant once the cause is fixed; costs an OpenProcess per exec
including on x86_64); only the pre-existing handle-leak close inside
get_parent_handle() was kept; upstream guard restored verbatim.

## child_copy exoneration (what pointed everyone at the handle, not the arithmetic)
`_cmalloc_entry` (cygheap.h:15) identical on both LP64 archs; `child_info`
checksummed and transferred intra-build; `child_copy` is a bare, pointer-clean
`ReadProcessMemory`; committed region ⊇ copied region. The read args/range/mask were
never the fault — `child_copy` had no handle to read through. This exoneration is
what redirected the whole hunt to the parent handle.

## mint→create window audit (spawn.cc:551 → :656/:712)
Every statement naming `parent` enumerated. `spawn.cc:597` is the SOLE touch of
`parent` in the ~110-line window. `deimpersonate()` (cygheap.h:162-165) =
`RevertToSelf()` — touches no handle-table entry; Windows inheritance is a property
of the handle attribute + `bInheritHandles`, not the acting token → the mint/create
token asymmetry is REAL but INERT (bounded negative). `CreateProcessAsUserW`@707 is
the setuid branch only; rung3 takes plain `CreateProcessW`@656.

## iscygwin() blast radius (the filing headline) — 17 sites / 3 subsystems
Pre-fix ALL evaluated `iscygwin()=0` for every ARM64 binary (foreign-program
branch); the hookapi fix flips all 17 to =1 atomically. **Classified from source;
largely UNTESTED dynamically** — the 12 rungs enter only a handful of these, so the
"none relied on the foreign branch" claim is DERIVED-from-source, not
cross-validated (`:900` close_all_files and `:877` detach/nowait are
behaviour-changed and untested-by-rung).
- **spawn.cc ×12:** 564, 577, 594, 615, 626, 754, 771, 865, 869, 877, 882, 900
- **sigproc.cc ×3:** 1044, 1071, 1204
- **exceptions.cc ×2:** 1063, 1714

**Four masked latent defects (lead with 577 — user-visible):**
- `spawn.cc:577` — ARM64 Cygwin children wrongly got `CREATE_NEW_PROCESS_GROUP`,
  breaking Ctrl-C/job-control grouping. The one a shell user would feel first.
- `sigproc.cc:1044` — `PROC_EXEC_CLEANUP` skipped on exec.
- `sigproc.cc:1071` — `record_children` skipped (non-reaped children not passed to
  the execed process).
- `spawn.cc:882` — `synced = iscygwin() ? sync() : true` → the `subproc_ready`
  barrier was SKIPPED on every pre-fix spawn. **Caveat scope:** this bounds only
  timing-sensitive claims; defects 1 and 2 above are parent-side/pre-CreateProcess
  static faults (a store target; a strcpy overlap), so neither rests on timing and
  neither reopens — a bound by construction, re-derived independently, not asserted.

## bounded overlap sweep + NEON strcpy
Exactly TWO `strcpy` self-overlap sites tree-wide, no siblings (the sweep is
complete, not a sample). NEON `strcpy` disassembly confirms the load/store-forward
overlap hazard that makes `strcpy(X,X+1)` corrupt where x86's byte-copy did not.

## Filing (sealed by c63ab774)
`evidence/FILING-hookapi-arm64-classification.md` (in c63ab774's tree), 243 lines,
11 sections: Summary, The defect, Why it breaks exec, The fix, Evidence, Blast
radius, Stability, Second-subsystem regression, Note for the patch author (incl.
"don't add a #define"), Scope and honesty. `106/106` is a **hash seal (SHA256SUMS
integrity), NOT coverage** — real ceiling is 12/12 rungs, 55/55 repeats. Canonical
DLL `b4bdbd9e3f7d8d50`, byte-reproducible across 4 links (`--no-insert-timestamp`).
Branch clean at `d9369d0bf`; the hookapi fix + leak close await the user.

## Four original programme items — all complete
1. **8 orphan cygwin.din exports** — documented aarch64 exclusions/predictable stubs
   (`fegetprec`/`fesetprec`/`_fe_nomask_env` are x87-precision, meaningless on ARM64
   → honest exclusion, not an invented equivalent).
2. **gentls_offsets** — awk pattern widened to match ARM64 `.word` (not just `.long`).
3. **version-robust SEH handler name** — derived/conditioned on struct existence
   rather than a hard-coded P19/P25 mangled tag; two false comments deleted.
4. **v0-v7 autoload FP-param audit** — reported.

---

# BINDING ENVIRONMENT NOTES (the coordinator paid for ignoring these 3×)
- **Toolchain:** `/root/xc/inst/bin/aarch64-pc-cygwin-*` (GCC 15.0.1, binutils
  2.44.50 with aarch64pe). REUSE — do not rebuild. Do NOT reinstall w32api headers
  (silently reverts the `#if defined(__x86_64__)||defined(__aarch64__)` _WIN64 fix
  and collapses the build ~271→~116 objects). Do NOT use mingw-w64 master (8c4baed92
  mbstate_t move breaks every Cygwin target). No corecrt.h shim.
- **Cannot EXECUTE aarch64 binaries in WSL** — cross-compile/disassemble/DWARF only.
- **Source is READ-ONLY** at `/root/xc/w-defects/winsup/cygwin`. Do NOT touch
  `/root/xc/inst|runtime|bld` (preserved), `w-autoload`/`w-gendef` (other sessions),
  or the sealed Windows worktree.
- **`/tmp` does NOT persist across WSL calls.** If a value matters, redirect it to a
  file in the SAME command that produced it. Echo to a transcript is not persistence.
- **PowerShell→WSL quoting trap:** inline `bash -c` with `$VAR`, awk, quotes, or `|`
  alternation gets mangled. DODGE: write a `.sh` into `files/` and invoke it, OR
  split into simple single grep commands. `files/rd.sh` reads numbered line ranges:
  `wsl -d Ubuntu bash -c 'bash /mnt/c/.../files/rd.sh FILE START END'` (reads from
  `/root/xc/w-defects/winsup/cygwin`).
- **Assembler directive facts:** ARM64 GCC emits `.word` (32-bit), `.xword` (64-bit),
  `.hword` (16-bit) — NOT x86's `.long`/`.quad`. Any awk/grep scraping asm offsets
  must match `.word`/`.xword`, not just `.long`. (This was the gentls_offsets bug.)

# METHOD RULES (binding, learned the hard way)
- A NON-MATCH IS NEVER EVIDENCE OF ABSENCE — pattern-matching locates candidates;
  open the file to conclude absence.
- Where a symbol sits inside preprocessor conditionals, measure what the COMPILER
  SEES after preprocessing, never what grep finds.
- A CORRECTION IS A CLAIM — re-derive from primary source before asserting it.
- Distinguish MEASURED from DERIVED from PRESUMED in every claim.
- Validate a detector against a known positive before trusting its negative.
- **Rejecting a candidate because a guard EXISTS, without measuring what the guard
  EVALUATES TO, is an inference standing in for a measurement.** (The exec root cause
  was rejected by four parties on the guard's existence; it fell only when someone
  measured `iscygwin()=0`. Knowing the rule and applying it when it costs you
  something are different skills.)
- A green result whose scope never entered the branch is not evidence about that
  branch. A seal/hash count is not a coverage number.
- **x18 holds the TEB on Windows ARM64 — NEVER write x18.** Read TEB via
  `mrs x16, tpidr_el0` then `ldr [x16,#8]`. Beware `#0x18` immediates and ASCII in
  disassembly as substring false positives.
- **LSE atomics unavailable** (baseline ARMv8-A, `+v8a`): use `ldaxr`/`stlxr`, not
  `swpal`/`ldaddal`.
- Report the FULL LABELLED progression of object/error counts, never one headline;
  label each row real or diagnostic. Never claim a product PASS.
