[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RuntimeDll,
    [Parameter(Mandatory)] [string] $BashExe,
    [Parameter(Mandatory)] [string] $BusyBoxExe,
    [Parameter(Mandatory)] [string] $MinGitRoot,
    [Parameter(Mandatory)] [string] $Destination,
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{40}$')] [string] $RuntimeCommit,
    [long] $SourceDateEpoch = 1788034899
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$arm64 = 0xAA64

function Get-PeMachine([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $null }
        $stream.Position = 0x3C
        $stream.Position = $reader.ReadUInt32()
        if ($reader.ReadUInt32() -ne 0x00004550) { return $null }
        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

function Copy-NativeTree([string] $Source, [string] $Target) {
    Get-ChildItem -LiteralPath $Source -File -Recurse | Sort-Object FullName | ForEach-Object {
        if ($_.Name -match 'credential-manager|scalar') { return }
        $machine = Get-PeMachine $_.FullName
        if ($null -ne $machine -and $machine -ne $arm64) { return }
        $relative = [IO.Path]::GetRelativePath($Source, $_.FullName)
        $output = Join-Path $Target $relative
        New-Item -ItemType Directory -Path (Split-Path $output) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $output
    }
}

function Write-DeterministicZip([string] $Root, [string] $Path, [long] $Epoch) {
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Create($Path)
    try {
        $archive = [IO.Compression.ZipArchive]::new(
            $stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $timestamp = [DateTimeOffset]::FromUnixTimeSeconds($Epoch)
            Get-ChildItem -LiteralPath $Root -File -Recurse |
                Sort-Object { [IO.Path]::GetRelativePath($Root, $_.FullName) } |
                ForEach-Object {
                    $relative = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
                    $entry = $archive.CreateEntry(
                        $relative, [IO.Compression.CompressionLevel]::Optimal)
                    $entry.LastWriteTime = $timestamp
                    $input = [IO.File]::OpenRead($_.FullName)
                    $output = $entry.Open()
                    try { $input.CopyTo($output) }
                    finally { $output.Dispose(); $input.Dispose() }
                }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

foreach ($path in @($RuntimeDll, $BashExe, $BusyBoxExe)) {
    if ((Get-PeMachine $path) -ne $arm64) {
        throw "$path is not a native ARM64 PE image"
    }
}

$root = Join-Path $Destination 'native-git-bash-mvp-arm64'
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
New-Item -ItemType Directory -Path "$root\usr\bin", "$root\cmd", "$root\clangarm64" -Force |
    Out-Null
Copy-Item -LiteralPath $RuntimeDll -Destination "$root\usr\bin\msys-2.0.dll"
Copy-Item -LiteralPath $BashExe -Destination "$root\usr\bin\bash.exe"
Copy-Item -LiteralPath $BusyBoxExe -Destination "$root\usr\bin\busybox.exe"
@(
    'awk', 'basename', 'cat', 'cp', 'cut', 'dirname', 'echo', 'env', 'false',
    'find', 'grep', 'head', 'ln', 'mkdir', 'mv', 'printf', 'pwd', 'readlink',
    'rm', 'sed', 'sh', 'sleep', 'sort', 'tail', 'test', 'touch', 'tr', 'true', 'uname',
    'which', 'xargs'
) | ForEach-Object {
    Copy-Item -LiteralPath $BusyBoxExe -Destination "$root\usr\bin\$_.exe"
}

Copy-NativeTree (Join-Path $MinGitRoot 'cmd') (Join-Path $root 'cmd')
Copy-NativeTree (Join-Path $MinGitRoot 'clangarm64\bin') (Join-Path $root 'clangarm64\bin')
Copy-NativeTree (Join-Path $MinGitRoot 'clangarm64\libexec\git-core') `
    (Join-Path $root 'clangarm64\libexec\git-core')
Copy-NativeTree (Join-Path $MinGitRoot 'clangarm64\share\git-core') `
    (Join-Path $root 'clangarm64\share\git-core')
if (Test-Path -LiteralPath (Join-Path $MinGitRoot 'etc')) {
    Copy-NativeTree (Join-Path $MinGitRoot 'etc') (Join-Path $root 'etc')
}

$provenance = [ordered]@{
    schema = 1
    source_date_epoch = $SourceDateEpoch
    runtime = [ordered]@{
        source = 'this repository and pull-request head'
        source_commit = $RuntimeCommit
        base_commit = 'f71b5d07c804433dfa06df122b22efd200e9ec2b'
        toolchain = 'prebuilt native ARM64 Clang/LLD from MSYS2 CLANGARM64'
        generators = [ordered]@{
            source = 'https://github.com/crutkas/msys2-runtime/releases/download/native-generators-layer6-20260829/native-generators-arm64.zip'
            sha256 = 'B8223D2F3D66E536298BD2DE0EFD395F1C4CB55DC0840CFEF4E8E50C58AFC3E7'
        }
    }
    busybox = [ordered]@{
        source = 'https://github.com/crutkas/busybox-w32 commit c26a88d7e1ec96a1b96fce442e35378f3ddecba4'
        bundle_sha256 = '23D605DDDCFAE3E1865C5E5CC9BF7C54FA104AD62B2313644FA7E058475F6EAE'
    }
    bash = [ordered]@{
        source = 'https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz'
        sha256 = '0D5CD86965F869A26CF64F4B71BE7B96F90A3BA8B3D74E27E8E9D9D5550F31BA'
        configure = '--build=aarch64-pc-cygwin --host=aarch64-pc-cygwin --prefix=/usr --without-bash-malloc --disable-nls --disable-rpath --enable-job-control'
    }
    git = [ordered]@{
        source = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/MinGit-2.55.0.3-arm64.zip'
        sha256 = 'F7748965D5068E81AD93CA1923650DB6742D6E22332B1AE7567A841C59F6BDE5'
        excluded = @('x64 usr subtree', 'Git Credential Manager', 'Scalar')
    }
    release_only_gaps = @(
        'self-hosted native GCC',
        'final source-bound CRT publication',
        'gettext/NLS catalogs',
        'installer and package admission',
        'Binutils MOV decoder',
        'final static C++ destructor registration',
        'ARM64 CPUID/cache reporting',
        'standalone cygserver.exe',
        'minimized symbol-subset import libraries'
    )
}
$provenance | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $root 'provenance.json') -Encoding utf8NoBOM

$files = Get-ChildItem -LiteralPath $root -File -Recurse |
    Where-Object Name -ne 'manifest.json' |
    Sort-Object { [IO.Path]::GetRelativePath($root, $_.FullName) } |
    ForEach-Object {
        $machine = Get-PeMachine $_.FullName
        [ordered]@{
            path = [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
            size = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            pe_machine = if ($null -eq $machine) { $null } else { '0x{0:X4}' -f $machine }
        }
    }
$manifest = [ordered]@{
    schema = 1
    file_count = @($files).Count
    native_arm64_pe_count = @($files | Where-Object pe_machine -eq '0xAA64').Count
    files = @($files)
}
$manifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $root 'manifest.json') -Encoding utf8NoBOM

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$archive = Join-Path $Destination 'native-git-bash-mvp-arm64.zip'
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
Write-DeterministicZip $root $archive $SourceDateEpoch
$digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
[ordered]@{
    archive = $archive
    sha256 = $digest
    file_count = $manifest.file_count
    native_arm64_pe_count = $manifest.native_arm64_pe_count
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'artifact.json') `
    -Encoding utf8NoBOM
Write-Host "artifact: $archive"
Write-Host "sha256: $digest"
Write-Host "files: $($manifest.file_count); native ARM64 PE: $($manifest.native_arm64_pe_count)"
