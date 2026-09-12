param(
    [Parameter(Mandatory = $true)]
    [string] $ArtifactDirectory,

    [string] $ExportDirectoryName = 'export-907',

    [string] $ArchiveName = 'msys2-runtime-arm64-utilities-907.zip',

    [string] $Disposition = 'utility-only export; not a replacement runtime package',

    [string] $ExternalProofDirectory,

    [switch] $RequireCleanPaths
)

$ErrorActionPreference = 'Stop'

$artifact = (Resolve-Path $ArtifactDirectory).Path
$build = Join-Path $artifact 'build'
$source = Join-Path $artifact 'source'
$qualification = Join-Path $artifact 'fixture\qualification'
$export = Join-Path $artifact $ExportDirectoryName
$archive = Join-Path $artifact $ArchiveName
$compilerRoot = 'C:\ag-readline-e138-01\combined-20260911-01\compiler'
$objdump = Join-Path $compilerRoot 'bin\aarch64-pc-cygwin-objdump.exe'
$strings = Join-Path $compilerRoot 'bin\aarch64-pc-cygwin-strings.exe'
$expectedRuntimeHash = '907afa099a69aa3c13d4e3b30eeba18c4a6b1766d5fa39b4746fae23c3f9e76c'

if (Test-Path $export) {
    Remove-Item -LiteralPath $export -Recurse -Force
}
if (Test-Path $archive) {
    Remove-Item -LiteralPath $archive -Force
}

$bin = Join-Path $export 'usr\bin'
$license = Join-Path $export 'usr\share\licenses\msys2-runtime'
$doc = Join-Path $export 'usr\share\doc\msys2-runtime'
$src = Join-Path $export 'usr\src\msys2-runtime\winsup\utils'
$evidence = Join-Path $export 'evidence'
New-Item -ItemType Directory -Force -Path $bin, $license, $doc, $src, $evidence | Out-Null

$utilityNames = @('ps', 'mount', 'cygpath')
foreach ($name in $utilityNames) {
    Copy-Item -LiteralPath (Join-Path $build "$name.exe") -Destination $bin
    Copy-Item -LiteralPath (Join-Path $build "$name.map") -Destination $evidence
}
foreach ($name in 'ps.cc', 'mount.cc', 'path.cc', 'path.h', 'cygpath.cc', 'wide_path.h') {
    Copy-Item -LiteralPath (Join-Path $source "utils\$name") -Destination $src
}
Copy-Item -LiteralPath (Join-Path $source 'COPYING') -Destination (Join-Path $license 'COPYING')
Copy-Item -LiteralPath (Join-Path $source 'doc\utils.xml') -Destination (Join-Path $doc 'utils.xml')
Copy-Item -LiteralPath (Join-Path $artifact 'build-command.json') -Destination $evidence
Copy-Item -LiteralPath (Join-Path $artifact 'generated-headers.SHA256SUMS') -Destination $evidence
Copy-Item -Path (Join-Path $qualification '*') -Destination $evidence -Recurse
if (Test-Path (Join-Path $artifact 'reproducibility.json')) {
    Copy-Item -LiteralPath (Join-Path $artifact 'reproducibility.json') -Destination $evidence
}
if ($ExternalProofDirectory) {
    $externalProof = Join-Path $evidence 'prior-private-intake'
    New-Item -ItemType Directory -Force -Path $externalProof | Out-Null
    Copy-Item -Path (Join-Path (Resolve-Path $ExternalProofDirectory).Path '*.json') -Destination $externalProof
}

