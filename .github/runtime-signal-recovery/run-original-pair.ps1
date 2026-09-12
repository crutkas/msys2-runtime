param(
    [Parameter(Mandatory = $true)]
    [string] $ArtifactDirectory,

    [ValidateRange(1, 10)]
    [int] $Repetitions = 3,

    [string] $ProbePs
)

$ErrorActionPreference = 'Stop'

$sourceRoot = 'C:\ag-bash907-20260911-02'
$source907 = Join-Path $sourceRoot 'original-controller-907-01'
$sourceD70 = Join-Path $sourceRoot 'original-controller-d70-01'
$expected = [ordered]@{
    controller = 'e4bf9ab340f57dcb1c6456c2e8d0454cb31fac0762fdc0447d75759447aa493a'
    bash = '39ef42f62906be249b650dd9e0760109161c40c5b4e047093ef7e16b138c5d6a'
    iconv = '86aa5600dd67dc8985ed4f218420549ed46539ae739dbbeaf11f68d0c1db4215'
    intl = '44c50b20168751f4b5a0107a7b85c7e9ff9565062b1be2b86c65eb5beeaa339c'
    runtime907 = '907afa099a69aa3c13d4e3b30eeba18c4a6b1766d5fa39b4746fae23c3f9e76c'
    runtimeD70 = 'd70cfb46ed6bfa643a6ab557a71008e86043d8a04e5ce2d33549e4e95a49117d'
}

