# ARM64 vNext — preserved assets, and the three ways to silently destroy them

> **INPUT SOURCE IDENTITIES — clone these SHAs, NOT the branch.** Every clone is
> `--depth 1 --branch woarm64`; if a branch advances, a replay silently builds different
> sources with no signal.
> `gcc-src` `5688a17320e775944bbe795010ebe7e89fc7a628` (VERIFIED) ·
> `runtime` `d890a845e992638a6f09560efacc26d15b3ffe6a` (VERIFIED) ·
> `mingw-w64` `819a6ec2ea87c19814b287e21d65e0dc7f05abba` (VERIFIED, tag `v12.0.0` exactly) ·
> `binutils` `44335833f8f734f978211b082b15aed14efcf958` (**PRESUMED** — built tree lost;
> corroborated only in that the installed `ld`/`as` report `2.44.50.20250131` and
> `bfd/version.h` at that commit carries `BFD_VERSION_DATE 20250131`, which narrows to a
> one-day window rather than pinning a SHA). Full detail in `toolchain-recipe/PROVENANCE.md`.
> The `file:///mnt/c/...` clone paths are a portability inconvenience, not a data-loss risk:
> both repos are pushed to GitHub with local tips matching origin — substitute the remote URL.
> ## CRITICAL — THREE-SESSION DEPENDENCY, AND ITS RESOLUTION
>
> **This evidence directory preserves the SOURCE state completely, but the TOOLCHAIN is a
> PRECONDITION it does not contain.** `/root/xc/inst` is listed below under preserved assets,
> which reads like custody but confers none: the compiler exists **only as live WSL filesystem
> state** — in no diff, no repo, no archive. **LISTING IS NOT PRESERVING.**
>
> Rebuilding from this directory alone depends on THREE sessions:
> `fca94a35` (binutils + GCC cross), `1e64365a` (w32api, newlib, C++ cross, winsup config),
> and `c63ab774` (this directory: patch, untracked file, link evidence).
>
> **RESOLVED:** the toolchain build recipe has been consolidated into
> **`toolchain-recipe/`** in this directory, as `from-fca94a35/` and `from-1e64365a/` so
> provenance survives the copy. See **`toolchain-recipe/PROVENANCE.md`** for each file's
> origin session, original path and SHA-256.
>
> **`toolchain-recipe/from-1e64365a/gcc-cxx.sh` builds the C++ cross compiler** into
> `/root/xc/inst` (`--enable-languages=c,c++`, `make all-gcc`).
>
> **LIMITATION: that these scripts replay cleanly is UNTESTED.** Consolidation makes the
> recipe FINDABLE, not VERIFIED. A rebuild to prove replay is an owner decision.
>
> **UNTRACKED FILES:** `evidence/untracked/` here is the BYTE-EXACT source
> (`longdouble.c` 3,368 B, LF, `aaf9785b...`, byte-identical to the live tree). The bundle
> named `arm64-port-backup-2026-09-02` is content-equivalent but **CRLF-converted**
> (3,520 B). Verify against the normalised hash, never a raw byte count.
>
> **APPLICABILITY IS NOT CORRECTNESS:** the patch provably applies (43/43 pre-images,
> forward and reverse apply PASS) but is **known to contain wrong content** — the P19
> `_DISPATCHER_CONTEXT` token swap and two contradictory comments.
**Session:** `c63ab774-a023-4e57-9bc4-53f727507ada` · 2026-09-02 · preservation record.

The build state described in `RESULT.md` exists **only as live filesystem state** in the WSL
guest. This file exists so the reproduction recipe survives the loss of that guest or of this
session. Nothing here implements anything or modifies any asset.

---

## THE THREE FOOT-GUNS

All three fail **with no error message**, and all three produce symptoms that appear far from the
cause. That is what makes them dangerous: each looks like an ARM64 port defect and is not.

### 1. Reinstalling w32api headers reverts the `_cygwin.h` fix

* **What breaks it:** running `mingw-w64-headers`' `make install` again, or refreshing
  `/root/xc/inst/aarch64-pc-cygwin/include/w32api` from unpatched mingw-w64 sources.
