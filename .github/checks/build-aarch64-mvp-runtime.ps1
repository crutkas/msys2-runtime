[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Work,
    [Parameter(Mandatory)] [string] $ClangPrefix,
    [Parameter(Mandatory)] [string] $BusyBoxArchive,
    [Parameter(Mandatory)] [string] $GeneratorArchive,
    [Parameter(Mandatory)] [string] $MinGitArchive,
    [string] $NativePerl,
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

$sourceCommit = (& git -C $Source rev-parse 'HEAD^{commit}').Trim()
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Source HEAD is not an exact 40-hex commit: $sourceCommit"
}
$resolvedWork = [IO.Path]::GetFullPath($Work)
if ((Split-Path $resolvedWork -Leaf) -ne 'git-bash-mvp' -or
    [IO.Path]::GetPathRoot($resolvedWork) -eq $resolvedWork) {
    throw "Refusing to clean unsafe work root: $resolvedWork"
}
$staleSentinel = Join-Path $resolvedWork 'stale-sentinel'
if (Test-Path -LiteralPath $resolvedWork) {
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force
}
if (Test-Path -LiteralPath $staleSentinel) {
    throw "Stale work-root sentinel survived cleanup: $staleSentinel"
}
Write-Host "source-identity: $sourceCommit"
Write-Host "clean-work-root: $resolvedWork"

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
$tempRoot = Join-Path $Work 'tmp'
New-Item -ItemType Directory -Path $inputRoot, $sourceRoot, $buildRoot, $bashSource,
    $bashBuild, $minGit, $shim, $tempRoot -Force | Out-Null
$env:TEMP = $tempRoot
$env:TMP = $tempRoot
$env:TMPDIR = To-Posix $tempRoot

tar -xf $BusyBoxArchive -C $inputRoot
$busy = (Get-ChildItem -LiteralPath $inputRoot -Filter busybox.exe -File -Recurse |
    Select-Object -First 1).FullName
Assert-Arm64 $busy 'BusyBox shell'
$generatorExtractRoot = Join-Path ([IO.Path]::GetPathRoot($Work)) 'g'
if (Test-Path -LiteralPath $generatorExtractRoot) {
    Remove-Item -LiteralPath $generatorExtractRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $generatorExtractRoot -Force | Out-Null
Expand-Archive -LiteralPath $GeneratorArchive -DestinationPath $generatorExtractRoot -Force
$generatorRoot = Join-Path $generatorExtractRoot 'native-generators-arm64'
$generatorPrefix = Join-Path $generatorRoot 'prefix'
$generatorBin = Join-Path $generatorPrefix 'bin'
$generatorToolchain = Join-Path $generatorRoot 'toolchain\bin'
$nativePerl = if ($NativePerl) { $NativePerl } else { Join-Path $ClangPrefix 'perl.exe' }
$generatorPrefixPosix = To-Posix $generatorPrefix
$nativePerlPosix = To-Posix $nativePerl
Get-ChildItem -LiteralPath $generatorPrefix -File -Recurse | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) { return }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $relocated = $text.Replace('@GENERATOR_PREFIX@', $generatorPrefixPosix).
        Replace('@NATIVE_PERL@', $nativePerlPosix)
    $relocated = $relocated -replace `
        '/[A-Za-z]/Users/[^/]+/\.copilot/session-state/[0-9a-f-]+/files/native-preflight/prefix', `
        $generatorPrefixPosix
    $relocated = $relocated -replace `
        '[A-Za-z]:/Users/[^/]+/\.copilot/session-state/[0-9a-f-]+/files/driver/msys2-root/msys64/clangarm64/bin/perl\.exe', `
        $nativePerlPosix
    if ($_.Name -in @('aclocal', 'aclocal-1.15')) {
        $needle = 'my $fullfile = File::Spec->canonpath ("$m4dir/$file");'
        $replacement = "$needle`n`t  `$fullfile = File::Spec->abs2rel (`$fullfile);`n`t  `$fullfile =~ tr{\\}{/};"
        $relocated = $relocated.Replace($needle, $replacement)
        $relocated = $relocated.Replace(
            '  $traces = "echo ''$early_m4_code'' | $traces - ";',
            '  $traces = "echo \"$early_m4_code\" | $traces - ";')
        $relocated = $relocated.Replace(
            '(map { "''$_''" }',
            '(map { qq{"$_"} }')
        $relocated = $relocated.Replace(
            '(map { "--trace=''$_:\$f::\$n::\${::}%''" }',
            '(map { qq{"--trace=$_:\$f::\$n::\${::}%"} }')
        $relocated = $relocated.Replace(
            '(map { "--trace=''$_:\$f::\$n''" }',
            '(map { qq{"--trace=$_:\$f::\$n"} }')
        $traceNeedle = '      my ($file, $macro, $arg1) = split (/::/);'
        $traceReplacement = "$traceNeedle`n      `$file =~ tr{\\}{/};"
        $relocated = $relocated.Replace($traceNeedle, $traceReplacement)
    }
    if ($_.Name -in @('autom4te', 'autom4te-2.69')) {
        $relocated = $relocated.Replace('>/dev/null', '>NUL')
    }
    if ($_.Name -in @('automake', 'automake-1.15')) {
        $relocated = $relocated.Replace(
            ''':\$f:\$l::\$d::\$n::\${::}%''',
            ''':$f:$l::$d::$n::${::}%''')
    }
    if ($relocated -ne $text) {
        [IO.File]::WriteAllText($_.FullName, $relocated, [Text.UTF8Encoding]::new($false))
    }
    if ($relocated -match '/[A-Za-z]/Users/') {
        throw "Generator script retains an archived local path: $($_.FullName)"
    }
}