function Get-Sha256 {
    param([string] $Path)
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-Hash {
    param([string] $Path, [string] $Expected)
    $actual = Get-Sha256 $Path
    if ($actual -ne $Expected) {
        throw "hash mismatch for $Path expected=$Expected actual=$actual"
    }
}

function ConvertTo-MsysPath {
    param([string] $Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "cannot convert path to MSYS form: $full"
    }
    "/$($Matches[1].ToLowerInvariant())/$($Matches[2].Replace('\', '/'))"
}

function Read-SharedText {
    param([string] $Path)
    $stream = [IO.FileStream]::new(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
        try {
            $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-DescendantSnapshot {
    param(
        [int] $RootPid,
        [string] $OwnedRoot
    )
    $all = @(Get-CimInstance Win32_Process)
    $wanted = [Collections.Generic.HashSet[int]]::new()
    $wanted.Add($RootPid) | Out-Null
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($item in $all) {
            if ($wanted.Contains([int]$item.ParentProcessId) -and !$wanted.Contains([int]$item.ProcessId)) {
                $wanted.Add([int]$item.ProcessId) | Out-Null
                $changed = $true
            }
        }
    }
    @($all | Where-Object {
        $wanted.Contains([int]$_.ProcessId) -or
        ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($OwnedRoot, [StringComparison]::OrdinalIgnoreCase))
    })
}

function Save-PgidProbe {
    param(
        [string] $Bin,
        [string] $Destination
    )
    $output = @(& (Join-Path $Bin 'ps-probe.exe'))
    $exitCode = $LASTEXITCODE
    [ordered]@{
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        exit_code = $exitCode
        output = $output
    } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $Destination -Encoding utf8NoBOM
}

function Invoke-Run {
    param(
        [string] $Mode,
        [int] $Iteration,
        [bool] $EnableProbe
    )

    $source = if ($Mode -eq '907') { $source907 } else { $sourceD70 }
    $suffix = if ($EnableProbe) { 'probed' } else { 'unprobed' }
    $runRoot = Join-Path $ArtifactDirectory "$Mode-$suffix-$('{0:d2}' -f $Iteration)"
    if (Test-Path $runRoot) {
        throw "fresh output required: $runRoot"
    }
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'runtime') -Destination $runRoot -Recurse
    foreach ($name in 'home', 'temp', 'native-exits') {
        New-Item -ItemType Directory -Path (Join-Path $runRoot $name) | Out-Null
    }

    $bin = Join-Path $runRoot 'runtime\usr\bin'
    $controller = Join-Path $bin 'bash907-pty.exe'
    $bash = Join-Path $bin 'bash.exe'
    Assert-Hash $controller $expected.controller
    Assert-Hash $bash $expected.bash
    Assert-Hash (Join-Path $bin 'msys-iconv-2.dll') $expected.iconv
    Assert-Hash (Join-Path $bin 'msys-intl-8.dll') $expected.intl
    Assert-Hash (Join-Path $bin 'msys-2.0.dll') $(if ($Mode -eq '907') { $expected.runtime907 } else { $expected.runtimeD70 })

    if ($EnableProbe) {
        if (!$ProbePs) {
            throw 'ProbePs is required for probed runs'
        }
        Assert-Hash $ProbePs 'c3deba68c4dbb984c4f7154fed817aa6fe147f9fc0b654ce716f7a61fb56a2b0'
        Copy-Item -LiteralPath $ProbePs -Destination (Join-Path $bin 'ps-probe.exe')
    }

    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $controller
    $info.ArgumentList.Add($bash)
    $info.ArgumentList.Add((Join-Path $runRoot 'controller-result.json'))
    $info.WorkingDirectory = $runRoot
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $environment = [ordered]@{
        SystemRoot = $env:SystemRoot
        WINDIR = $env:WINDIR
        COMSPEC = $env:COMSPEC
        PATHEXT = $env:PATHEXT
        PATH = "$bin;$env:SystemRoot\System32"
        HOME = ConvertTo-MsysPath (Join-Path $runRoot 'home')
        USERPROFILE = Join-Path $runRoot 'home'
        TMP = Join-Path $runRoot 'temp'
        TEMP = Join-Path $runRoot 'temp'
        TMPDIR = ConvertTo-MsysPath (Join-Path $runRoot 'temp')
        LC_ALL = 'C.UTF-8'
        LANG = 'C.UTF-8'
        MSYSTEM = 'CYGWIN'
        MSYS = 'winsymlinks:sys'
        TERM = 'xterm-256color'
        TERMINFO = "$(ConvertTo-MsysPath (Join-Path $runRoot 'runtime\usr\share\terminfo'))"
        INPUTRC = "$(ConvertTo-MsysPath (Join-Path $runRoot 'runtime\etc\inputrc'))"
        OMP_NUM_THREADS = '1'
        OPENBLAS_NUM_THREADS = '1'
        MAKEFLAGS = '-j1'
        WOARM64_NATIVE_ARG_CONVERSION = 'none'
        WOARM64_NATIVE_TEST_ROOT = $ArtifactDirectory
        WOARM64_NATIVE_EXIT_DIR = Join-Path $runRoot 'native-exits'
        PS1 = 'BASH907__> '
        PS2 = 'BASH907_CONT> '
        HISTFILE = ConvertTo-MsysPath (Join-Path $runRoot 'history')
        PROMPT_COMMAND = ''
        HISTCONTROL = ''
    }
    $info.Environment.Clear()
    foreach ($entry in $environment.GetEnumerator()) {
        $info.Environment[$entry.Key] = $entry.Value
    }

    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $generations = @{}
    $handles = @{}
    $snapshots = [Collections.Generic.List[object]]::new()
    $ready = Join-Path $runRoot 'editor-ready.json'
    $continue = Join-Path $runRoot 'continue'
    $transcript = Join-Path $runRoot 'pty-output.bin'
    $deadline = [DateTime]::UtcNow.AddSeconds(150)
    $continued = $false
    $initialProbe = $false
    $foregroundProbe = $false

    while (!$process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        if ($EnableProbe) {
            $snapshot = @(Get-DescendantSnapshot $process.Id $runRoot)
            foreach ($item in $snapshot) {
                $key = "$($item.ProcessId):$($item.CreationDate)"
                if (!$generations.ContainsKey($key)) {
                    $generations[$key] = [ordered]@{
                        process_id = [int]$item.ProcessId
                        parent_process_id = [int]$item.ParentProcessId
                        creation_date = "$($item.CreationDate)"
                        name = $item.Name
                        executable_path = $item.ExecutablePath
                        command_line = $item.CommandLine
                        first_seen_utc = [DateTime]::UtcNow.ToString('o')
                    }
                    try {
                        $handles[$key] = [Diagnostics.Process]::GetProcessById([int]$item.ProcessId)
                    } catch {
                    }
                }
            }
            $snapshots.Add([ordered]@{
                timestamp_utc = [DateTime]::UtcNow.ToString('o')
                processes = @($snapshot | Select-Object ProcessId, ParentProcessId, CreationDate, Name, ExecutablePath, CommandLine)
            })
        }

        if (!$continued -and (Test-Path $ready)) {
            'go' | Set-Content -LiteralPath $continue -Encoding ascii
            $continued = $true
        }
        if ($EnableProbe -and (Test-Path $transcript)) {
            $text = Read-SharedText $transcript
            $pipelineCount = ([regex]::Matches($text, [regex]::Escape('sleep 60 | cat'))).Count
            if (!$initialProbe -and $pipelineCount -ge 1) {
                Save-PgidProbe $bin (Join-Path $runRoot 'pgid-initial.json')
                $initialProbe = $true
            }
            if (!$foregroundProbe -and $pipelineCount -ge 3) {
                Save-PgidProbe $bin (Join-Path $runRoot 'pgid-foreground.json')
                $foregroundProbe = $true
            }
        }
        Start-Sleep -Milliseconds 10
    }
    if (!$process.HasExited) {
        Stop-Process -Id $process.Id
        throw "controller timed out in $runRoot"
    }
    $process.WaitForExit()
    Start-Sleep -Seconds 2

    $rawExits = foreach ($entry in $handles.GetEnumerator()) {
        $handle = $entry.Value
        $generation = $generations[$entry.Key]
        $exit = $null
        $exited = $false
        try {
            $handle.Refresh()
            $exited = $handle.HasExited
            if ($exited) {
                $exit = [uint32]$handle.ExitCode
            }
        } catch {
        }
        [ordered]@{
            process_id = $generation.process_id
            creation_date = $generation.creation_date
            name = $generation.name
            executable_path = $generation.executable_path
            command_line = $generation.command_line
            exited = $exited
            windows_exit_dword = $exit
        }
    }

    $remaining = @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.ExecutablePath -and
                $_.ExecutablePath.StartsWith($runRoot, [StringComparison]::OrdinalIgnoreCase)
            }
    )
    foreach ($item in $remaining) {
        Stop-Process -Id ([int]$item.ProcessId)
    }
    $cases = if (Test-Path (Join-Path $runRoot 'cases.tsv')) {
        @(Get-Content (Join-Path $runRoot 'cases.tsv') | ForEach-Object {
            $parts = $_ -split "`t", 2
            [ordered]@{ name = $parts[0]; status = $parts[1] }
        })
    } else {
        @()
    }
    $foregroundText = if (Test-Path $transcript) {
        Read-SharedText $transcript
    } else {
        ''
    }
    $foregroundMatch = [regex]::Match($foregroundText, 'CASE:foreground:(\d+):(\d+)')
    $result = [ordered]@{
        schema = 1
        mode = $Mode
        iteration = $Iteration
        probed = $EnableProbe
        root = $runRoot
        controller_sha256 = Get-Sha256 $controller
        bash_sha256 = Get-Sha256 $bash
        runtime_sha256 = Get-Sha256 (Join-Path $bin 'msys-2.0.dll')
        iconv_sha256 = Get-Sha256 (Join-Path $bin 'msys-iconv-2.dll')
        intl_sha256 = Get-Sha256 (Join-Path $bin 'msys-intl-8.dll')
        controller_pid = $process.Id
        controller_exit_dword = [uint32]$process.ExitCode
        controller_stdout = $stdout.Result
        controller_stderr = $stderr.Result
        foreground_case_seen = $foregroundMatch.Success
        foreground_assertion_status = if ($foregroundMatch.Success) { [int]$foregroundMatch.Groups[1].Value } else { $null }
        foreground_shell_status = if ($foregroundMatch.Success) { [int]$foregroundMatch.Groups[2].Value } else { $null }
        cases = $cases
        generations = @($generations.Values)
        raw_exits = @($rawExits)
        remaining_before_cleanup = @($remaining | Select-Object ProcessId, ParentProcessId, CreationDate, Name, ExecutablePath, CommandLine)
        snapshot_count = $snapshots.Count
    }
    $result | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $runRoot 'bounded-result.json') -Encoding utf8NoBOM
    $snapshots | ConvertTo-Json -Depth 7 |
        Set-Content -LiteralPath (Join-Path $runRoot 'process-snapshots.json') -Encoding utf8NoBOM
    $result
}