* **Why it is silent:** the header installs cleanly. Nothing warns. But `_cygwin.h` reverts to
  `#ifdef __x86_64__` around `#define _WIN64`, so on aarch64 `_WIN64` is never defined,
  `basetsd.h` takes its **32-bit** branch, and `UINT_PTR` / `INT_PTR` / `LONG_PTR` / `ULONG_PTR` /
  `SOCKET` / `DWORD_PTR` all silently narrow to 32 bits.
* **RECOGNITION SYMPTOM:** object count **collapses from ~271 toward ~116**, with a flood of
  pointer-truncation errors that look like ARM64 port defects. If the count drops toward 116,
  **check `_cygwin.h` FIRST** before investigating anything else.
* **Check:**
  ```
  grep '_WIN64' -B1 /root/xc/inst/aarch64-pc-cygwin/include/w32api/_cygwin.h
  # MUST read:  #if defined(__x86_64__) || defined(__aarch64__)
  ```
* **Related:** the headers must stay **released w32api v12.0.0**. mingw-w64 *master* commit
  `8c4baed92` moved `mbstate_t` into `corecrt.h` behind a guard with no arch and no `__CYGWIN__`
  component; it collides with newlib on *every* Cygwin target including x86_64 (145 errors) and is
  in no release tag. Do **not** paper over it with a `corecrt.h` shim — pin v12.0.0.
  ```
  grep -c mbstate_t /root/xc/inst/aarch64-pc-cygwin/include/w32api/corecrt.h   # MUST be 0
  ```

### 2. Re-running newlib's `configure` regenerates the 12 `ld128` entries

* **What breaks it:** any `configure` / `config.status` run in `/root/xc/bld/newlib` — including
  the automatic re-run `make` triggers if a `Makefile.in` or `configure` timestamp changes.
* **Why it is silent:** `configure` succeeds. But the generated `Makefile` is rebuilt from
  `Makefile.in`, discarding the **12 hand-commented `libm/ld128/libm_a-*.$(OBJEXT)` entries**, so
  the 128-bit long-double directory is compiled again.
* **Root cause (a real newlib bug):** `libm/Makefile.inc:56-58` pulls `ld128/` in whenever
  `HAVE_LIBM_MACHINE_AARCH64` is true. Correct for ELF aarch64 (113-bit quad), **wrong** for
  Cygwin ARM64, which sets `_LDBL_EQ_DBL 1` (long double == double, 64-bit) — as newlib's own
  configure correctly detects.
* **RECOGNITION SYMPTOM:** `#error "Unsupported long double format"` from `libm/ld128/` or
  `libm/ld/`, plus `'BIAS' undeclared`, `'LDBL_NBIT' undeclared`, `storage size of 'u' isn't
  known`. 46 errors, **all confined to `libm/`**. `libc.a` is unaffected.
* **Also required at configure time:** `libc/machine/aarch64/machine/_fpmath.h` must be
  temporarily moved aside, because `libc/acinclude.m4:66` sets `HAVE_FPMATH_H` from a bare
  `test -r` on it, which drags in `libm/ld/`. Restore it immediately after `configure` returns.
* **Do NOT** "fix" this by setting `libm_machine_dir=` empty. That is too blunt: it also drops
  `libm/machine/aarch64/`, losing `s_fma.c`, `sf_fma.c` and the whole `fenv` family.
  **Symptom of that mistake:** `fma` and `fmaf` appear as `cannot export ... symbol not defined`
  at link time. (I made exactly this error and corrected it; see `RESULT.md` §7.)

### 3. Losing the uncommitted state of `/root/xc/runtime`

* **What breaks it:** `git checkout`, `git stash`, `git clean`, `git reset --hard`, or deleting
  the WSL guest. **Nothing is committed.** HEAD is `d890a845e992638a6f09560efacc26d15b3ffe6a`
  and every port edit — the sealed ARM64 port plus all diagnostics — is working-tree-only.
* **Why it is silent:** the tree still builds; it just builds the *unported* source, so failures
  reappear that were previously "fixed".
* **RECOGNITION SYMPTOM:** `#error unimplemented for this target` from `cygwin.sc.in`,
  `winsup/configure.ac` rejecting `aarch64`, or `math/fabsl.c` warnings returning.
