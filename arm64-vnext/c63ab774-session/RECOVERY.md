# ARM64 vNext — session `c63ab774` recovery notes

Written against an imminent machine reformat. **The WSL tree at `/root/xc/`
is not recoverable and is not in this commit.** What is here is the source
fixes, the recipes to rebuild, the measurements, and the sealed evidence.

> **Document history.** The body below was written before `port-patch/`,
> `verify-artifacts/` and `scripts/libstdcxx.sh` existed, and was amended
> afterwards to add them. If you find something else on the branch that this
> file does not mention, trust the branch — and suspect that other omissions
> of the same kind may remain.

## START HERE: `port-patch/` is the substrate

**Read this before touching the four committed defect fixes.**

`arm64-vnext/c63ab774-session/port-patch/` holds the ARM64 port itself,
preserved as an artefact and **deliberately not applied** to `winsup/` on
this branch. The user was asked whether to commit the port as source and
declined; this preserves it without pre-empting that decision.

| | |
|---|---|
| `arm64-port.patch` | 2458 lines, 39 files, against base `d890a845e` |
| `generators/gendef` | 978 lines — emits the 989 `sigfe`/`sigbe`/`sigdelayed` trampolines |
| `generators/autoload.cc` | 840 lines — the AArch64 autoload thunks |
| `generators/mkimport`, `generators/cygwin.sc.in` | import thunk; linker script |
| `generated-sigfe.s` | the generated assembly, 3926 `_sigfe` references |
| `untracked/math-aarch64/` | 3 files never tracked in git, incl. `longdouble.c` |

**Why this matters more than anything else here: the four committed fixes
patch code that does not exist without this patch.** `hookapi.cc`,
`dcrt0.cc`'s stack switch, `quoted()` — on a clean upstream tree the ARM64
arms those fixes touch are `#error unimplemented for this target`. **Applying
the fixes to a clean tree without first applying `arm64-port.patch` produces
nonsense.** Order is: port patch, then the fixes.

The four generator files are stored **verbatim**, not only as diff hunks,
because they are standalone programs and a diff is worth little once the base
moves. See `port-patch/PORT-PATCH-README.md`.

## What else is committed

| | |
|---|---|
| `winsup/cygwin/hookapi.cc` | the ARM64 case label — root-cause fix for exec |
| `winsup/cygwin/dcrt0.cc` | fork stack headroom, argv `memmove`, `get_parent_handle()` leak close |
| `evidence/` | 106 sealed files + `SHA256SUMS` |
| `scripts/` | 156 recipe scripts, incl. `sF7-relink-import.sh` and `libstdcxx.sh` |
| `tests/` | rung sources and debug harnesses |
| `verify-artifacts/` | 33 files — generator verification evidence, **see the warning below** |

`scripts/libstdcxx.sh` is the configure invocation for the freestanding C++
headers. It encodes that `winsup/cygwin` includes exactly one C++ header,
`<new>`, and that a hosted libstdc++ is neither buildable here (its configure
dies on `GCC_NO_EXECUTABLES`) nor needed. Without it that has to be
rediscovered, which cost real time the first time.

### `verify-artifacts/` — evidence, and it contains a trap

These are **evidence, not build inputs.** Nothing in there is consumed by a
build and none of it should be wired into one. Its most valuable file is
`gendef.orig`, the **pre-port baseline** of the generator (485 lines, zero
aarch64 references) — pair it with `port-patch/generators/gendef` (978 lines)
to see what the port actually changed.

**The trap:** the `sigfe.s` captures in that directory carry the header
comment `TEB access: mrs x16, tpidr_el0`. **That idiom is wrong on Windows on
Arm** — the TEB is in `x18`, and `tpidr_el0` reads 0. Those captures pre-date
the fix. Anyone skimming for an example of correct generator output will find
the wrong one first, because a directory named "verify" looks more like
reference material than a patch does. **The correct output is
`port-patch/generated-sigfe.s`, whose comment reads `mov x16, x18`.**
Per-file detail is in `verify-artifacts/INDEX.md`.

The filing intended for upstream is
`evidence/FILING-hookapi-arm64-classification.md` — eleven sections, the
one-line diff, the full measured chain, blast radius, both regressions, and
its own scope limits.

## What is LOST and cannot be recovered from this commit

* **The cross toolchain** — `/root/xc/inst`, `aarch64-pc-cygwin-gcc 15.0.1`
  plus binutils with `aarch64pe`/`pe-aarch64-little`. Not rebuilt here; the
  recipes under `scripts/toolchain-recipe/` describe how it was made, and
  `evidence/toolchain-manifest.txt` records exactly what it contained.
* **The built runtime** — canonical `msys-2.0.dll`
  sha256 `b4bdbd9e3f7d8d50…`. Too large to commit and regenerable.
