# Runtime generation qualification: portable evidence

This is an evidence-only publication of the completed September 11, 2026
qualification for [runtime PR #34](https://github.com/crutkas/msys2-runtime/pull/34).
No new qualification, runtime build, source change, or merge was performed to
publish this directory.

Qualified source commit:
[`df7d66f9b1433c50dd7cd234b0d8bd1213418b22`](https://github.com/crutkas/msys2-runtime/tree/df7d66f9b1433c50dd7cd234b0d8bd1213418b22).
Its direct parent is PR #33's
`563662010c2f2072ad90f28713611caabdf70dbb`. The later evidence-publication
commit does not change those source identities or retroactively qualify a
different integration base.

## Contents and seals

`proof.tar.gz` contains all **170 original evidence files**, including source
snapshots, the successor patch, generated artifacts, historical generator
inputs, fixtures, configure logs, every control's stdout/stderr, and the
original `handoff.json`. It also contains the original sibling manifest.
Readable copies of the handoff, manifest, three result files, and TLS logs are
provided alongside the archive; their bytes are unchanged.

| File | SHA256 |
| --- | --- |
| `proof.tar.gz` (269,076 bytes) | `2abaa10780ef6e287a2bd90f424d599771aa7db1d72faf354ed81af7557f1c84` |
| `handoff.json` | `5fd646b577eec81083f31fe1e532b0387f0e02d509ec457c3f8b1fce306c078b` |
| `runtime-generation-application-3fc49c8a.manifest.json` | `8fdf475ac76350ed75a791ace5bf9cfefacf52e739b746e3cf41ab0f8f895776` |
| `make-controls-sealed/result.json` | `36c169ee34291d4b3961fcbf054cca3438e5450f101f9ae6ed2737b78580463c` |
| `make-controls-receipt-gap-before/result.json` | `2e37d0d89e90d053b0ecb8ee98e6acecfe496740a1102ba6cc76c020eaf2c296` |
| `make-controls-final-02/result.json` | `f045f2b371282247c90748237b1631d0df7bc86bde947ca4545bb4490527aef9` |
| `logs/existing-tls-controls-final.log` | `7d1a3d7b09523ba3c8ed2b166c7f99bde5e953be4afaad097a9bde284cc2f806` |

## Qualification lineage

1. The sealed proposal patch
   `50736b8ccbdbca6df589a5d514db0d55fc27e698a1fab547dc374a612175dbd7`
   was applied byte-exact after verifying all 50 proposal inputs. Fresh
   **16 actual configured-make controls and 40 existing TLS controls passed**.
   Those 16 controls did **not** cover the subsequently discovered receipt gap.
2. A new adversarial case selected a changed signal generator and corrupted
   `sigfe.s`. Actual configured make incorrectly exited **0** with the sealed
   guard. The pre-fix result intentionally records this failure of the guard;
   it is not a successful qualification result.
3. The successor checks the old receipt's output set and hashes **before**
   deciding to regenerate for changed inputs. **26 actual-make controls and
   40 TLS controls passed**, including six changed-input plus corrupt/missing
   output cases, preservation of other artifacts, valid changed-input
   regeneration, no-op stability, and missing public assembly providers.

The final case set explicitly asserts good TLS SHA256
`49ac682b8f5ed4295d03abc2dab5953fc472684d42eb0b87d779057942b23566`,
**1,822 bytes / 59 entries**. The unmodified historical `.long`-only parser,
with only its basename output convention adapted, produces **56 bytes** with
SHA256 `95e965fc1beea943c3eadc2cd941c34b01a3151968a0ffbe6917b354d2f0d8a5`.
Actual make rejects that output and preserves the known-good artifacts.

## Recovery without the original machine

Retrieve this directory at the **exact evidence-publication commit** linked
by the coordinator's rehydration document, not merely its moving branch.
The following PowerShell commands run from this directory. They inspect and
extract evidence only; they do not build or rerun qualification.

```powershell
$ErrorActionPreference = 'Stop'
function Assert-Hash($Path, $Expected) {
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() -ne $Expected) {
        throw "SHA256 mismatch: $Path"
    }
}
Assert-Hash .\proof.tar.gz '2abaa10780ef6e287a2bd90f424d599771aa7db1d72faf354ed81af7557f1c84'
$destination = Join-Path $env:TEMP ('runtime-generation-proof-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $destination | Out-Null
tar -xzf .\proof.tar.gz -C $destination
if ($LASTEXITCODE) { throw 'Evidence extraction failed' }
$root = Join-Path $destination 'runtime-generation-application-3fc49c8a'
$manifestPath = "$root.manifest.json"
Assert-Hash $manifestPath '8fdf475ac76350ed75a791ace5bf9cfefacf52e739b746e3cf41ab0f8f895776'
Assert-Hash "$root\handoff.json" '5fd646b577eec81083f31fe1e532b0387f0e02d509ec457c3f8b1fce306c078b'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$entries = @($manifest.files.PSObject.Properties)
if ($entries.Count -ne 170) { throw 'Unexpected evidence file count' }
foreach ($entry in $entries) {
    $path = Join-Path $root $entry.Name.Replace('/', '\')
    Assert-Hash $path $entry.Value.sha256
    if ((Get-Item -LiteralPath $path).Length -ne $entry.Value.bytes) {
        throw "Byte-count mismatch: $path"
    }
}
"Recovered and verified 170 original evidence files at $root"
```

The historical absolute Windows/WSL paths inside the sealed JSON and logs
are provenance, **not prerequisites for reading the recovered proof**.
Do not rewrite them or rerun the archived fixture scripts in place.
This archive is not a portable compiler/prefix/build environment and does
not contain a complete runtime checkout; obtain source at the qualified
commit linked above. Any future qualification needs a newly owned,
configured source/build/prefix layout and fresh receipts. Existing evidence
does not certify that new environment.

## Integration boundary

The assessed ordering remains **#32 -> content-reconciled #33 -> incremental
#34**, subject to the owners' freeze/drain and landing decisions. Preserve
#33's foreign-architecture spawn environment handling, union #32's missing
test/helper wiring, and preserve `563662` ancestry where possible. If #33 is
rewritten without that ancestry, restack only #34's source commit rather
than replaying the old integration payload. Publication of this evidence
does not authorize a merge, rebase, or changes to retained frozen artifacts.