* **Captured here:** `runtime-git-status.txt` (44 entries: 43 modified, 1 untracked),
  `runtime-uncommitted.diff` (43 files, 1693 insertions, 760 deletions — **verified**, see below),
  and `untracked/winsup/cygwin/math/aarch64/longdouble.c` (3368 B).
  **That untracked file is NOT in the sealed port patch** and must be restored separately, or the
  tree fails at link.

---

## THE STRUCTURAL FINDING — read this before anything else

Attribute the reproduction diff before reading its size:

| | files | insertions | deletions |
|---|---|---|---|
| **real port work** | 35 | 846 | 53 |
| autotools regeneration noise | 8 | 847 | 707 |
| raw total | 43 | 1693 | 760 |

`config.guess` alone is +645/−591. Roughly **half the diff is not port work at all**.

Now compare against the sealed ARM64 port: **29 files / 785 insertions / 51 deletions**.
Real port work in this tree is 35 files / 846 insertions — a delta of only about
**6 files and 61 insertions** over the sealed port.

> **Therefore the 254 → 271 object gain came almost entirely from TOOLCHAIN AND HEADER work
> — w32api v12.0.0, the `_WIN64` fix, `libgcc.a`, newlib, the freestanding C++ headers — and
> almost not at all from writing more port code.**
>
> **THE ARM64 PORT WAS ALREADY NEARLY COMPLETE; WHAT WAS MISSING WAS THE TOOLCHAIN AROUND IT.**
> `gendef` and `autoload` remain genuine gaps, but they are not evidence of a thin port — they
> are two specific holes in something substantially built.

That is a materially different picture from "271 of 310 objects and a long way to go", and it is
the sentence a successor most needs to read first.

---

## Diagnostic edits carrying MISLEADING or CONTRADICTORY comments

**These comments are NOT authoritative. They must be DELETED by whoever implements the
version-robust SEH fix.** They are left in place deliberately: they are the tree the preserved
binaries were built from, and they are useful evidence of exactly how this class of error
propagates. Do not "tidy" them in isolation — remove them as part of the real fix.

The general lesson, recorded because it generalises far beyond this case:

> **A scratch edit with a confident universal comment is more dangerous than an uncommented one.**
> An unexplained hack gets caught in review; a hack with an authoritative comment gets *ratified*
> by it. When making a diagnostic edit, mark it **in the code** — a `DIAGNOSTIC ONLY, DO NOT SHIP`
> line beats any amount of correctness in the surrounding prose.

| File : line | What it says | Why it is wrong |
|---|---|---|
| `winsup/cygwin/local_includes/exception.h:13-18` | "the struct is plain `_DISPATCHER_CONTEXT` **on every architecture** — there is no `_DISPATCHER_CONTEXT_ARM64` — hence … `P19_DISPATCHER_CONTEXT`, identical to x86_64" | States as **universal** something true only of **w32api v12.0.0**. This is the original port bug reintroduced in the opposite direction, now carrying a confident justification that would survive review. Written by me during the row-10 diagnostic. |
| `winsup/cygwin/local_includes/cygtls.h:365` | "on ARM64 winnt.h names the struct `_DISPATCHER_CONTEXT_ARM64`" | **Contradicts the code in its own file**: lines 369 and 375 both emit `P19_DISPATCHER_CONTEXT`. My `sed` changed the token and left the comment. Comment and code now disagree. |

Audited and found **clean** (no misleading prose): `winsup/cygwin/thread.cc:1978`
(`yield` under a plain `#ifdef __aarch64__`, no claim made); the sibling's three diagnostics
`math/fabsl.c:15`, `cygwin.sc.in:8-10`, `cygmalloc.h:24` / `newlib/libc/include/sys/config.h:7`
(all bare `#ifdef`/`#elif` with no explanatory prose); and my newlib edits
`asmdefs.h:66`, `setjmp.S`, `rawmemchr.S`, which carry the searchable markers
`__aarch64_pe_asmdefs__` / `__pe_asm_fixed__` and describe only PE/COFF directive syntax —
a statement that is actually true and not version-dependent.

## Header-set dependence — the evidence behind "derive, don't hard-code"

All four header sets below were **measured directly here** (word-boundary matching, so
`_DISPATCHER_CONTEXT_ARM64EC` is never miscounted as `_DISPATCHER_CONTEXT_ARM64`).

