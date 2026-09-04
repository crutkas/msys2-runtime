# `xc-verify` — generator verification artefacts

**These are EVIDENCE, not build inputs.** Nothing here is consumed by a
rebuild. Do not wire any of it into a build; it exists so that the ported
`gendef` can be reviewed and its output judged against known-good references.

Recovered from `/root/xc-verify`, a **sibling** of `/root/xc`. Three
completeness sweeps this session searched `/root/xc/**` and could not see it.

## The two files that matter most

| file | why |
|---|---|
| `gendef.orig` | **The pre-port baseline of `gendef`** — 485 lines, **zero** aarch64 references. The ported generator (`../port-patch/generators/gendef`, 978 lines, 11 aarch64 references) is preserved verbatim elsewhere. Baseline + ported = a reviewable diff, ~509 lines. Without this file, seeing *what the port changed* means hunting the matching upstream revision. |
| `INDEX.md` | this file |

## The x86 controls — "what does the working architecture produce?"

| file | measured |
|---|---|
| `sigfe-x86_64.s` | 209,538 bytes, **3924** `_sigfe` references |
| `x86reg/sigfe.s` | byte-identical to the above — the same capture kept beside its `msys.def` and `out.log` |
| `x86reg/msys.def` | 40,698 bytes |
| `x86.def` | 40,698 bytes, matching |
| `sigfe-x86.s`, `x86.err` | **both 0 bytes** — empty captures. Whether that means 32-bit x86 was attempted and produced nothing, or the files were created and never written, is **not recoverable**. Preserved as-is rather than deleted, because an empty file is itself a record. |

The aarch64 output has **3926** trampolines against x86_64's 3924. The
two-entry difference is visible in the `aaA`/`aaB` diff below and is not
otherwise explained here.

## `aaA` … `aaD` — four generator runs

Purposes below are **derived from the artefacts themselves**, not from a
contemporaneous note. Where I could not recover the intent I say so.

### `aaA` and `aaD` — byte-identical to each other
`sigfe.s` 294,545 bytes, 14,162 lines, 3926 trampolines; `msys.def` 40,698 B.
Empty logs, i.e. clean runs. The top-level `xc-verify/sigfe.s` is
byte-identical to both, so **this is the accepted output**.

Their `msys.def` is **MSYS-conditioned**: it exports `msys_detach_dll`,
`msys_dll_init`, plus `_ctype_ DATA`, `_fe_nomask_env DATA` and
`_alloca = __alloca`.

**Why `aaD` repeats `aaA` byte-for-byte is not recovered.** The most likely
reading is a determinism check — same input, same output, run twice — but the
logs are empty and I will not assert it.

### `aaB` — the same generator against a **Cygwin-conditioned** definition
`sigfe.s` 294,557 bytes (12 B larger), same 14,162 lines and 3926
trampolines; `msys.def` 40,646 B (52 B smaller). Diff vs `aaA` is 30 lines and
is **entirely** the detach-DLL entry point:

```
aaA/aaD:  _sigfe_maybe_msys_detach_dll     -> msys_detach_dll
aaB:      _sigfe_maybe_cygwin_detach_dll   -> cygwin_detach_dll
          msys_dll_init = cygwin_dll_init
```
and the absence of `_ctype_`, `_fe_nomask_env` and `_alloca` from the def.

**This is the `__MSYS__` conditioning difference**, and it is the same
distinction that later turned out to matter for the build: compiling without
`-D__MSYS__` silently selects `cygwin_dll_init` instead of `msys_dll_init`.
See `../evidence/` and `../RECOVERY.md`. `aaB` is what the generator emits when
the definition is *not* MSYS-conditioned.

### `aaC` — a **failed** run, and its log is the whole content
No `msys.def`, no `sigfe.s` — only a log, which reads:

```
syntax error at /root/xc/w-orphans/gendef2 line 47, near "if !"
Execution of /root/xc/w-orphans/gendef2 aborted due to compilation errors.
```

So `aaC` is a run of a **different, broken generator** — `gendef2`, from
`w-orphans`, one of the trees recorded as contaminated with the stale
`tpidr_el0` TEB read. It never produced output. Preserved because a recorded
failure is evidence: it is why `w-orphans/gendef2` is not the authority.

## A dating clue worth knowing before reading the assembly

The `sigfe.s` files here carry the header comment:

> `TEB access: mrs x16, tpidr_el0`

**That idiom is wrong on Windows on Arm** — the TEB is in `x18`, and
`tpidr_el0` reads 0. It was found and fixed later in the programme. So these
captures **pre-date the TEB fix** and are useful as generator-output evidence,
**not** as a model to copy. The corrected generator is
`../port-patch/generators/gendef`; the corrected output is
`../port-patch/generated-sigfe.s`, whose comment reads `mov x16, x18`.

## Remaining files

| file | what |
|---|---|
| `tlsoffsets` | the good 1822-byte file, 59 entries. Travels with the hazard warning: `scripts/gentls_offsets` greps for `\.long` while AArch64 emits `.word`, so regenerating it silently yields 56 bytes of zeros **and exits 0**. Back it up before `make`. |
| `reloc/t_arm.s`, `t_arm.o`, `t_x86.s` | relocation test cases, ARM vs x86 pair |
| `as.err` | assembler error captures |
| `sigfe.s`, `sigfe.o` | top-level accepted output and its object |
| `seal_fixed.txt`, `seal_numstat.txt`, `sealed_files.txt`, `numstat.txt`, `joined.txt`, `tree_content.txt`, `tree_files.txt` | seal and manifest records |