New-Item -ItemType Directory -Force -Path $ArtifactDirectory | Out-Null
Assert-Hash (Join-Path $source907 'runtime\usr\bin\bash907-pty.exe') $expected.controller

$results = [Collections.Generic.List[object]]::new()
foreach ($iteration in 1..$Repetitions) {
    $results.Add((Invoke-Run -Mode '907' -Iteration $iteration -EnableProbe $false))
    $results.Add((Invoke-Run -Mode 'd70' -Iteration $iteration -EnableProbe $false))
}
if ($ProbePs) {
    $results.Add((Invoke-Run -Mode '907' -Iteration 1 -EnableProbe $true))
    $results.Add((Invoke-Run -Mode 'd70' -Iteration 1 -EnableProbe $true))
}

$summary = [ordered]@{
    schema = 1
    generated_utc = [DateTime]::UtcNow.ToString('o')
    repetitions = $Repetitions
    probe_runs = [bool]$ProbePs
    results = @($results | ForEach-Object {
        [ordered]@{
            mode = $_.mode
            iteration = $_.iteration
            probed = $_.probed
            controller_exit_dword = $_.controller_exit_dword
            foreground_case_seen = $_.foreground_case_seen
            foreground_assertion_status = $_.foreground_assertion_status
            foreground_shell_status = $_.foreground_shell_status
            sleep_exits = @($_.raw_exits | Where-Object { $_ -and $_.name -eq 'sleep.exe' } | ForEach-Object {
                [ordered]@{
                    process_id = $_.process_id
                    creation_date = $_.creation_date
                    windows_exit_dword = $_.windows_exit_dword
                }
            })
            cat_exits = @($_.raw_exits | Where-Object { $_ -and $_.name -eq 'cat.exe' } | ForEach-Object {
                [ordered]@{
                    process_id = $_.process_id
                    creation_date = $_.creation_date
                    windows_exit_dword = $_.windows_exit_dword
                }
            })
            remaining_count = $_.remaining_before_cleanup.Count
            root = $_.root
        }
    })
}
$summary | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $ArtifactDirectory 'pair-summary.json') -Encoding utf8NoBOM
$summary | ConvertTo-Json -Depth 8