| header set | size | sha256 (16) | struct **tag** under an ARM64 target | mangles to |
|---|---|---|---|---|
| build sysroot, w32api **v12.0.0** | 387,345 B | `83a7868c486f3ccb` | `_DISPATCHER_CONTEXT` (literal) | **P19** |
| `mingw-w64-tools/widl` | 264,325 B | `7577cc2cd882d2cf` | `_DISPATCHER_CONTEXT` (macro-renamed) | **P19** |
| **Microsoft Windows SDK 10.0.26100.0** `um\winnt.h` | 876,232 B | `8693f0ad4ada355c` | `_DISPATCHER_CONTEXT` (macro-renamed) | **P19** |
| CLANGARM64 (mingw-w64 fork, session `aabca41f`) | 405,341 B | `51f9430b73aa131e` | `_DISPATCHER_CONTEXT_ARM64` (no rename) | **P25** |

### The mechanism — and a correction to an earlier programme inference

Three of the four headers perform the **same macro-rename trick**, so that on an ARM64 target the
ARM64 dispatcher context simply *is* the dispatcher context:

```c
/* Microsoft SDK 10.0.26100.0, um\winnt.h */
#if defined(_ARM64_) || defined(_CHPE_X86_ARM64_)      /* 7097 */
#pragma push_macro("_DISPATCHER_CONTEXT_ARM64")        /* 7099 */
#undef  _DISPATCHER_CONTEXT_ARM64                      /* 7100 */
#define _DISPATCHER_CONTEXT_ARM64 _DISPATCHER_CONTEXT  /* 7101  <-- renames the TAG */
#endif
...
typedef struct _DISPATCHER_CONTEXT_ARM64 { ... }       /* 7130  <-- expands to _DISPATCHER_CONTEXT */
            DISPATCHER_CONTEXT_ARM64, *PDISPATCHER_CONTEXT_ARM64;
#if defined(_ARM64_) || defined(_CHPE_X86_ARM64_)      /* 7145 */
typedef DISPATCHER_CONTEXT_ARM64 DISPATCHER_CONTEXT, *PDISPATCHER_CONTEXT;
#undef _DISPATCHER_CONTEXT_ARM64                       /* 7149 */
#pragma pop_macro("_DISPATCHER_CONTEXT_ARM64")         /* 7150 */
#endif
```
`mingw-w64-tools/widl` does the same under `__aarch64__` (rename at 1963, struct at 2005,
`#undef` at 2114, alias at 2115). w32api v12.0.0 needs no rename — its tag is already plain.

**CLANGARM64 is the odd one out.** It defines the struct at 2480 with the tag
`_DISPATCHER_CONTEXT_ARM64` *unrenamed*, then merely aliases the typedef at 2495-2497 under
`#if defined(_ARM64_)`. Because C++ mangles from the **struct tag**, not the typedef name
(standard Itanium ABI), `PDISPATCHER_CONTEXT` there mangles as `P25_DISPATCHER_CONTEXT_ARM64`.

> **CORRECTION TO AN EARLIER PROGRAMME CLAIM.** It was stated that "version-robustness is the
> behaviour of the *authoritative* Microsoft header, not a fork quirk", with the implication that
> Microsoft's SDK drives the **P25** form. **The measurement says the opposite.** Under `_ARM64_`
> the Microsoft SDK macro-renames the tag to `_DISPATCHER_CONTEXT` and therefore yields **P19** —
> the same as w32api v12.0.0 and as widl. **Only the CLANGARM64 mingw-w64 fork yields P25**, and
> it does so precisely by *omitting* the rename that the other three perform. So P25 is the fork
> behaviour and P19 is the Microsoft behaviour, which is the reverse of the earlier reading.

**This makes the case for deriving the name stronger, not weaker.** The tag is not merely
header-*set*-dependent — within a single Microsoft header it is **preprocessor-state-dependent**,
flipping between `_DISPATCHER_CONTEXT_ARM64` and `_DISPATCHER_CONTEXT` across a `push_macro` /
`pop_macro` window depending on whether `_ARM64_` is defined. Two variants of the *same project*
(mingw-w64: widl vs CLANGARM64) already disagree. **Any hard-coded token is wrong for some
supported configuration.** The fix must let the compiler emit the mangled name, or reference the
function symbol so the assembler resolves it.

