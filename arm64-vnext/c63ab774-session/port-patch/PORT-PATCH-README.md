# ARM64 port — preserved as a patch, NOT applied to this branch

**Status: artefact only. The user's decision on committing the ARM64 port
itself is still open, and this does not pre-empt it.**

Earlier in this programme the user was asked whether to commit all verified
ARM64 port work and **declined**. This directory therefore preserves the port
as a *patch and a set of standalone files*, in the same manner as
`arm64-fork-and-argv-fixes.patch`, so that a machine reformat does not destroy
it. Nothing here is applied to `winsup/` on this branch.

## Why this exists

The three defect fixes and the evidence were committed earlier and verified on
the remote. **The port itself was not**, and it lived only in the WSL tree at
`/root/xc/w-link`, which is not recoverable. This is the largest single body of
work in the programme — the hand-ported assembly layer — and it was within
minutes of being lost.

## Contents

| path | what it is |
|---|---|
| `arm64-port.patch` | 2458 lines, 39 files, against base `d890a845e` |
| `generators/gendef` | 978 lines — the AArch64 backend that emits the `sigfe`/`sigbe`/`sigdelayed` trampolines |
| `generators/mkimport` | 120 lines — the AArch64 import thunk (`adrp x16` / `ldr x16` / `br x16`) |
| `generators/autoload.cc` | 840 lines — the AArch64 autoload thunks, a redesign rather than a port |
| `generators/cygwin.sc.in` | 206 lines — linker script: `OUTPUT_FORMAT(pei-aarch64-little)`, ctor/dtor markers, `.xdata` guard, `.idata` alignment |
| `generated-sigfe.s` | 294 KB — the actual generated assembly, 3926 `_sigfe` references. Proves what the generator produces. |
| `untracked/math-aarch64/` | 3 files not tracked in git, including `longdouble.c`, without which the tree fails at link |

The four `generators/` files are captured **verbatim, not as diff hunks**.
They are standalone programs; a diff against a base that has moved is useless,
and `gendef` in particular is the thing that produces 989 trampolines.

## Deliberately NOT in the patch

`winsup/cygwin/dcrt0.cc` and `winsup/cygwin/hookapi.cc` are excluded. Those
carry the three defect fixes and the leak close, which are **already committed
as source** on this branch (`61f6b35f`, `7ab09ec8`, `d9369d0b`, `6397acaa`).
Including them here would create a conflicting duplicate.

Autotools regenerables (`compile`, `config.guess`, `config.sub`, `depcomp`,
`install-sh`, `missing`, `mkinstalldirs`, `test-driver`) are excluded as noise.

## Which tree this came from, and why it matters

**`/root/xc/w-link` — this is the tree to trust.** Other trees used during the
programme (`w-autoload`, `w-gendef`, `w-orphans`, `w-compose`) were recorded as
contaminated with a stale `tpidr_el0` TEB read, which is wrong on Windows on
Arm: the TEB is in `x18`, and `tpidr_el0` reads 0.

Verified before capture: `generators/gendef` and `generators/autoload.cc`
contain **zero** occurrences of `tpidr_el0`. The single occurrence in
`arm64-port.patch` is inside an explanatory comment stating why `tpidr_el0` is
*not* used; the code reads `mov %0, x18`.

## What this patch has NOT been through

* It has **not** been applied to a clean tree and rebuilt from scratch. It is a
  capture of a working tree that produced a runtime passing 12 rung tests.
* It is against base `d890a845e`. If that base moves, hunks may need rework —
  which is exactly why the four generator files are also stored whole.
* The port contains at least one known latent defect that was found but not
  fixed: `scripts/gentls_offsets` greps for `\.long` while AArch64 emits
  `.word` for the `const uint32_t` it generates, so regenerating `tlsoffsets`
  silently produces a 56-byte file of zeros **and exits 0**. Back that file up
  before running `make`. See `../evidence/tlsoffsets-hazard-demonstrated.txt`.