foreach ($name in @('awk', 'basename', 'cat', 'cmp', 'cp', 'cut', 'dirname', 'echo',
    'date', 'env', 'expr', 'find', 'grep', 'head', 'install', 'ln', 'mkdir', 'mv',
    'patch', 'printf', 'pwd', 'rm', 'sed', 'sh', 'sort', 'tail', 'tee', 'test',
    'touch', 'tr', 'uname', 'which', 'xargs')) {
    Copy-Item -LiteralPath $busy -Destination (Join-Path $shim "$name.exe") -Force
}

$clang = Join-Path $ClangPrefix 'clang.exe'
$clangxx = Join-Path $ClangPrefix 'clang++.exe'
$make = Join-Path $ClangPrefix 'mingw32-make.exe'
$makeCommand = 'mingw32-make.exe'
foreach ($tool in @(
    @($clang, 'Clang'), @($clangxx, 'Clang++'), @($make, 'GNU Make'),
    @((Join-Path $ClangPrefix 'llvm-ar.exe'), 'LLVM ar'),
    @((Join-Path $ClangPrefix 'ld.lld.exe'), 'LLD'),
    @($nativePerl, 'Perl'),
    @((Join-Path $generatorBin 'm4.exe'), 'M4'),
    @((Join-Path $generatorToolchain 'autoconf.exe'), 'Autoconf launcher'),
    @((Join-Path $generatorToolchain 'autom4te.exe'), 'Autom4te launcher'),
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
$nativePerlDir = Split-Path $nativePerl
$env:PATH = "$shim;$generatorToolchain;$generatorBin;$nativePerlDir;$ClangPrefix;" +
    "$env:SystemRoot\System32;$env:SystemRoot"
$env:NATIVE_PERL = $nativePerl
$env:PERL = To-Posix $nativePerl
$env:AUTOTOOLS_BINDIR = $generatorBin
$env:ACLOCAL_PATH = To-Posix (Join-Path $generatorPrefix 'share\aclocal')
$env:autom4te_perllibdir = To-Posix (Join-Path $generatorPrefix 'share\autoconf')
$env:AC_MACRODIR = $env:autom4te_perllibdir
$env:ACLOCAL = Join-Path $generatorToolchain 'aclocal.exe'
$env:AUTOCONF = Join-Path $generatorToolchain 'autoconf.exe'
$env:AUTOM4TE = 'autom4te.exe'
$env:AUTOMAKE = Join-Path $generatorToolchain 'automake.exe'
$env:RM = To-Posix (Join-Path $shim 'rm.exe')
$env:AWK = To-Posix (Join-Path $shim 'awk.exe')
$env:DATE = To-Posix (Join-Path $shim 'date.exe')
$env:GREP = To-Posix (Join-Path $shim 'grep.exe')
$env:EGREP_TRADITIONAL = $env:GREP
$env:PATCH = To-Posix (Join-Path $shim 'patch.exe')
$env:SED = To-Posix (Join-Path $shim 'sed.exe')
$env:TEE = To-Posix (Join-Path $shim 'tee.exe')
$env:M4 = 'm4.exe'
$env:BISON = 'bison.exe'
$env:FLEX = 'flex.exe'
$env:CONFIG_SHELL = Join-Path $shim 'sh.exe'
$env:SHELL = $env:CONFIG_SHELL
$env:MAKE = $make
$env:AR = 'llvm-ar.exe'
$env:AS = 'clang.exe'
$env:DLLTOOL = 'llvm-dlltool.exe'
$env:LD = 'ld.lld.exe'
$env:NM = 'llvm-nm.exe'
$env:OBJCOPY = 'llvm-objcopy.exe'
$env:OBJDUMP = 'llvm-objdump.exe'
$env:RANLIB = 'llvm-ranlib.exe'
$env:READELF = 'llvm-readelf.exe'
$env:STRIP = 'llvm-strip.exe'
$env:WINDRES = 'llvm-windres.exe'
$env:AR_FOR_TARGET = $env:AR
$env:AS_FOR_TARGET = $clang
$env:LD_FOR_TARGET = $env:LD
$env:NM_FOR_TARGET = $env:NM
$env:OBJCOPY_FOR_TARGET = $env:OBJCOPY
$env:OBJDUMP_FOR_TARGET = $env:OBJDUMP
$env:RANLIB_FOR_TARGET = $env:RANLIB
$env:READELF_FOR_TARGET = $env:READELF
$env:STRIP_FOR_TARGET = $env:STRIP
$env:WINDRES_FOR_TARGET = $env:WINDRES
$busyHash = (Get-FileHash -LiteralPath $busy -Algorithm SHA256).Hash
foreach ($utility in @('patch', 'date', 'tee', 'awk', 'sed', 'find', 'cmp',
    'grep', 'rm', 'touch')) {
    $resolved = (Get-Command "$utility.exe" -CommandType Application |
        Select-Object -First 1).Source
    Assert-Arm64 $resolved "BusyBox $utility utility"
    if ((Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash -ne $busyHash) {
        throw "$utility did not resolve to the approved BusyBox image: $resolved"
    }
    Write-Host "utility-resolution: $utility=$resolved ($busyHash)"
}
if (($env:PATH -split ';') -match '[\\/]msys64[\\/]usr[\\/]bin$') {
    throw "Native build PATH retained an MSYS usr/bin fallback: $env:PATH"
}
foreach ($override in @(
    @('ACLOCAL', $env:ACLOCAL, '--version'),
    @('AUTOCONF', $env:AUTOCONF, '--version'),
    @('AUTOM4TE', $env:AUTOM4TE, '--version'),
    @('AUTOMAKE', $env:AUTOMAKE, '--version'),
    @('RM', $env:RM, '--help')
)) {
    if ($override[1] -match '^[/\\](usr|bin)[/\\]') {
        throw "$($override[0]) unexpectedly resolved to a system fallback: $($override[1])"
    }
    $firstLine = (& $override[1] $override[2] | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0) { throw "$($override[0]) override failed its native smoke test" }
    Write-Host "generator-override: $($override[0])=$($override[1]) ($firstLine)"
}
$resolvedAutom4te = (Get-Command $env:AUTOM4TE -CommandType Application |
    Select-Object -First 1).Source
if ([IO.Path]::GetFullPath($resolvedAutom4te) -ne
    [IO.Path]::GetFullPath((Join-Path $generatorToolchain 'autom4te.exe'))) {
    throw "AUTOM4TE did not resolve to the pinned native launcher: $resolvedAutom4te"
}
Write-Host "generator-override: AUTOM4TE resolved through sealed PATH to $resolvedAutom4te"
& $nativePerl "-I$($env:autom4te_perllibdir)" -MAutom4te::C4che -e 1
if ($LASTEXITCODE -ne 0) { throw 'Relocated native Perl could not import Autom4te::C4che' }
Write-Host 'generator-override: relocated native Perl module import passed'
$makefileSource = Get-Content -LiteralPath (Join-Path $sourceRoot 'winsup\cygwin\Makefile.am') -Raw
if ($makefileSource.Contains('/bin/sh $(word 1,$^)') -or
    -not $makefileSource.Contains('$(SHELL) $(word 1,$^)')) {
    throw 'version.cc generation does not use the configured native $(SHELL)'
}
Write-Host 'generator-override: version.cc recipe uses configured native $(SHELL)'
if (-not $makefileSource.Contains(
        '.cygwin_dll_common=alloc,load,data,contents,share')) {
    throw 'Clang post-link fix does not mark .cygwin_dll_common shared'
}
Write-Host 'source-regression: Clang post-link fix marks .cygwin_dll_common shared'
$ptySource = Get-Content -LiteralPath (
    Join-Path $sourceRoot 'winsup\cygwin\fhandler\pty.cc') -Raw
if (-not $ptySource.Contains('static size_t ixput = 0;') -or
    $ptySource.Contains('static int ixput = 0;')) {
    throw 'PTY response buffer index does not match its size_t capacity'
}
Write-Host 'source-regression: PTY response buffer index uses size_t'

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
$targetDefines = '-D__CYGWIN__ -D__MSYS__ -U__WINT_TYPE__ -D__WINT_TYPE__=unsigned'
$targetCc = "$bin/clang.exe -target aarch64-w64-windows-gnu -fuse-ld=lld " +
    "--sysroot=$empty $targetDefines"
$targetCxx = "$bin/clang++.exe -target aarch64-w64-windows-gnu -fuse-ld=lld " +
    "--sysroot=$empty $targetDefines"
$env:CC = $buildCc
$env:CXX = $buildCxx
$env:CC_FOR_TARGET = $targetCc
$env:CXX_FOR_TARGET = $targetCxx
$env:MAKE = $makeCommand

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
        "--with-msys2-runtime-commit=$sourceCommit"
    if ($LASTEXITCODE -ne 0) { throw 'top-level configure failed' }
    & $makeCommand -j $Jobs all-target-newlib
    if ($LASTEXITCODE -ne 0) { throw 'newlib build failed' }
}
finally { Pop-Location }

$newlibBuild = "$build/aarch64-pc-cygwin/newlib"
$cygwinBuild = Join-Path $buildRoot 'aarch64-pc-cygwin\winsup'
$cygwinBuildPosix = To-Posix $cygwinBuild
New-Item -ItemType Directory -Path $cygwinBuild -Force | Out-Null
$windowsOverlay = Join-Path $Work 'windows-header-overlay'
$w32apiOverlay = Join-Path $windowsOverlay 'w32api'
New-Item -ItemType Directory -Path $w32apiOverlay -Force | Out-Null
$corecrtSource = Join-Path $crtPrefix 'include\corecrt.h'
$corecrtText = Get-Content -LiteralPath $corecrtSource -Raw
$mbstatePattern = '(?ms)^#if defined\(_UCRT\) \|\| defined\(__LARGE_MBSTATE_T\)\r?$' +
    '.*?^#endif\r?$'
$mbstateMatches = [regex]::Matches($corecrtText, $mbstatePattern)
if ($mbstateMatches.Count -ne 1) {
    throw 'MinGW corecrt.h mbstate_t block did not match the Cygwin overlay guard'
}
$mbstateBlock = $mbstateMatches[0].Value
$corecrtText = $corecrtText.Replace(
    $mbstateBlock, "#ifndef __CYGWIN__`n$mbstateBlock`n#endif")
[IO.File]::WriteAllText(
    (Join-Path $windowsOverlay 'corecrt.h'), $corecrtText,
    [Text.UTF8Encoding]::new($false))
foreach ($header in @('iphlpapi.h', 'mswsock.h', 'mstcpip.h', 'ntstatus.h',
    'shlobj.h', 'userenv.h', 'windows.h', 'winioctl.h', 'ws2tcpip.h')) {
    [IO.File]::WriteAllText(
        (Join-Path $w32apiOverlay $header), "#include <$header>`n",
        [Text.UTF8Encoding]::new($false))
}
$windowsOverlayPosix = To-Posix $windowsOverlay
$runtimeCc = "$bin/clang.exe -target aarch64-w64-windows-gnu -fuse-ld=lld " +
    "--sysroot=$empty $targetDefines " +
    "-L$cygwinBuildPosix/cygwin -I$src/winsup/cygwin/include " +
    "-B$newlibBuild -I$newlibBuild/targ-include -I$src/newlib/libc/include " +
    "-idirafter $windowsOverlayPosix -idirafter $crt/include -L$crt/lib -B$crt/lib"
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
        "--with-msys2-runtime-commit=$sourceCommit"
    if ($LASTEXITCODE -ne 0) { throw 'winsup configure failed' }
    & $makeCommand -C cygwin -j $Jobs
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
$env:MVP_WINDOWS_HEADERS = $windowsOverlayPosix
$env:MVP_RUNTIME_SOURCE = $src
$env:MVP_RUNTIME_BUILD = $build
$wrapper = To-Posix (Join-Path $sourceRoot '.github\checks\aarch64-cygwin-clang.sh')
$env:CC = "sh.exe $wrapper"
Push-Location $bashBuild
try {
    & $busy sh '../bash-source/bash-5.3/configure' `
        '--build=aarch64-pc-cygwin' '--host=aarch64-pc-cygwin' '--prefix=/usr' `
        '--without-bash-malloc' '--disable-nls' '--disable-rpath' '--enable-job-control'
    if ($LASTEXITCODE -ne 0) { throw 'Bash configure failed' }
    & $makeCommand -j $Jobs bash.exe
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