**Honesty boundary:** the four rows above are direct measurements of header text; the "mangles to"
column is *derived* by applying the Itanium C++ ABI tag-mangling rule to that text. I did **not**
compile against the Microsoft SDK or the CLANGARM64 headers to observe the emitted symbol. The one
row that *is* empirically confirmed is w32api v12.0.0: `exceptions.o` in this build demonstrably
defines `…P19_DISPATCHER_CONTEXT`.

---

## Restoring the reproduction state from this directory

```
git -C <clone> checkout d890a845e992638a6f09560efacc26d15b3ffe6a
git -C <clone> apply evidence/runtime-uncommitted.diff
cp -r evidence/untracked/* <clone>/
```
Then follow `RESULT.md` §4 for the link recipe. Note the build invocation needs
`INCLUDES="$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)"`, the `-I` restatement of the
`-isystem` dirs in `CFLAGS` (for `mkvers.sh`/`windres`), and
`CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1`.

### ⚠ `longdouble.c` — LINE-ENDING VARIANCE ACROSS COPIES. Verify by NORMALISED hash.

The `cp -r untracked/*` step above is where this bites. Three copies of
`winsup/cygwin/math/aarch64/longdouble.c` exist and **their byte counts differ**:

| copy | bytes | line endings | raw sha256 | LF-normalised sha256 |
|---|---|---|---|---|
| **this evidence dir** (`untracked/…`) | **3,368** | **152 bare LF** | `aaf9785b057e5527e717c294a76f40a755ac0cd15735856cc7b2d4af827ff80b` | `aaf9785b…` |
| live tree `/root/xc/runtime/…` | 3,368 | 152 bare LF | `aaf9785b…` | `aaf9785b…` |
| sealed backup, session `724ee2e9` | 3,520 | 152 **CRLF** | `52d89409e33f27e195065d1cf0911e4d2c3052a8f8f0f6f2df9bce9181cb5c26` | `aaf9785b…` |
| coordinator chat backup | 3,520 | 152 CRLF | `52d89409…` | `aaf9785b…` |

*(First three rows measured directly here; the fourth is the coordinator's own verification of
their copy.)*

**The content is identical.** The 152-byte delta is exactly one byte per line — the CRLF
signature, **not corruption**.

* **VERIFY BY THE NORMALISED HASH `aaf9785b…`, NEVER BY RAW BYTE COUNT.**
  `tr -d '\r' < longdouble.c | sha256sum`
* **Prefer the copy in this directory** for a WSL/LF build tree — it is already LF.
* **If you restore from either 3,520-byte copy, normalise CRLF → LF first.** The WSL build tree
  is LF throughout; injecting CRLF into a file the build expects as LF is the same failure class
  that once produced a `/usr/bin/perl` + CR shebang and broke this programme's build.

Two failure modes this table prevents: (1) a restorer fetching from another copy, checking it
against "3,368 bytes" and wrongly declaring corruption; (2) silently importing CRLF into the
build tree.

**Why this file needs separate handling at all:** the sealed `arm64-port.patch` **does not create
it**. Verified here — the patch has no `diff --git` header for `longdouble.c`; its only mention is
at line 187, a `math/aarch64/longdouble.c` entry added to `Makefile.am`. So applying the sealed
patch produces a `Makefile.am` that references a file which does not exist, and the tree fails at
link. *(The same check independently confirms the sealed port's shape: **29 files, 785 insertions,
51 deletions**.)*

### Patch applicability was verified — but note what that does and does not prove

The pre-image blob check on `runtime-uncommitted.diff` passes: 43 `index` headers, every
pre-image blob matching `git rev-parse d890a845:<path>`, **zero mismatches**. The recovery recipe
is provably sound in the sense that the patch will apply cleanly to the stated base commit.

> **Caveat:** pre-image matching proves **APPLICABILITY, not POST-IMAGE CORRECTNESS.** It confirms
> the patch targets the right base and is internally intact. It says nothing about whether the
> resulting code is right — and this diff is *known* to contain wrong content, e.g. the
> `P19_DISPATCHER_CONTEXT` token swap and its misleading comments (see above). It complements
> review; it does not replace it.

## Diff integrity verification

