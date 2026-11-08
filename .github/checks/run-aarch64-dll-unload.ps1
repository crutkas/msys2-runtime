param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeDirectory,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne
    [System.Runtime.InteropServices.Architecture]::Arm64) {
    throw 'The DLL unload regression requires a native Windows ARM64 host.'
}

$runtime = (Resolve-Path $RuntimeDirectory).Path
$probe = Join-Path $runtime 'aarch64-dll-unload-smoke.exe'
$module = Join-Path $runtime 'aarch64-dll-unload-module.dll'
$entry0 = Join-Path $runtime 'aarch64-dll-unload-entry0.dll'
$inputs = @(
    (Join-Path $runtime 'msys-2.0.dll'),
    $probe,
    $module,
    $entry0
)
foreach ($input in $inputs) {
    if (-not (Test-Path $input -PathType Leaf)) {
        throw "Missing DLL unload regression input: $input"
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
$evidence = (Resolve-Path $EvidenceDirectory).Path
$os = Get-CimInstance Win32_OperatingSystem
[ordered]@{
    schema = 1
    architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    os = $os.Caption
    os_version = $os.Version
    os_build = $os.BuildNumber
    powershell = $PSVersionTable.PSVersion.ToString()
} | ConvertTo-Json | Set-Content (Join-Path $evidence 'environment.json')
$inputs | ForEach-Object {
    $file = Get-Item $_
    '{0} *{1}' -f
        (Get-FileHash -Algorithm SHA256 $file.FullName).Hash.ToLowerInvariant(),
        $file.Name
} | Set-Content (Join-Path $evidence 'INPUT_SHA256SUMS')

$matrix = @(
    @{ Name = 'loadlibrary-once'; Mode = 'loadlibrary'; Path = $module; Cycles = 1 },
    @{ Name = 'loadlibrary-repeat'; Mode = 'loadlibrary'; Path = $module; Cycles = 10 },
    @{ Name = 'native-thread-fallback'; Mode = 'native-thread'; Path = $module; Cycles = 10 },
    @{ Name = 'dlopen-now'; Mode = 'dlopen-now'; Path = $module; Cycles = 10 },
    @{ Name = 'dlopen-lazy'; Mode = 'dlopen-lazy'; Path = $module; Cycles = 10 },
    @{ Name = 'dont-resolve'; Mode = 'dont-resolve'; Path = $module; Cycles = 3 },
    @{ Name = 'entry0'; Mode = 'entry0'; Path = $entry0; Cycles = 3 }
)

Push-Location $runtime
try {
    "case`tstatus" | Set-Content (Join-Path $evidence 'matrix.tsv')
    foreach ($case in $matrix) {
        $output = & $probe $case.Mode $case.Path $case.Cycles 2>&1
        $status = $LASTEXITCODE
        $output | Set-Content (Join-Path $evidence "$($case.Name).txt")
        "$($case.Name)`t$status" |
            Add-Content (Join-Path $evidence 'matrix.tsv')
        $events = Join-Path $runtime 'aarch64-dll-unload-events.txt'
        if (Test-Path $events) {
            Copy-Item $events (Join-Path $evidence "$($case.Name)-events.txt")
        }
        if ($status -ne 0) {
            throw "$($case.Name) failed with exit code $status"
        }
    }
}
finally {
    Pop-Location
}

$cdb = 'C:\Program Files (x86)\Windows Kits\10\Debuggers\arm64\cdb.exe'
if (-not (Test-Path $cdb -PathType Leaf)) {
    throw "The sealed native ARM64 debugger was not found: $cdb"
}
$cdbTranscript = Join-Path $evidence 'cdb-live.txt'
$cdbCommands = 'sxe av; bp KERNELBASE!FreeLibrary ".echo FREE_LIBRARY_ENTRY; r; lm m aarch64_dll_unload_module; gc"; g; .echo TARGET_EXIT; q'
Push-Location $runtime
try {
    $cdbOutput = @(& $cdb -o -logo $cdbTranscript -c $cdbCommands `
        $probe loadlibrary $module 1 2>&1)
    $cdbStatus = $LASTEXITCODE
}
finally {
    Pop-Location
}
$cdbOutput | Set-Content (Join-Path $evidence 'cdb-console.txt')
[ordered]@{
    path = $cdb
    sha256 = (Get-FileHash -Algorithm SHA256 $cdb).Hash.ToLowerInvariant()
    command = "$cdb -o -logo $cdbTranscript -c '$cdbCommands' $probe loadlibrary $module 1"
    exit_code = $cdbStatus
} | ConvertTo-Json | Set-Content (Join-Path $evidence 'cdb-command.json')
$cdbText = (@($cdbOutput) + @(Get-Content $cdbTranscript)) -join "`n"
if ($cdbStatus -ne 0 -or
    $cdbText -notmatch 'FREE_LIBRARY_ENTRY' -or
    $cdbText -notmatch 'TARGET_EXIT' -or
    $cdbText -notmatch 'aarch64-dll-unload=pass' -or
    $cdbText -match '(?i)c0000005|access violation') {
    throw "cdb unload proof failed with exit code $cdbStatus."
}

[ordered]@{
    schema = 1
    cases = $matrix.Count
    direct_matrix = 'pass'
    cdb_unload = 'pass'
    unloaded_module_execute = 'absent'
    result = 'pass'
} | ConvertTo-Json | Set-Content (Join-Path $evidence 'summary.json')
