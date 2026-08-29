[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RuntimeRoot,
    [Parameter(Mandatory)] [string] $RuntimeSource,
    [Parameter(Mandatory)] [string] $RuntimeBuild,
    [Parameter(Mandatory)] [string] $ClangPrefix,
    [Parameter(Mandatory)] [string] $CrtPrefix,
    [Parameter(Mandatory)] [string] $BusyBox,
    [Parameter(Mandatory)] [string] $MinGitRoot,
    [Parameter(Mandatory)] [string] $EvidencePath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

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
    if ((Get-PeMachine $Path) -ne 0xAA64) { throw "$Class is not native ARM64: $Path" }
    $script:processes.Add([ordered]@{ class = $Class; path = $Path; machine = '0xAA64' })
}

function Invoke-Native([string] $Path, [string[]] $Arguments, [string] $Class) {
    Assert-Arm64 $Path $Class
    & $Path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Class failed with exit code $LASTEXITCODE" }
}

$processes = [Collections.Generic.List[object]]::new()
$tests = [Collections.Generic.List[string]]::new()
$bash = Join-Path $RuntimeRoot 'usr\bin\bash.exe'
$runtimeDll = Join-Path $RuntimeRoot 'usr\bin\msys-2.0.dll'
$git = Join-Path $RuntimeRoot 'cmd\git.exe'
$clang = Join-Path $ClangPrefix 'clang.exe'
Assert-Arm64 $runtimeDll 'runtime DLL'
Assert-Arm64 $bash 'Bash'
Assert-Arm64 $git 'Git'
Assert-Arm64 $clang 'Clang'
Assert-Arm64 $BusyBox 'BusyBox shell'
$readobj = Join-Path $ClangPrefix 'llvm-readobj.exe'
Assert-Arm64 $readobj 'LLVM PE inspector'
$peReport = (& $readobj --file-headers --sections --coff-imports --coff-exports $runtimeDll |
    Out-String)
foreach ($required in @(
    'IMAGE_FILE_MACHINE_ARM64',
    'IMAGE_DLL_CHARACTERISTICS_DYNAMIC_BASE',
    'IMAGE_DLL_CHARACTERISTICS_NX_COMPAT',
    'Name: .reloc',
    'Name: .cygwin_',
    'IMAGE_SCN_MEM_SHARED',
    'Name: KERNEL32.dll',
    'Name: ntdll.dll'
)) {
    if (-not $peReport.Contains($required)) { throw "Runtime PE invariant missing: $required" }
}
$exportCount = ([regex]::Matches($peReport, '(?m)^\s+Ordinal:')).Count
if ($exportCount -lt 1700) { throw "Unexpectedly small runtime export table: $exportCount" }

$env:MVP_CLANG_PREFIX = $ClangPrefix.Replace('\', '/')
$env:MVP_RUNTIME_SOURCE = $RuntimeSource.Replace('\', '/')
$env:MVP_RUNTIME_BUILD = $RuntimeBuild.Replace('\', '/')
$env:MVP_CRT_PREFIX = $CrtPrefix.Replace('\', '/')
$env:MVP_CLANG_RESOURCE_DIR = (& $clang -print-resource-dir).Trim().Replace('\', '/')
$smokeSource = Join-Path $RuntimeSource '.github\checks\aarch64-runtime-smoke.c'
$wrapper = Join-Path $RuntimeSource '.github\checks\aarch64-cygwin-clang.sh'
$smokeExe = Join-Path $RuntimeRoot 'usr\bin\runtime-smoke.exe'
Invoke-Native $BusyBox @('sh', $wrapper, $smokeSource, '-o', $smokeExe) 'runtime smoke compiler'
Assert-Arm64 $smokeExe 'runtime-linked smoke executable'

$tmp = Join-Path $RuntimeRoot 'tmp'
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$oldLocation = Get-Location
$oldPath = $env:PATH
$env:PATH = "$(Join-Path $RuntimeRoot 'usr\bin');$(Join-Path $RuntimeRoot 'cmd');" +
    "$(Join-Path $RuntimeRoot 'clangarm64\bin');$oldPath"
$env:HOME = Join-Path $RuntimeRoot 'home'
$env:MSYS2_PATH_TYPE = 'inherit'
$env:MSYS = 'winsymlinks:sys'
New-Item -ItemType Directory -Path $env:HOME -Force | Out-Null
try {
    Set-Location (Join-Path $RuntimeRoot 'usr\bin')
    $windowsPath = Join-Path $tmp 'path-conversion'
    Invoke-Native $smokeExe @($windowsPath) 'runtime behavior suite'
    $tests.Add('startup/cwd/path conversion')
    $tests.Add("PE load/import/export/relocation/ASLR ($exportCount exports)")
    $tests.Add('pthread/TLS')
    $tests.Add('fork/pipes')
    $tests.Add('signals/SEH')
    $tests.Add('AF_UNIX sockets')
    $tests.Add('filesystem/hardlink/symlink')
    $tests.Add('locale C baseline without catalogs')
    $tests.Add('posix_spawn/exec')

    Invoke-Native $bash @('-lc',
        'set -eu; x=ARM64; test "$(printf "%s" "$x" | tr A-Z a-z)" = arm64; ' +
        '(exit 7) || test $? = 7; printf "bash-smoke: %s %s\n" "$MACHTYPE" "$PWD"') `
        'Bash workflow'
    $tests.Add('Bash variables/command substitution/pipeline/subshell')

    $gitScript = @'
set -eu
export PATH=/cmd:/clangarm64/bin:/usr/bin
export HOME=/home
rm -rf /tmp/git-smoke
mkdir -p /tmp/git-smoke/repo
cd /tmp/git-smoke/repo
git init -q
git config user.name "Native ARM64"
git config user.email native-arm64@example.invalid
printf "native\n" > tracked.txt
git add tracked.txt
git commit -q -m native
cd ..
git clone -q repo clone
test "$(git -C clone log -1 --format=%s)" = native
printf "git-smoke: version=%s commit=%s\n" "$(git --version)" "$(git -C repo rev-parse --short HEAD)"
'@
    $gitScriptPath = Join-Path $tmp 'git-smoke.sh'
    Set-Content -LiteralPath $gitScriptPath -Value $gitScript -Encoding utf8NoBOM
    Invoke-Native $bash @($gitScriptPath) 'native Bash and Git workflow'
    $tests.Add('Git init/add/commit')
    $tests.Add('Git local clone/log')

    $x64Child = Join-Path $MinGitRoot 'usr\bin\true.exe'
    if ((Get-PeMachine $x64Child) -ne 0x8664) {
        throw "Expected MinGit usr/bin/true.exe to be the explicitly emulated x64 child"
    }
    $x64Unix = '/' + $x64Child.Replace('\', '/').Replace(':', '')
    Invoke-Native $bash @('-lc', "'$x64Unix'") `
        'Bash spawning explicitly emulated x64 child'
    $processes.Add([ordered]@{
        class = 'explicitly emulated x64 interoperability child'
        path = $x64Child
        machine = '0x8664'
    })
    $tests.Add('x64 child interoperability (explicitly emulated)')
}
finally {
    Set-Location $oldLocation
    $env:PATH = $oldPath
}

[ordered]@{
    schema = 1
    process_attestation_count = $processes.Count
    behavioral_test_count = $tests.Count
    processes = $processes
    tests = $tests
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $EvidencePath -Encoding utf8NoBOM
Write-Host "MVP validation passed: $($processes.Count) process attestations, $($tests.Count) behavioral tests"