* **The compiled rung binaries.** Sources are in `tests/`; most generators
  in `scripts/` embed their source inline via heredoc.
* **`/root/xc/w-link/`** — the configured build tree (newlib, libgcc, import
  libs, the freestanding C++ headers at `sysroot-cxx`).

## Rebuild order

0. **Apply `port-patch/arm64-port.patch` to a tree at base `d890a845e`, and
   copy `port-patch/untracked/math-aarch64/` into `winsup/cygwin/math/aarch64/`
   — that directory was never tracked in git and the tree fails at link
   without `longdouble.c`.** Skipping this step is not an option: the four
   committed fixes patch ARM64 code that upstream does not have. If the
   patch's hunks no longer apply, the four generator files under
   `port-patch/generators/` are stored whole and can be dropped in directly.
1. Toolchain per `scripts/toolchain-recipe/` (this is the long pole).
2. Freestanding C++ headers per `scripts/libstdcxx.sh`: `winsup/cygwin`
   includes exactly one C++ header, `<new>`. A hosted libstdc++ is neither
   possible (its configure dies on `GCC_NO_EXECUTABLES`) nor needed.
3. newlib, libgcc, import libs.
4. `winsup/cygwin` objects. **Three things bite here:**
   * **Back up `tlsoffsets` first.** `scripts/gentls_offsets` greps for
     `\.long`; AArch64 emits `.word` for the `const uint32_t` it generates,
     so regeneration silently produces a **56-byte file of zeros** in place
     of the correct 1822-byte one, **and exits 0** — so no build system will
     notice. A known-good copy (1822 bytes, 59 entries) is committed at
     `verify-artifacts/tlsoffsets`. See
     `evidence/tlsoffsets-hazard-demonstrated.txt`.
   * **`-D__MSYS__` is required.** Without it `dcrt0.cc` compiles the
     `cygwin_dll_init` branch instead of `msys_dll_init` — clean compile,
     wrong symbol, 38 sites across 18 files affected.
   * `Makefile.am` uses the obsolete `$(INCLUDES)`; extract it from the
     generated `Makefile`'s `AM_CPPFLAGS` line.
5. Link with `scripts/sF7-relink-import.sh`. `libdll.a` must be assembled by
   hand from the objects that exist plus `fenv_aarch64.o`, because `make`
   dies on `aarch64/*.S` files that the port references but does not supply.
   `-e dll_entry` **and** `msys.def` are both required.
   **`-Wl,--no-insert-timestamp` is required for a byte-reproducible link** —
   without it two identical relinks differ in 3 bytes (the PE timestamp).

## State at the time of writing

Working, measured: process start, `main()`, `printf`/`malloc`/`free`,
signal delivery, ctype/strtol, `fork` (nested, pipes, child-side heap),
intact `argv`, `exec` in four shapes (fork+execv, fork+execl, direct, and
into a native Windows program), and signal delivery after exec.
**12/12 rung tests, 55/55 across five repeats.**

**Not done, and the ceiling should travel with any citation of the above:**
no threads, no job control, no signals across fork, and **no real MSYS2
program (bash, coreutils) has ever run**. Twelve purpose-built test
programs is a narrow slice, not a product pass. Linking is not running.

## Three defects found and fixed

1. **fork** — the AArch64 arm of the main-stack switch omitted the
   subtraction its x86_64 counterpart makes. x86 addresses locals at
   negative offsets from `rbp`; AArch64 spills at *positive* offsets from
   `sp`, so the frame sat above the stack top and this function's own TEB
   spill, `str x4,[sp,#24]`, landed on `cygheap->chain`.
2. **argv** — `strcpy (cmd, cmd + 1)` in `quoted()`, overlapping source and
   destination. Undefined behaviour on every target; benign on x86_64 by
   implementation accident, corrupting on AArch64's NEON `strcpy`. **A
   latent upstream Cygwin bug, not a port error.**
3. **exec** — `hookapi.cc`'s machine-type allowlist lacked ARM64, so every
   AArch64 binary was classified foreign, mis-routing **17** decisions
   across `spawn.cc`, `sigproc.cc` and `exceptions.cc`.

## One caveat that applies retroactively to this session's own evidence

`spawn.cc:882` reads `synced = iscygwin () ? sync (...) : true`. Before the
hookapi fix that meant **every spawn skipped the `subproc_ready` handshake**
with `synced` simply asserted true. Timing-sensitive conclusions reached on
pre-fix builds should be re-read. The fork and argv findings are *not*
affected — both are parent-side faults occurring before `CreateProcess`
(a static store target in the linked image; string handling before any
spawn), so the barrier's state cannot reach them. That was re-derived
independently rather than accepted from the author.
