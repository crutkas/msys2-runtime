# Attempting a native ARM64 `msys-2.0.dll` link — result

**Session:** `c63ab774-a023-4e57-9bc4-53f727507ada` · **Date:** 2026-09-02 · Local build only.
No commits, pushes, refs, PRs, CI, upstream submissions, or contributor contact were made.
`/root/xc/inst` (the programme's only working cross toolchain) was **not** modified: every new
artefact was written to a different prefix or to a build tree.

---

## HEADLINE: **NO. A `msys-2.0.dll` did NOT link.**

No `.dll` file exists. There is no PE machine type, size or sha256 to report, because no image
was produced. What *did* happen is that the build reached the **link stage for the first time in
this programme**, with real `libc.a`, `libm.a`, `libgcc.a`, real ARM64 import libraries, a real
linker script and a real `.def` file — and the linker produced a **complete, finite list of what
is still missing**. That list is below and is the deliverable.

Nothing was stubbed. `libdll.a` contains **only** object files that genuinely compiled.

---

## 1. Preconditions (verified before trusting any number)

| # | Precondition | Verified value |
|---|---|---|
| 1 | `inst/aarch64-pc-cygwin/include/w32api/_cygwin.h` carries the aarch64 `_WIN64` fix | **YES** — `#if defined(__x86_64__) \|\| defined(__aarch64__)` |
| 2 | w32api version | **12.0.0** (released, not master) |
| 3 | `mbstate_t` absent from `corecrt.h` (no `8c4baed92` regression) | **YES** |
| 4 | no `corecrt.h` shim reinstated | **YES (clean)** |
| 5 | cross compiler unchanged | `aarch64-pc-cygwin-g++ (GCC) 15.0.1 20250131 (experimental)` |

## 2. FULL LABELLED PROGRESSION

Denominator 310 = "intended `.o` targets", the same denominator session `1e64365a` used.
Metric = `find -name '*.o' | wc -l` in `/root/xc/bld/winsup/cygwin`, same as the sibling.

Rows 1–5 are session `1e64365a`'s, reproduced with their qualifiers. Rows 6–10 are mine.

| # | Configuration | objects /310 | `error:` lines | fixes real or throwaway? |
|---|---|---|---|---|
| 1 | w32api **master**, no fixes | 116 | 314 | — |
| 2 | + `_WIN64` aarch64 fix | 116 | 285 | `_WIN64` fix is REAL (already in sysroot) |
| 3 | + w32api **v12.0.0** instead of master | **254** | 15 | **sealed port AS-IS = this row** |
| 4 | + 3 target-detection fixes, `-Werror` on | 261 | 8 | those 3 are **THROWAWAY DIAGNOSTICS** |
| 5 | same as 4, warnings non-fatal | 265 | 3 | same 3 throwaway diagnostics |
| 6 | + freestanding C++ headers (`<new>`) | **268** | **0** | header install is REAL toolchain work |
| 7 | + `devices.cc` timestamp (use tracked pre-generated file) | 269 | 1 (transient) | build-tree only |
| 8 | + `thread.cc` `pause`→`yield`; include dirs into `CFLAGS` | 270 | 1 (transient) | **THROWAWAY DIAGNOSTIC** |
| 9 | + `mkvers.sh` `-I` fix for `windres` | **271** | **0** | build-invocation workaround |
| 10 | + SEH mangled-name fix (`exception.h`, `cygtls.h`) | **271** | **0** | **THROWAWAY DIAGNOSTIC — token swap, NOT a proposed patch; see §6.1** |

**Final compile state: 271 of 310 objects, ZERO `error:` lines, exactly ONE failing
translation unit — `autoload.o`.** (`sigfe.s` also "fails" but it is a generated file, not a TU.)

Rows 6–10 all sit on top of row 5, i.e. they inherit the sibling's three throwaway diagnostics
(`math/fabsl.c`, `cygwin.sc.in`, `MALLOC_ALIGNMENT`). Those remain uncommitted and must be
re-derived properly by whoever owns the port. Do not fold rows 6–10 into a "sealed port"
figure — the sealed port as-is is **row 3: 254/310 with 15 errors**.

## 3. What newly EXISTS that did not exist before

All four of these were previously absent and blocked the link outright.

| Artefact | Size | Format | Note |
|---|---|---|---|
| `newlib/libc.a` | 7,208,392 B | `pe-aarch64-little` | previously "configured but never built" (gap C2) |
| `newlib/libm.a` | 1,632,850 B | `pe-aarch64-little` | ditto |
| `libgcc.a` | 6,677,214 B | `pe-aarch64-little` | built in the gcc build tree, **not** installed into `inst` |
| `libkernel32.a` / `libntdll.a` / `libadvapi32.a` / `libuser32.a` | 1.39 / 1.90 / 0.75 / 0.80 MB | `pe-aarch64-little` | generated with `dlltool -m arm64` from mingw-w64 `lib-common/*.def.in` using mingw-w64's own `-DDEF_ARM64` recipe |
| freestanding C++ headers | 10 files | — | `/root/xc/sysroot-cxx`, **not** `inst` |

Supporting inputs already good: `cygwin.sc` 3,729 B, `msys.def` 40,698 B,
`libcygserver.a` 103,308 B, `libdll.a` 31,160,252 B (248 real objects).
`sigfe.s` is **0 bytes**.

### Closing the libstdc++ gap — the cheapest correct route

A full hosted libstdc++ is **not** required and in fact cannot be configured: its `configure`
dies with `Link tests are not allowed after GCC_NO_EXECUTABLES` because the target libc is
`msys-2.0.dll` itself, which does not yet exist. It is also unnecessary — the entire
`winsup/cygwin` tree includes exactly **one** C++ standard header:

```
$ grep -rho '#include <(new|typeinfo|exception|...)>' winsup/cygwin | sort | uniq -c
      1  #include <new>          # local_includes/cygwin-cxx.h:17
```

`<new>` pulls only `bits/c++config.h`, `bits/exception.h`, `bits/version.h`
(+ `bits/os_defines.h`, `bits/cpu_defines.h`). `version.h` ships pre-generated; `c++config.h`
was produced by replaying the sed recipe in `libstdc++-v3/include/Makefile.am:1364-1426`.
`configure.host` maps `cygwin*` → `os/newlib`; aarch64 has no `cpu_defines.h` so generic applies.
Verified by compiling `#include <new>` to a `pe-aarch64-little` object.

## 4. THE LINK ATTEMPT — exact recipe

The real recipe from `Makefile.am:651-663`, unmodified except for `-L` paths:

```
aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o ../cygserver/libcygserver.a \
  /root/xc/bld/newlib/libm.a /root/xc/bld/newlib/libc.a \
  -L<libgcc> -L<implibs> -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map
```

`libdll.a` accounting: **259 objects intended, 248 present, 11 missing** — the 10
`aarch64/*.S` string/memory routines plus `autoload.o`. Nothing was substituted for them.

Result: `collect2: error: ld returned 1 exit status`. **No output file.**

## 5. THE DELIVERABLE — exactly what is still missing

The failure decomposes into **two components and one small orphan set**. Nothing else.

### 5a. `scripts/gendef` — empty `sigfe.s` (gap B1)

`scripts/gendef:24` is `my $is_x86_64 = $cpu eq 'x86_64';` and **every** emission path is gated
on it, so for `--cpu=aarch64` the script writes a 0-byte `sigfe.s`.

* **990 `cannot export … symbol not defined`**, of which **980 are `_sigfe_*`**
* plus `sigsetjmp` and `siglongjmp` (gendef's `longjmp` sub, also x86-only)
* plus **4 undefined references**: `_sigbe`, `sigdelayed`, `_sigdelayed_end`, `_sigfe_malloc`

Scope of the real work: AArch64 versions of `_sigfe_maybe`, `_sigfe`, `_sigbe`, `sigdelayed`,
`stabilize_sig_stack`, `sigsetjmp`, `setjmp`, `longjmp`, plus the per-export trampoline.
Roughly 500 lines of hand-written x86-64 assembly to port, including the TEB access
(`%gs:8` → `x18`), the `xchg`/`xadd` stack-lock protocol (→ LSE or `ldxr/stxr`), the full
register save/restore in `sigdelayed` (→ AArch64 GPR/NEON, and `fxsave`/`xsave` has no direct
analogue), and the SEH `.seh_*` prologue directives.

**I deliberately did not write this.** Fabricating ~500 lines of unexecutable AArch64 signal
trampoline to turn the link green would satisfy the linker while leaving the runtime broken —
explicitly worse than an honest failure.

### 5b. `autoload.cc` (gap B3)

Fails to assemble: `{standard input}: Error: non-constant expression in ".if" statement` ×12
(the `.if (2b - name) % 8` alignment check in the `LoadDLLfunc` macro is x86-only).
Consequence: **192 undefined references**, and I verified each one against the
`LoadDLLfunc*` entries in `autoload.cc` — **192 of the 196 undefined references are exactly
symbols `autoload.cc` would have defined** (`AuthzAccessCheck`, `CoInitialize`,
`CloseClipboard`, …). The remaining 4 are the `sigfe` ones in §5a.

Full list: `evidence/undef_autoload.txt`.

### 5c. Orphan exports — 8 symbols `cygwin.din` exports with no aarch64 implementation

| Symbol | Where it lives | Verdict |
|---|---|---|
| `fegetprec`, `fesetprec`, `_fe_nomask_env` | `newlib/lib{c,m}/machine/shared_x86/` | **x86-only by construction** — x87 precision control is meaningless on ARM64 |
| `fedisableexcept`, `fegetexcept` | newlib has them for arm/mips, **not aarch64** | aarch64 fenv gap |
| `__alloca` | x86-only alias | x86-only |
| `_ctype_` | `newlib/libc/ctype/ctype_.h` | not emitted under this newlib config |
| `msys_dll_init` | `winsup/cygwin/dcrt0.cc` | msys2-specific; needs checking |

`cygwin.din` exports these unconditionally, so they must be either implemented or excluded for
aarch64.

## 6. NEW port gaps found this session (none previously recorded)

1. **`local_includes/exception.h` and `local_includes/cygtls.h` hard-code a mangled SEH handler
   name, making `.seh_handler` silently dependent on which Windows header set is in use.**

   The `__aarch64__` branches emit `…P25_DISPATCHER_CONTEXT_ARM64` on the stated assumption that
   "on ARM64 winnt.h names the struct `_DISPATCHER_CONTEXT_ARM64`". **That assumption is false for
   released w32api v12.0.0**, which declares `typedef struct _DISPATCHER_CONTEXT
   *PDISPATCHER_CONTEXT;` in *all three* architecture branches — `_DISPATCHER_CONTEXT_ARM64` does
   not appear anywhere in that header. Confirmed by two mutually independent observations:
   reading `winnt.h` directly, **and** `exceptions.o` demonstrably defining
   `…P19_DISPATCHER_CONTEXT`. The `.seh_handler` directive therefore names a symbol that never
   exists, giving 2 undefined references.

   > **DO NOT "FIX" THIS WITH A TOKEN SWAP.** The coordinator checked the CLANGARM64 toolchain's
   > `winnt.h` (405,341 bytes) and it **does** contain `_DISPATCHER_CONTEXT_ARM64` (2 occurrences,
   > alongside 8 plain `struct _DISPATCHER_CONTEXT`). So **both** measurements are correct *for
   > their own header set*: `P25_DISPATCHER_CONTEXT_ARM64` is right against CLANGARM64 headers and
   > `P19_DISPATCHER_CONTEXT` is right against released w32api v12.0.0. Rewriting P25→P19 fixes
   > v12.0.0 and **reintroduces the identical bug in the other direction** under CLANGARM64.
   >
   > **The real defect is that the port hard-codes a mangled name at all.** That makes a
   > correctness property of the SEH machinery depend on a header-version detail, with failure
   > deferred all the way to link time and no diagnostic at the point of error. The correct fix
   > must be **version-robust**: derive the mangled name rather than spell it (e.g. let the
   > compiler emit it, or reference the function symbol so the assembler resolves it), or else
   > condition explicitly on whether `_DISPATCHER_CONTEXT_ARM64` exists in the header set in use.
   > This is owner-authorised work and was **not** implemented here.

   What I did in the scratch tree was exactly the token swap warned against above — applied
   **only** as a throwaway diagnostic to prove the mechanism and to strip these 2 symbols out of
   the undefined list so the residue could be attributed cleanly. It is **not** a proposed patch
   and must not be adopted.

   *(This is the highest-value single finding here after the toolchain work — it is silent, and
   it only surfaces at link time.)*

   **Methodological note, recorded at the coordinator's request.** An earlier programme claim
   treated the linker reporting `…P25_DISPATCHER_CONTEXT_ARM64` as independent corroboration of a
   separate `llvm-nm` mangling analysis. It was **circular**: the linker was echoing back the
   string the sealed port itself hard-codes. A downstream tool repeating a string that an
   upstream artefact hard-coded is not independent confirmation — check whether the second source
   *derived* the value or merely *repeated* it. The finding above avoids this because it rests on
   reading the header, not on reading the error message.

2. **newlib `libm/Makefile.inc:56-58` ties `ld128/` to `HAVE_LIBM_MACHINE_AARCH64`.** Correct for
   ELF aarch64 (128-bit long double), wrong for Cygwin ARM64, which sets `_LDBL_EQ_DBL 1`
   (long double == double, 64-bit — newlib's own configure detects this correctly).

3. **newlib `libc/machine/aarch64/machine/_fpmath.h` describes a 113-bit IEEE quad.** Its mere
   existence makes `HAVE_FPMATH_H` true (`libc/acinclude.m4:66` is a bare `test -r`), which pulls
   in `libm/ld/`, which then `#error "Unsupported long double format"`. 46 errors.

4. **newlib aarch64 assembly is ELF-only.** `libc/machine/aarch64/asmdefs.h` emits
   `.type name,%function`, `.size`, and a `.note.gnu.property` section; `setjmp.S` and
   `rawmemchr.S` emit `.type`/`.size` directly. PE/COFF `as` rejects all of these
   (`junk at end of line, first unrecognized character is 'm'`). Needs a
   `.def/.scl/.type/.endef` branch. Blocks `memchr`, `memcmp`, `setjmp`, `longjmp`, `rawmemchr`.

5. **`scripts/mkvers.sh` harvests only `-I` flags, never `-isystem`.** `AM_CPPFLAGS` passes the
   Cygwin include dir as `-isystem`, so `windres` cannot find `<cygwin/version.h>` and
   `version.cc`/`winver.o` fail. Masked natively by `/usr/include`. Same family as the known
   `$(INCLUDES)` bug.

6. **GCC `libgcc` `extra_parts` for `aarch64-*-cygwin` builds `config/i386/cygming-crtbegin.c`.**
   `make all-target-libgcc` fails on `crtbegin.o`/`crtbeginS.o`. `libgcc.a` itself builds fine
   once target headers are on the include path, and the DLL link is `-nostdlib` so only
   `libgcc.a` is needed — but a complete toolchain will need this resolved.

7. **`devices.cc` is tracked and pre-generated**, yet the rule re-runs `scripts/gendevices`,
   which needs the `shilka` scanner generator (COCOM). A timestamp is enough to avoid it; the
   host-tool dependency is not actually required. This downgrades gap C1.

## 7. What I verified and what I did NOT

**Verified:** every artefact's format via `objdump -f` (all `pe-aarch64-little`, architecture
`aarch64`); the four sysroot preconditions; object counts by direct `find`; that 192 of 196
undefined references are exactly `autoload.cc`'s `LoadDLLfunc*` symbols; that `sigfe.s` is
0 bytes; that `<new>` compiles to an ARM64 PE object.

**NOT verified / NOT claimed:**
* **No DLL exists.** No PE machine type, no size, no sha256, no section layout, no export count,
  no import closure — because there is no image.
* **Nothing has been executed on ARM64.** Nothing in this programme ever has.
* The correctness of any generated code beyond "the assembler and linker accepted it".
* That the 271 compiled objects are *semantically* correct for ARM64 — only that they compile.
* `libm/ld` exclusion is right for `_LDBL_EQ_DBL`, but I did not audit every `long double`
  entry point that newlib would otherwise have supplied.

**Corrected mid-session, disclosed:** my first newlib fix set `libm_machine_dir=''`, which was
too blunt — it also dropped `libm/machine/aarch64/`, losing `s_fma.c`, `sf_fma.c` and the whole
`fenv` family, and `fma`/`fmaf` duly appeared as missing exports. I restored
`libm_machine_dir=aarch64` and excluded only `ld128`. `fma`, `fmaf`, `feclearexcept`,
`fegetround`, `fesetround` are confirmed present in the rebuilt `libm.a`.

## 8. Ordered remaining work to a first link

1. **`scripts/gendef` AArch64 backend** — by far the largest item; unblocks 980 exports + 4 refs.
2. **`autoload.cc` AArch64 thunks** — unblocks 192 refs.
3. The 10 `aarch64/*.S` string routines (newlib's `libc.a` already provides working `memcpy`
   etc., so these are overrides — they may be droppable for a first link).
4. The 8 orphan `cygwin.din` exports: implement or exclude for aarch64.
5. Upstream the 7 findings in §6 — **but note §6.1 needs a version-robust fix, not a token swap**;
   it is silent and link-time-only, so it is easy to "fix" in a way that breaks the other header set.

## 9. Evidence files

`evidence/undef.txt` (196) · `undef_autoload.txt` (192) · `undef_other.txt` (4) ·
`cantexport.txt` (990) · `cannot-export-non-sigfe.txt` (10) · `link-attempt-raw.log` ·
`msys.map.head.txt` · `analysis-final.txt`.
Reproduction scripts `s01`–`s35` are alongside them.
