[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Work,
    [Parameter(Mandatory)] [string] $ClangPrefix,
    [Parameter(Mandatory)] [string] $BusyBoxArchive,
    [Parameter(Mandatory)] [string] $GeneratorArchive,
    [Parameter(Mandatory)] [string] $MinGitArchive,
    [ValidateRange(1, 64)] [int] $Jobs = 20
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$env:SOURCE_DATE_EPOCH = '1788034899'
$arm64 = 0xAA64

function Get-PeMachine([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "$Path is not a PE image" }
        $stream.Position = 0x3C
        $stream.Position = $reader.ReadUInt32()
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "$Path has no PE signature" }
        return $reader.ReadUInt16()
    }
    finally { $stream.Dispose() }
}

function Assert-Arm64([string] $Path, [string] $Class) {
    if (-not (Test-Path -LiteralPath $Path) -or (Get-PeMachine $Path) -ne $arm64) {
        throw "$Class is not a native ARM64 PE process: $Path"
    }
    Write-Host "process-attestation: $Class = AA64 ($Path)"
}

function Assert-Sha256([string] $Path, [string] $Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { throw "SHA-256 mismatch for $Path`: $actual" }
}

function To-Posix([string] $Path) { return $Path.Replace('\', '/') }

Assert-Sha256 $BusyBoxArchive '23D605DDDCFAE3E1865C5E5CC9BF7C54FA104AD62B2313644FA7E058475F6EAE'
Assert-Sha256 $GeneratorArchive 'B8223D2F3D66E536298BD2DE0EFD395F1C4CB55DC0840CFEF4E8E50C58AFC3E7'
Assert-Sha256 $MinGitArchive 'F7748965D5068E81AD93CA1923650DB6742D6E22332B1AE7567A841C59F6BDE5'

$inputRoot = Join-Path $Work 'inputs'
$sourceRoot = Join-Path $Work 'source'
$buildRoot = Join-Path $Work 'build'
$bashSource = Join-Path $Work 'bash-source'
$bashBuild = Join-Path $Work 'bash-build'
$minGit = Join-Path $Work 'mingit'
$shim = Join-Path $Work 'native-shims'
New-Item -ItemType Directory -Path $inputRoot, $sourceRoot, $buildRoot, $bashSource,
    $bashBuild, $minGit, $shim -Force | Out-Null

tar -xf $BusyBoxArchive -C $inputRoot
$busy = (Get-ChildItem -LiteralPath $inputRoot -Filter busybox.exe -File -Recurse |
    Select-Object -First 1).FullName
Assert-Arm64 $busy 'BusyBox shell'
Expand-Archive -LiteralPath $GeneratorArchive -DestinationPath $Work -Force
$generatorRoot = Join-Path $Work 'native-generators-arm64'
$generatorPrefix = Join-Path $generatorRoot 'prefix'
$generatorBin = Join-Path $generatorPrefix 'bin'
$generatorToolchain = Join-Path $generatorRoot 'toolchain\bin'
$nativePerl = Join-Path $ClangPrefix 'perl.exe'
$generatorPrefixPosix = To-Posix $generatorPrefix
$nativePerlPosix = To-Posix $nativePerl
Get-ChildItem -LiteralPath $generatorPrefix -File -Recurse | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) { return }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ($text.Contains('@GENERATOR_PREFIX@') -or $text.Contains('@NATIVE_PERL@')) {
        $text = $text.Replace('@GENERATOR_PREFIX@', $generatorPrefixPosix).
            Replace('@NATIVE_PERL@', $nativePerlPosix)
        [IO.File]::WriteAllText($_.FullName, $text, [Text.UTF8Encoding]::new($false))
    }
}

foreach ($name in @('awk', 'basename', 'cat', 'cmp', 'cp', 'cut', 'dirname', 'echo',
    'env', 'expr', 'find', 'grep', 'head', 'install', 'ln', 'mkdir', 'mv', 'printf',
    'pwd', 'rm', 'sed', 'sh', 'sort', 'tail', 'test', 'touch', 'tr', 'uname', 'which',
    'xargs')) {
    Copy-Item -LiteralPath $busy -Destination (Join-Path $shim "$name.exe") -Force
}

$clang = Join-Path $ClangPrefix 'clang.exe'
$clangxx = Join-Path $ClangPrefix 'clang++.exe'
$make = Join-Path $ClangPrefix 'mingw32-make.exe'
foreach ($tool in @(
    @($clang, 'Clang'), @($clangxx, 'Clang++'), @($make, 'GNU Make'),
    @((Join-Path $ClangPrefix 'llvm-ar.exe'), 'LLVM ar'),
    @((Join-Path $ClangPrefix 'ld.lld.exe'), 'LLD'),
    @($nativePerl, 'Perl'),
    @((Join-Path $generatorBin 'm4.exe'), 'M4'),
    @((Join-Path $generatorToolchain 'autoconf.exe'), 'Autoconf launcher'),
    @((Join-Path $generatorToolchain 'automake.exe'), 'Automake launcher'),
    @((Join-Path $generatorBin 'msta'), 'COCOM msta'),
    @((Join-Path $generatorBin 'sprut'), 'COCOM sprut')
)) { Assert-Arm64 $tool[0] $tool[1] }

