# Atomic generation: defect, proof lineage, and recovery

This directory preserves the evidence behind
[runtime PR #34](https://github.com/crutkas/msys2-runtime/pull/34) before machine
reformatting. Publication is evidence-only: no new build or qualification.
Qualified source is
[`df7d66f9b1433c50dd7cd234b0d8bd1213418b22`](https://github.com/crutkas/msys2-runtime/tree/df7d66f9b1433c50dd7cd234b0d8bd1213418b22),
whose direct parent is `563662010c2f2072ad90f28713611caabdf70dbb`.

## The guard's own false-success defect

The sealed baseline guard checked previously published output hashes **only
when the input signature matched** its receipt. If an input changed while a
previous output was corrupt, the signature mismatch bypassed that integrity
check and selected ordinary regeneration.

The new adversarial case combined a changed `SIGNAL_GENERATOR` with corrupted
`sigfe.s`. Actual configured `make` returned **0**, silently replacing the
damaged prior output rather than reporting the damaged publication. This is
a false success relative to the required fail-loudly integrity boundary.
The observed case proves this bypass; it does **not** prove that the
replacement assembly itself was bad, nor claim a concurrent-race stress test.
A concurrent input change reaching the same mismatched-signature branch has
the same unchecked-prior-output problem.

The successor validates the existing receipt's **entire output set and hashes
before input-signature comparison**. Changed inputs cannot legitimize
corruption or a missing artifact. Regeneration requires intact prior outputs
or explicit removal of the affected receipt. The six added corrupt/missing
TLS, DEF, and assembly controls require nonzero exit and preservation of all
other artifacts. Valid changed-input regeneration and no-op behavior remain
separately exercised.

## Receipt-last publishing: why the order matters

The real Makefile targets invoke the guard independently of timestamps.
Generators write privately; TLS shape/pairing/alignment, DIN-to-DEF exports,
assembly labels, and public providers are validated before publication.
Each artifact is renamed atomically, and the hash-bound receipt is published
**last**, after all artifact renames succeed.

A receipt is a claim that the named artifacts were successfully published.
Writing it before its artifacts makes that claim prematurely: a crash can
leave a false completion record behind. Receipt-last preserves the previous
receipt until the new artifact set has actually been installed. If interruption
leaves a partially replaced set, its hashes no longer match that prior
receipt; the next invocation rejects it **even when inputs have changed**.
This latter rule is exactly what the baseline guard was missing.

Receipt-last is necessary ordering, not permission to trust a receipt without
checking its artifacts. The guard revalidates hashes every time. Individual
renames are atomic; this is **not** a filesystem-wide multi-file transaction
or a claim of power-loss durability. Unchanged outputs retain timestamps, so
a no-op does not reassemble `sigfe.o`.

## Which proof covered which scenario

| Stage | Evidence | Exact claim |
| --- | --- | --- |
| Historical sealed proposal | `baseline-proposal/`, complete `baseline-proposal.tar.gz`, patch SHA256 `50736b8ccbdbca6df589a5d514db0d55fc27e698a1fab547dc374a612175dbd7` | Original proposal and its original proof preserved unchanged; all 50 original manifest entries retained |
| Fresh byte-exact baseline application | `make-controls-sealed/result.json`, `logs/existing-tls-controls.log` | 16 actual configured-make cases and 40 TLS cases passed; the changed-input-plus-corrupt-output false-0 scenario was **not covered** |
| Newly exposed defect, before fix | `make-controls-receipt-gap-before/result.json` | `reject-changed-input-corrupt-sigfe-s` expected failure but got exit 0; this deliberately records an unsuccessful guard qualification |
| Distinct successor qualification | `make-controls-final-02/result.json`, `logs/existing-tls-controls-final.log` | 26 actual configured-make cases and 40 TLS cases passed, including the newly added integrity boundary and valid changed-input/no-op controls |

**The historical baseline is not retroactively credited with covering the
newly discovered case.** The successor is a larger, distinct qualification
claim. Original receipt timestamps, commands, outputs, and source identities
remain unchanged in the archives. Publication commits do not constitute new
qualification.

## Related silent-corruption hazard: historical TLS generator

The toolchain owner `5b01b4e5-41d0-4535-bc71-1133839af6e1` tracks the related
generator-selection hazard in
[crutkas/msys2-woarm64-build#11](https://github.com/crutkas/msys2-woarm64-build/pull/11).
The historical `gentls_offsets` parser accepts `.long`, while ARM64 GCC emits
`.word`. The old parser can exit cleanly while replacing a valid layout with
a **56-byte textual file containing two zero offsets**; it is not 56 NUL
bytes. This and the receipt bypass are both failures where a clean process
exit conceals an integrity violation.

Known-good TLS is **1,822 bytes / 59 entries**, SHA256
`49ac682b8f5ed4295d03abc2dab5953fc472684d42eb0b87d779057942b23566`.
Historical parser SHA256 is
`b5ad924f820df3def1b9d19671086ee5c8a92c1e0918a81c9262649e5089de18`;
its 56-byte output SHA256 is
`95e965fc1beea943c3eadc2cd941c34b01a3151968a0ffbe6917b354d2f0d8a5`.
The successor case set explicitly asserts those identities. The old parser
is unmodified; the adapter changes only its basename output convention.
Actual make rejects its invalid output and preserves the good artifacts.
The real stale signal generator is also exercised (SHA256
`74f502440493f2406435006bce46674adcfda59b269f0da98586a7b87e0127fb`).
Current qualified `gentls_offsets` already handles `.word` and `.long` and
is intentionally unchanged by PR #34.

## Payload SHA256 inventory

| File | Bytes | SHA256 |
| --- | ---: | --- |
| `baseline-proposal.tar.gz` | 74523 | `19d273f86f14b9b3beb5debaa9f1309683f79bff242e8bf78ab363632d8d85c5` |
| `baseline-proposal/build-hardening-proposal-01.manifest.json` | 8133 | `106fa206a3e37e89de416512e9d6080c642d2dd7ce9daa46c84fa3c78b77c085` |
| `baseline-proposal/handoff.json` | 3080 | `f8429c52a5599f4f1e4601358b564f3dd3d2ee2774dce2ee91760477726f0fed` |
| `baseline-proposal/runtime-generation-guards.patch` | 21873 | `50736b8ccbdbca6df589a5d514db0d55fc27e698a1fab547dc374a612175dbd7` |
| `handoff.json` | 4094 | `5fd646b577eec81083f31fe1e532b0387f0e02d509ec457c3f8b1fce306c078b` |
| `logs/existing-tls-controls-final.log` | 1221 | `7d1a3d7b09523ba3c8ed2b166c7f99bde5e953be4afaad097a9bde284cc2f806` |
| `logs/existing-tls-controls.log` | 1221 | `7d1a3d7b09523ba3c8ed2b166c7f99bde5e953be4afaad097a9bde284cc2f806` |
| `make-controls-final-02/result.json` | 32676 | `f045f2b371282247c90748237b1631d0df7bc86bde947ca4545bb4490527aef9` |
| `make-controls-receipt-gap-before/result.json` | 17634 | `2e37d0d89e90d053b0ecb8ee98e6acecfe496740a1102ba6cc76c020eaf2c296` |
| `make-controls-sealed/result.json` | 20111 | `36c169ee34291d4b3961fcbf054cca3438e5450f101f9ae6ed2737b78580463c` |
| `proof.tar.gz` | 269076 | `2abaa10780ef6e287a2bd90f424d599771aa7db1d72faf354ed81af7557f1c84` |
| `runtime-generation-application-3fc49c8a.manifest.json` | 30107 | `8fdf475ac76350ed75a791ace5bf9cfefacf52e739b746e3cf41ab0f8f895776` |

The manifests inside the archives give per-file SHA256 and size for all
**50 baseline files** and **170 application/successor files**. The local
`.gitattributes` applies `-text` to retain exact bytes on checkout.

## Original absolute paths and portable recovery

Original baseline: `C:\agtc-signal-01\build-hardening-proposal-01`, with sibling
`C:\agtc-signal-01\build-hardening-proposal-01.manifest.json`.
Original application proof:
`C:\agtc-signal-01\runtime-generation-application-3fc49c8a`, with sibling
`C:\agtc-signal-01\runtime-generation-application-3fc49c8a.manifest.json`.
Owned source/build/prefix root:
`/root/arm64-vnext-20260905/runtime/atomic-generation-20260911-3fc49c8a`.
Read-only copied baseline originated at
`/root/arm64-vnext-20260905/toolchain/epochs/generation-hardening-20260911-01`.
Historical fixtures came from
`C:\agtc-signal-01\baseline-source\winsup\cygwin\scripts\gendef` and
`C:\agtc-signal-01\old-long-only-gentls_offsets`.

Download this directory at an exact publication commit. Check the archive
SHA256 values above, then extract into a new evidence-only directory with
`tar -xzf .\proof.tar.gz -C <destination>` and
`tar -xzf .\baseline-proposal.tar.gz -C <destination>`. Each archive restores
its original root directory and sibling manifest. Verify every manifest
entry's size and SHA256 before using it.

Executable PowerShell recovery instructions for the 170-file application
archive are also preserved at this immutable
[earlier evidence-publication README](https://github.com/crutkas/msys2-runtime/blob/fb627b685141eea8bd7e7813837e4b21c754dc35/winsup/testsuite/build/evidence/runtime-generation-20260911/README.md).
Original absolute paths are provenance, not dependencies for reading the
proof. Neither archive is a full compiler/prefix/build backup. Do not execute
archived fixtures in place or rewrite the sealed records. Recover full source
from the qualified source commit; future builds require a new owned,
configured environment and separately identified qualification.
