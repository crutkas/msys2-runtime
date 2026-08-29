param(
    [Parameter(Mandatory)]
    [string]$SspPath,

    [Parameter(Mandatory)]
    [string]$ChildPath,

    [Parameter(Mandatory)]
    [string]$WorkingDirectory
)

$ErrorActionPreference = 'Stop'
$stdoutPath = Join-Path $WorkingDirectory 'ssp.stdout'
$stderrPath = Join-Path $WorkingDirectory 'ssp.stderr'
$childPidPath = Join-Path $WorkingDirectory 'ssp-child.pid'
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $SspPath
$startInfo.UseShellExecute = $false
$startInfo.WorkingDirectory = $WorkingDirectory
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.EnvironmentVariables['SSP_VALIDATION_EVIDENCE'] = '1'
$startInfo.EnvironmentVariables['LAYER5_SSP_CHILD_PID_FILE'] = $childPidPath
$startInfo.Arguments = "-d -s -v 0x1000 0x2000 `"$ChildPath`""

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$started = $false
try {
    if (!$process.Start()) {
        throw 'Failed to start native ARM64 SSP'
    }
    $started = $true
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(30000)) {
        $process.Kill()
        $process.WaitForExit()
        throw 'Native ARM64 SSP timed out after 30 seconds'
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    Set-Content -LiteralPath $stdoutPath -Value $stdout
    Set-Content -LiteralPath $stderrPath -Value $stderr

    if ($process.ExitCode -ne 0) {
        throw "Native ARM64 SSP failed with exit code $($process.ExitCode)`n$stderr"
    }
    if ($stdout -notmatch 'SSP_CHILD_OK') {
        throw "Controlled SSP child did not complete`n$stdout"
    }
    $evidence = [regex]::Match(
        $stdout,
        'SSP_VALIDATION breakpoints_inserted=(\d+) breakpoints_restored=(\d+) cache_flushes=(\d+) pstate_updates=(\d+) lr_edges=(\d+)'
    )
    if (!$evidence.Success) {
        throw "SSP validation evidence is missing`n$stdout"
    }
    $counts = 1..5 | ForEach-Object { [int]$evidence.Groups[$_].Value }
    if ($counts.Where({ $_ -lt 1 }).Count -ne 0) {
        throw "SSP did not exercise every required debugger path: $($evidence.Value)"
    }
    if ($counts[2] -lt ($counts[0] + $counts[1])) {
        throw "SSP cache flush count does not cover breakpoint writes: $($evidence.Value)"
    }
    Write-Output $evidence.Value
}
finally {
    if ($started -and !$process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }
    $process.Dispose()
    if (Test-Path -LiteralPath $childPidPath) {
        $childPid = (Get-Content -LiteralPath $childPidPath -Raw).Trim()
        if ($childPid -match '^\d+$') {
            $childProcess = Get-Process -Id ([int]$childPid) -ErrorAction SilentlyContinue
            if ($childProcess) {
                Stop-Process -Id $childProcess.Id -Force
                throw "Controlled SSP child $childPid survived debugger cleanup"
            }
        }
    }
}