# git archive preserves exact blob bytes and avoids autocrlf changes in generated inputs.
$sourceTar = Join-Path $Work 'source.tar'
& git -C $Source archive --format=tar -o $sourceTar HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
& $busy tar -xf $sourceTar -C $sourceRoot
if ($LASTEXITCODE -ne 0) { throw 'native source extraction failed' }

$crtPrefix = Split-Path $ClangPrefix
$resourceDir = (& $clang -print-resource-dir).Trim()
$pathBefore = $env:PATH
$env:PATH = "$generatorToolchain;$generatorBin;$shim;$ClangPrefix;$pathBefore"
$env:NATIVE_PERL = $nativePerl
$env:AUTOTOOLS_BINDIR = $generatorBin
$env:ACLOCAL_PATH = Join-Path $generatorPrefix 'share\aclocal'
$env:ACLOCAL = Join-Path $generatorToolchain 'aclocal.exe'
$env:AUTOCONF = Join-Path $generatorToolchain 'autoconf.exe'
$env:AUTOMAKE = Join-Path $generatorToolchain 'automake.exe'
$env:RM = Join-Path $shim 'rm.exe'
$env:M4 = Join-Path $generatorBin 'm4.exe'
$env:BISON = Join-Path $generatorBin 'bison.exe'
$env:FLEX = Join-Path $generatorBin 'flex.exe'
$env:CONFIG_SHELL = "$busy sh"
$env:SHELL = "$busy sh"
$env:MAKE = $make
$env:AR = Join-Path $ClangPrefix 'llvm-ar.exe'
$env:AS = Join-Path $ClangPrefix 'as.exe'
$env:DLLTOOL = Join-Path $ClangPrefix 'llvm-dlltool.exe'
$env:LD = Join-Path $ClangPrefix 'ld.lld.exe'
$env:NM = Join-Path $ClangPrefix 'llvm-nm.exe'
$env:OBJCOPY = Join-Path $ClangPrefix 'llvm-objcopy.exe'
$env:OBJDUMP = Join-Path $ClangPrefix 'llvm-objdump.exe'
$env:RANLIB = Join-Path $ClangPrefix 'llvm-ranlib.exe'
$env:READELF = Join-Path $ClangPrefix 'llvm-readelf.exe'
$env:STRIP = Join-Path $ClangPrefix 'llvm-strip.exe'
$env:WINDRES = Join-Path $ClangPrefix 'llvm-windres.exe'

$src = To-Posix $sourceRoot
$build = To-Posix $buildRoot
$crt = To-Posix $crtPrefix
$bin = To-Posix $ClangPrefix
$emptySysroot = Join-Path $Work 'empty-sysroot'
New-Item -ItemType Directory -Path $emptySysroot -Force | Out-Null
$empty = To-Posix $emptySysroot
$buildCc = "$bin/clang.exe -target aarch64-w64-windows-gnu -fuse-ld=lld " +
    "-isystem $crt/include -L$crt/lib -B$crt/lib"
$buildCxx = "$bin/clang++.exe -target aarch64-w64-windows-gnu -fuse-ld=lld " +
    "-isystem $crt/include -L$crt/lib -B$crt/lib"
$targetCc = "$bin/clang.exe -target aarch64-w64-windows-gnu -fuse-ld=lld --sysroot=$empty"
$targetCxx = "$bin/clang++.exe -target aarch64-w64-windows-gnu -fuse-ld=lld --sysroot=$empty"
$env:CC = $buildCc
$env:CXX = $buildCxx
$env:CC_FOR_TARGET = $targetCc
$env:CXX_FOR_TARGET = $targetCxx

Push-Location $sourceRoot
try {
    & $busy sh (Join-Path $sourceRoot 'winsup\autogen.sh')
    if ($LASTEXITCODE -ne 0) { throw 'winsup Autotools generation failed' }
}
finally { Pop-Location }

Push-Location $buildRoot
try {
    & $busy sh (Join-Path $sourceRoot 'configure') `
        '--build=aarch64-w64-mingw32' '--host=aarch64-w64-mingw32' `
        '--target=aarch64-pc-cygwin' '--disable-nls' '--disable-doc' `
        '--disable-dependency-tracking' '--disable-dumper' '--with-cross-bootstrap' `
        '--with-msys2-runtime-commit=f71b5d07c804433dfa06df122b22efd200e9ec2b'
    if ($LASTEXITCODE -ne 0) { throw 'top-level configure failed' }
    & $make -j $Jobs all-target-newlib
    if ($LASTEXITCODE -ne 0) { throw 'newlib build failed' }
}
finally { Pop-Location }