The diff was written **directly** with `git diff HEAD --output=<file>` — never through a shell
pipeline, because a sibling session's patch backup was silently corrupted that way earlier today.
It was then verified by independently recounting the written file:

| | files | insertions | deletions |
|---|---|---|---|
| `git diff HEAD --shortstat` | 43 | 1693 | 760 |
| recount of `runtime-uncommitted.diff` | 43 | 1693 | 760 |

`diff --git` headers counted directly; insertion/deletion counts include bare `+` / `-` lines
(inserted/removed blank lines), which a naive `grep '^+'` undercounts. **PASS.**

> **Validation rule worth keeping:** a naive `grep -c '^+'` **undercounts** a diff, because an
> inserted blank line is a bare `+`. Without splitting `^+[^+]` from `-x '+'` the totals mismatch
> and an intact file looks corrupted. **A false corruption signal is as damaging as missing a real
> one** — it sends someone rebuilding a perfectly good artifact.

After the provenance header was prepended, both checks were re-run: counts still 43/1693/760, and
`git apply --reverse --check` **passes** against the modified tree, proving the header did not
break parseability. (`--check` is read-only; `/root/xc` was not modified.)

Note: this is a Linux-side clone with no CRLF conversion, so `-c core.autocrlf=false` is not
applicable here — that precaution belongs to the Windows-side worktrees.

## Preserved assets (do not modify — owner-authorised only)

`/root/xc/inst` (the programme's only working `aarch64-pc-cygwin` cross: g++ 15.0.1 20250131,
GNU ld 2.44.50.20250131) · `/root/xc/bld/newlib/{libc.a,libm.a}` ·
`/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc/libgcc.a` · `/root/xc/implibs/lib/*.a` ·
`/root/xc/sysroot-cxx` · `/root/xc/bld/winsup/cygwin/{cygwin.sc,msys.def,libdll.a,msysdll.a}`.

**Sizes AND SHA-256 for all of these live in `built-artifact-hashes.txt` in this directory**
(generating script: `capture-artifact-hashes.sh`). `RESULT.md` carries **sizes only — it contains
no sha256 values at all**. `SHA256SUMS` seals *this directory*; it does not cover `/root/xc`.

Two results in that manifest matter more than the hashes themselves:

* **Every size independently corroborates the `RESULT.md` table** — 7,208,392 / 1,632,850 /
  6,677,214 / 31,160,252 / 3,729 / 40,698 and the rest all match exactly. That table was
  previously **single-sourced**; it is now confirmed by a separate capture.
* **`sigfe.s` is cryptographically confirmed empty.**
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` is the SHA-256 of the empty
  string (re-derived here with `printf '' | sha256sum`). The 0-byte `gendef` finding — on which
  the **entire 990-export analysis rests** — no longer depends on trusting an `ls` listing.
* Newly captured, and never previously recorded: **the identity of the four toolchain drivers
  that built everything** — `g++` 17,261,408 B `18d0b448…`, `gcc` 17,241,008 B `dd4d9346…`,
  `ld` 10,927,080 B `c142f1f7…`, `as` 11,684,704 B `f649ae32…`. Until now the compiler that
  produced every artifact above had no recorded identity.

### ⚠ ECHO TO A TRANSCRIPT IS NOT PERSISTENCE

This manifest exists because of a failure worth recording as a standing rule. `s36-hashes.sh`
computed all twelve artifact hashes **correctly** — and printed them. They reached the session
transcript and **never reached disk**. Only sizes were persisted, and `ASSETS-README.md` then
claimed for several revisions that "sizes and SHA-256 for all of these are in the report", which
was **false**: `RESULT.md` contained zero sha256 strings.

It survived every review precisely because nothing was *wrong* — the script was right, the
analysis was right, the values were right. Only the durability step was missing, and a missing
step leaves no artifact to inspect.

Every load-bearing value this programme has lost failed the same way — `GCC_HEAD=`,
`BINUTILS_HEAD=`, and these hashes were each computed correctly and then **printed rather than
written**.

> **RULE: if a value matters, redirect it to a file in the same command that produces it.**
> Not a later step, not a follow-up call — the same command. And when a document claims data
> lives somewhere, open that somewhere and confirm it does.

**No `msys-2.0.dll` exists.** Nothing in this programme has ever been executed on ARM64.