function Get-PeMachine {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    [BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

function Find-ByteSequenceCount {
    param(
        [byte[]] $Bytes,
        [byte[]] $Needle
    )
    $count = 0
    for ($offset = 0; $offset -le $Bytes.Length - $Needle.Length; ++$offset) {
        $match = $true
        for ($index = 0; $index -lt $Needle.Length; ++$index) {
            if ($Bytes[$offset + $index] -ne $Needle[$index]) {
                $match = $false
                break
            }
        }
        if ($match) {
            ++$count
        }
    }
    $count
}

$expectedImports = @{
    ps = @('ADVAPI32.dll', 'KERNEL32.dll', 'msys-2.0.dll', 'ntdll.dll')
    mount = @('KERNEL32.dll', 'msys-2.0.dll')
    cygpath = @('KERNEL32.dll', 'msys-2.0.dll', 'ntdll.dll', 'SHELL32.dll', 'USERENV.dll')
}

$forbiddenMarkers = @(
    '.copilot',
    'session-state',
    'copilot-worktrees',
    'C:\Users\crutkasLocal',
    'C:/Users/crutkasLocal',
    'C:\ag-readline',
    'C:/ag-readline',
    'C:\ap06',
    'C:/ap06'
)
$binaries = foreach ($name in $utilityNames) {
    $path = Join-Path $bin "$name.exe"
    $machine = Get-PeMachine $path
    if ($machine -ne 0xaa64) {
        throw "$name.exe has unexpected PE machine 0x$($machine.ToString('x4'))"
    }
    $imports = @(
        & $objdump -p $path |
            Select-String 'DLL Name:' |
            ForEach-Object { ($_.Line -split 'DLL Name:\s*', 2)[1].Trim() }
    )
    if (Compare-Object $expectedImports[$name] $imports) {
        throw "$name.exe has an unexpected DLL import closure: $($imports -join ', ')"
    }
    $map = Get-Content -LiteralPath (Join-Path $build "$name.map") -Raw
    if ($map -match 'libcygwin\.a' -or $map -notmatch 'libmsys-2\.0\.a' -or $map -notmatch 'crt0\.o') {
        throw "$name link map does not prove the normal MSYS runtime/startup selection"
    }
    $bytes = [IO.File]::ReadAllBytes($path)
    $pathHits = foreach ($marker in $forbiddenMarkers) {
        $asciiCount = Find-ByteSequenceCount $bytes ([Text.Encoding]::ASCII.GetBytes($marker))
        $utf16Count = Find-ByteSequenceCount $bytes ([Text.Encoding]::Unicode.GetBytes($marker))
        if ($asciiCount -or $utf16Count) {
            [ordered]@{
                marker = $marker
                ascii_count = $asciiCount
                utf16le_count = $utf16Count
            }
        }
    }
    $canonicalPaths = @(
        & $strings -a $path |
            ForEach-Object {
                if ($_ -match '(/usr/src/.*|/opt/.*)$') {
                    $Matches[1]
                }
            } |
            Sort-Object -Unique
    )
    $noncanonicalPaths = @($canonicalPaths | Where-Object { $_ -match '\\' })
    if ($RequireCleanPaths -and ($pathHits.Count -or $noncanonicalPaths.Count)) {
        throw "$name contains non-public or non-normalized build paths"
    }
    [ordered]@{
        file = "usr/bin/$name.exe"
        sha256 = (Get-FileHash -Algorithm SHA256 $path).Hash.ToLowerInvariant()
        pe_machine = '0xaa64'
        imports = $imports
        link_map = "evidence/$name.map"
        normal_msys_import = $true
        libcygwin_alias_absent = $true
        path_hygiene = [ordered]@{
            forbidden_hits = @($pathHits)
            noncanonical_paths = $noncanonicalPaths
            canonical_paths = $canonicalPaths
        }
    }
}

$runtimeProofs = [ordered]@{}
$proofFiles = @{
    ps = 'loaded-modules.json'
    mount = 'mount-loaded-modules.json'
    cygpath = 'cygpath-loaded-modules.json'
}
foreach ($name in $utilityNames) {
    $proof = Get-Content -LiteralPath (Join-Path $qualification $proofFiles[$name]) -Raw | ConvertFrom-Json
    $modules = if ($name -eq 'mount') { @($proof.modules) } else { @($proof) }
    $runtime = $modules | Where-Object name -ieq 'msys-2.0.dll' | Select-Object -First 1
    if (!$runtime -or $runtime.sha256 -ne $expectedRuntimeHash) {
        throw "$name runtime proof is missing the pinned 907 DLL"
    }
    $runtimeProofs[$name] = [ordered]@{
        path = $runtime.path
        sha256 = $runtime.sha256
    }
}

$actualInputs = [ordered]@{
    gxx = 'C:\ag-readline-e138-01\combined-20260911-01\compiler\bin\g++.exe'
    cc1plus = 'C:\ag-readline-e138-01\combined-20260911-01\compiler\libexec\gcc\aarch64-pc-cygwin\15.0.1\cc1plus.exe'
    specs = 'C:\ag-readline-e138-01\combined-20260911-01\compiler\lib\gcc\aarch64-pc-cygwin\15.0.1\specs'
    runtime_import = 'C:\ag-readline-e138-01\combined-20260911-01\compiler\aarch64-pc-cygwin\lib\libmsys-2.0.a'
    crt = 'C:\ag-readline-e138-01\combined-20260911-01\compiler\aarch64-pc-cygwin\lib\crt0.o'
    psapi_import = 'C:\ap06-78\tcl-main-05\tc\aarch64-w64-mingw32\lib\libpsapi.a'
    userenv_import = 'C:\ap06-78\tcl-main-05\tc\aarch64-w64-mingw32\lib\libuserenv.a'
}
$inputHashes = [ordered]@{}
foreach ($entry in $actualInputs.GetEnumerator()) {
    $inputHashes[$entry.Key] = [ordered]@{
        path = $entry.Value
        sha256 = (Get-FileHash -Algorithm SHA256 $entry.Value).Hash.ToLowerInvariant()
    }
}

$sourceHashes = Get-ChildItem -LiteralPath $src -File |
    Sort-Object Name |
    ForEach-Object {
        '{0}  usr/src/msys2-runtime/winsup/utils/{1}' -f
            (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant(),
            $_.Name
    }
$sourceHashes | Set-Content -LiteralPath (Join-Path $evidence 'SOURCE-SHA256SUMS') -Encoding ascii

[ordered]@{
    package_owner = 'msys2-runtime utilities'
    scope = $Disposition
    source_commit = '563662010c2f2072ad90f28713611caabdf70dbb'
    source_tree_manifest_sha256 = '2180cb8b66ae8cf7a6c121b856dd1d4a1a7dccea927a672c4e0cbaa385adce59'
    producer_receipts = [ordered]@{
        runtime_dll_sha256 = $expectedRuntimeHash
        sdk_inputs_sha256 = '69bde4474dc5c93660a598fac1ca8d3f97907cdabdbd4a454f51adeace711d34'
        compiler_sha256 = 'fff0fa4da353da74bbfd7e1f3424103e32fd73ab47878c9447cf5c67b43b2c38'
        runtime_import_sha256 = '6f19eb725d275d6e9f3564783cf5a18c9f13849b6c8033ca92291ecd3f5a735c'
        crt_sha256 = '29b356f7105386a37bc8b16169e8beac1b0cbc2c1640946df02f85bbae5d3737'
    }
    actual_inputs = $inputHashes
    binaries = $binaries
    runtime_load_proofs = $runtimeProofs
    behavior_proofs = [ordered]@{
        ps = @('help.txt', 'version.txt', 'pid-proof.json', 'perl-cat-proof.json', 'parent.txt', 'child.txt', 'session.txt', 'windows.txt')
        mount = @('mount-help.txt', 'mount-version.txt', 'mount-output.txt', 'mount-proof.json')
        cygpath = @('cygpath-help.txt', 'cygpath-version.txt', 'cygpath-proof.json')
    }
} | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $export 'MANIFEST.json') -Encoding utf8NoBOM

@"
These executables are utilities owned by the msys2-runtime package.

Disposition: $Disposition

This utility-only ARM64 export does not transfer or create independent
ownership of the runtime DLL, compiler, SDK, or a complete runtime package.

The binaries were built from the pinned source commit and the normal configured
winsup/utils recipes. No libcygwin.a alias was used. See MANIFEST.json,
evidence/build-command.json, the link maps, and qualification outputs.
"@ | Set-Content -LiteralPath (Join-Path $export 'README.txt') -Encoding ascii

$hashes = Get-ChildItem -LiteralPath $export -File -Recurse |
    Where-Object Name -ne 'SHA256SUMS' |
    Sort-Object FullName |
    ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($export, $_.FullName).Replace('\', '/')
        '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant(), $relative
    }
$hashes | Set-Content -LiteralPath (Join-Path $export 'SHA256SUMS') -Encoding ascii

Compress-Archive -Path (Join-Path $export '*') -DestinationPath $archive -CompressionLevel Optimal
[ordered]@{
    export_directory = $export
    archive = $archive
    archive_sha256 = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
    binaries = $binaries
} | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $artifact 'handoff.json') -Encoding utf8NoBOM