$newlibBuild = "$build/aarch64-pc-cygwin/newlib"
$cygwinBuild = Join-Path $buildRoot 'aarch64-pc-cygwin\winsup'
$cygwinBuildPosix = To-Posix $cygwinBuild
New-Item -ItemType Directory -Path $cygwinBuild -Force | Out-Null
$runtimeCc = "$bin/clang.exe -target aarch64-w64-windows-gnu -fuse-ld=lld --sysroot=$empty " +
    "-L$cygwinBuildPosix/cygwin -I$src/winsup/cygwin/include " +
    "-B$newlibBuild -I$newlibBuild/targ-include -I$src/newlib/libc/include " +
    "-idirafter $src/winsup/w32api/include -L$crt/lib -B$crt/lib"
$runtimeCxx = $runtimeCc.Replace('clang.exe', 'clang++.exe')
$env:CC = $runtimeCc
$env:CXX = $runtimeCxx
$env:CFLAGS = '-g -O2 -D__CYGWIN__ -D__MSYS__'
$env:CXXFLAGS = '-g -O2 -D__CYGWIN__ -D__MSYS__'
Push-Location $cygwinBuild
try {
    & $busy sh (Join-Path $sourceRoot 'winsup\configure') "--srcdir=$src/winsup" `
        '--build=aarch64-w64-mingw32' '--host=aarch64-pc-cygwin' `
        '--target=aarch64-pc-cygwin' '--with-newlib' '--disable-nls' '--disable-doc' `
        '--disable-dependency-tracking' '--disable-dumper' '--with-cross-bootstrap' `
        '--with-msys2-runtime-commit=f71b5d07c804433dfa06df122b22efd200e9ec2b'
    if ($LASTEXITCODE -ne 0) { throw 'winsup configure failed' }
    & $make -C cygwin -j $Jobs
    if ($LASTEXITCODE -ne 0) { throw 'runtime DLL build failed' }
}
finally { Pop-Location }

$runtimeDll = Join-Path $cygwinBuild 'cygwin\new-msys-2.0.dll'
Assert-Arm64 $runtimeDll 'source-built msys-2.0.dll'
$runtimeStage = Join-Path $Work 'runtime-stage'
New-Item -ItemType Directory -Path $runtimeStage -Force | Out-Null
Copy-Item -LiteralPath $runtimeDll -Destination (Join-Path $runtimeStage 'msys-2.0.dll')
$env:PATH = "$runtimeStage;$env:PATH"

$bashTar = Join-Path $Work 'bash-5.3.tar.gz'
Invoke-WebRequest -Uri 'https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz' -OutFile $bashTar
Assert-Sha256 $bashTar '0D5CD86965F869A26CF64F4B71BE7B96F90A3BA8B3D74E27E8E9D9D5550F31BA'
& $busy tar -xzf $bashTar -C $bashSource
if ($LASTEXITCODE -ne 0) { throw 'Bash source extraction failed' }

$env:MVP_CLANG_PREFIX = $bin
$env:MVP_CLANG_RESOURCE_DIR = To-Posix $resourceDir
$env:MVP_CRT_PREFIX = $crt
$env:MVP_RUNTIME_SOURCE = $src
$env:MVP_RUNTIME_BUILD = $build
$wrapper = To-Posix (Join-Path $sourceRoot '.github\checks\aarch64-cygwin-clang.sh')
$env:CC = "$busy sh $wrapper"
Push-Location $bashBuild
try {
    & $busy sh (Join-Path $bashSource 'bash-5.3\configure') `
        '--build=aarch64-pc-cygwin' '--host=aarch64-pc-cygwin' '--prefix=/usr' `
        '--without-bash-malloc' '--disable-nls' '--disable-rpath' '--enable-job-control'
    if ($LASTEXITCODE -ne 0) { throw 'Bash configure failed' }
    try { & $make -j $Jobs bash.exe }
    catch {
        $generator = Join-Path $bashBuild 'builtins\mkbuiltins.exe'
        if (-not (Test-Path -LiteralPath $generator)) { throw }
        Get-ChildItem -LiteralPath (Join-Path $bashSource 'bash-5.3\builtins') `
            -Filter '*.def' | Sort-Object Name | ForEach-Object {
                & $generator -D (Join-Path $bashSource 'bash-5.3\builtins') $_.FullName
                if ($LASTEXITCODE -ne 0) { throw "mkbuiltins failed for $($_.Name)" }
            }
        & $make -j $Jobs bash.exe
    }
    if ($LASTEXITCODE -ne 0) { throw 'Bash build failed' }
}
finally { Pop-Location }
Assert-Arm64 (Join-Path $bashBuild 'bash.exe') 'source-built GNU Bash'

Expand-Archive -LiteralPath $MinGitArchive -DestinationPath $minGit -Force
Write-Output ([ordered]@{
    runtime_dll = $runtimeDll
    bash = Join-Path $bashBuild 'bash.exe'
    busybox = $busy
    mingit = $minGit
    runtime_build = $buildRoot
    crt_prefix = $crtPrefix
} | ConvertTo-Json)
