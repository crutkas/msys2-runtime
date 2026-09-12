param(
    [Parameter(Mandatory = $true)]
    [string] $ArtifactDirectory,

    [Parameter(Mandatory = $true)]
    [string] $FixtureSourceBin
)

$ErrorActionPreference = 'Stop'

$fixture = Join-Path $ArtifactDirectory 'fixture'
$bin = Join-Path $fixture 'usr\bin'
$qualification = Join-Path $fixture 'qualification'
$tmp = Join-Path $fixture 'tmp'

New-Item -ItemType Directory -Force -Path $bin, $qualification, $tmp | Out-Null
Remove-Item -LiteralPath (Join-Path $qualification 'ready') -Force -ErrorAction SilentlyContinue

foreach ($name in 'ps.exe', 'mount.exe', 'cygpath.exe') {
    Copy-Item -LiteralPath (Join-Path $ArtifactDirectory "build\$name") -Destination (Join-Path $bin $name) -Force
}
foreach ($name in 'bash.exe', 'cat.exe', 'sleep.exe', 'msys-2.0.dll', 'msys-iconv-2.dll', 'msys-intl-8.dll') {
    Copy-Item -LiteralPath (Join-Path $FixtureSourceBin $name) -Destination (Join-Path $bin $name) -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'qualify-ps.sh') -Destination (Join-Path $bin 'qualify-ps.sh') -Force
Copy-Item -LiteralPath (Join-Path $ArtifactDirectory 'source\COPYING') -Destination (Join-Path $fixture 'CYGWIN_LICENSE') -Force

$oldPath = $env:PATH
$env:PATH = "$bin;$oldPath"
$catProcess = $null
$mountProcess = $null
$cygpathProcess = $null
Push-Location $fixture
try {
    & (Join-Path $bin 'ps.exe') --help 2>&1 |
        Set-Content -LiteralPath (Join-Path $qualification 'help.txt') -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) {
        throw "ps --help failed with exit code $LASTEXITCODE"
    }

    & (Join-Path $bin 'ps.exe') --version 2>&1 |
        Set-Content -LiteralPath (Join-Path $qualification 'version.txt') -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) {
        throw "ps --version failed with exit code $LASTEXITCODE"
    }

    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $bin 'bash.exe'
    $info.ArgumentList.Add('/usr/bin/qualify-ps.sh')
    $info.WorkingDirectory = $fixture
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['PATH'] = "$bin;$oldPath"
    $process = [Diagnostics.Process]::Start($info)
    $processOutput = $process.StandardOutput.ReadToEndAsync()
    $processError = $process.StandardError.ReadToEndAsync()

    $ready = Join-Path $qualification 'ready'
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (!(Test-Path $ready) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
    }
    if (!(Test-Path $ready)) {
        throw 'qualification script did not become ready'
    }

    $snapshot = Get-CimInstance Win32_Process
    $direct = @($snapshot | Where-Object ParentProcessId -eq $process.Id)
    $grandchildren = @($snapshot | Where-Object ParentProcessId -in @($direct.ProcessId))
    $descendants = @($direct) + @($grandchildren)

    if (!$process.WaitForExit(30000)) {
        throw 'qualification bash did not exit after the controlled child closed'
    }
    $processOutput.Result |
        Set-Content -LiteralPath (Join-Path $qualification 'bash.stdout.txt') -Encoding utf8NoBOM
    $stderr = $processError.Result
    $stderr | Set-Content -LiteralPath (Join-Path $qualification 'bash.stderr.txt') -Encoding utf8NoBOM
    if (!$process.HasExited -or $process.ExitCode -ne 0) {
        throw "qualification bash failed: exited=$($process.HasExited) code=$($process.ExitCode) stderr=$stderr"
    }

    $direct | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CreationDate, CommandLine |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $qualification 'win32-direct-children.json') -Encoding utf8NoBOM
    $descendants | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CreationDate, CommandLine |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $qualification 'win32-descendants.json') -Encoding utf8NoBOM

    $parentCygwin = [int](Get-Content (Join-Path $qualification 'parent-cygwin-pid.txt'))
    $childCygwin = [int](Get-Content (Join-Path $qualification 'child-cygwin-pid.txt'))
    $default = Get-Content (Join-Path $qualification 'default.txt')
    $parentLine = $default | Where-Object { $_ -match "^.\s+$parentCygwin\s+" } | Select-Object -First 1
    $childLine = $default | Where-Object { $_ -match "^.\s+$childCygwin\s+" } | Select-Object -First 1
    if (!$parentLine -or !$childLine) {
        throw "default ps output missing parent or child: parent=$parentLine child=$childLine"
    }

    $parentMatch = [regex]::Match($parentLine, "^.\s+$parentCygwin\s+\d+\s+\d+\s+(\d+)")
    $childMatch = [regex]::Match($childLine, "^.\s+$childCygwin\s+\d+\s+\d+\s+(\d+)")
    if (!$parentMatch.Success -or !$childMatch.Success) {
        throw 'Perl cygwin.t PID/WINPID regular expression did not match default ps output'
    }

    $parentWindows = [int]$parentMatch.Groups[1].Value
    $childWindows = [int]$childMatch.Groups[1].Value
    $actualParent = $snapshot | Where-Object ProcessId -eq $parentWindows | Select-Object -First 1
    $actualChild = $snapshot | Where-Object ProcessId -eq $childWindows | Select-Object -First 1
    if ($parentWindows -ne $process.Id -or !$actualParent -or !$actualChild -or $actualChild.Name -ne 'sleep.exe') {
        throw 'ps PID/WINPID output did not match the controlled Win32 process tree'
    }

    [ordered]@{
        parent_windows_pid = $parentWindows
        parent_cygwin_pid = $parentCygwin
        child_windows_pid = $childWindows
        child_cygwin_pid = $childCygwin
        parent_line = $parentLine
        child_line = $childLine
        perl_regex_matched = $true
        parent_process = $actualParent |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CreationDate, CommandLine
        child_process = $actualChild |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CreationDate, CommandLine
        exit_code = $process.ExitCode
    } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $qualification 'pid-proof.json') -Encoding utf8NoBOM

    $catInfo = [Diagnostics.ProcessStartInfo]::new()
    $catInfo.FileName = Join-Path $bin 'bash.exe'
    $catInfo.ArgumentList.Add('-lc')
    $catInfo.ArgumentList.Add('exec /usr/bin/cat')
    $catInfo.WorkingDirectory = $fixture
    $catInfo.UseShellExecute = $false
    $catInfo.RedirectStandardInput = $true
    $catInfo.RedirectStandardOutput = $true
    $catInfo.RedirectStandardError = $true
    $catInfo.Environment['PATH'] = "$bin;$oldPath"
    $catProcess = [Diagnostics.Process]::Start($catInfo)
    $catOutput = $catProcess.StandardOutput.ReadToEndAsync()
    $catError = $catProcess.StandardError.ReadToEndAsync()
    Start-Sleep -Milliseconds 300

    $catDefault = @(& (Join-Path $bin 'ps.exe'))
    if ($LASTEXITCODE -ne 0) {
        throw "default ps for controlled cat failed with exit code $LASTEXITCODE"
    }
    $catDefault |
        Set-Content -LiteralPath (Join-Path $qualification 'cat-default.txt') -Encoding utf8NoBOM
    $catLine = $catDefault |
        Where-Object { $_ -match '/usr/bin/cat$' } |
        Select-Object -First 1
    if (!$catLine) {
        throw 'default ps output did not list the controlled /usr/bin/cat process'
    }
    $catMatch = [regex]::Match($catLine, "^.\s+(\d+)\s+\d+\s+\d+\s+(\d+)")
    $catCygwin = [int]$catMatch.Groups[1].Value
    $catWindows = [int]$catMatch.Groups[2].Value
    if ($catWindows -ne $catProcess.Id) {
        $catNative = Get-CimInstance Win32_Process -Filter "ProcessId=$catWindows" |
            Select-Object -First 1
    } else {
        $catNative = Get-CimInstance Win32_Process -Filter "ProcessId=$($catProcess.Id)" |
            Select-Object -First 1
    }
    if (!$catNative) {
        throw "Perl cygwin.t WINPID field $catWindows did not identify a live Win32 process"
    }
    @(& (Join-Path $bin 'ps.exe') -p $catCygwin) |
        Set-Content -LiteralPath (Join-Path $qualification 'cat-process.txt') -Encoding utf8NoBOM
    $catProcess.StandardInput.Close()
    if (!$catProcess.WaitForExit(10000) -or $catProcess.ExitCode -ne 0) {
        throw 'controlled native cat process did not exit cleanly'
    }
    $catOutput.Result |
        Set-Content -LiteralPath (Join-Path $qualification 'cat.stdout.txt') -Encoding utf8NoBOM
    $catError.Result |
        Set-Content -LiteralPath (Join-Path $qualification 'cat.stderr.txt') -Encoding utf8NoBOM
    [ordered]@{
        cygwin_pid = $catCygwin
        windows_pid = $catWindows
        actual_process = $catNative |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CreationDate, CommandLine
        default_line = $catLine
        perl_regex_matched = [regex]::IsMatch(
            $catLine,
            "^.\s+$catCygwin\s+\d+\s+\d+\s+(\d+)"
        )
    } | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $qualification 'perl-cat-proof.json') -Encoding utf8NoBOM

    & (Join-Path $bin 'mount.exe') --help 2>&1 |
        Set-Content -LiteralPath (Join-Path $qualification 'mount-help.txt') -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) {
        throw "mount --help failed with exit code $LASTEXITCODE"
    }
    & (Join-Path $bin 'mount.exe') --version 2>&1 |
        Set-Content -LiteralPath (Join-Path $qualification 'mount-version.txt') -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) {
        throw "mount --version failed with exit code $LASTEXITCODE"
    }
    $mountOutput = @(& (Join-Path $bin 'bash.exe') -lc '/usr/bin/mount')
    if ($LASTEXITCODE -ne 0) {
        throw "literal /usr/bin/mount failed with exit code $LASTEXITCODE"
    }
    $mountOutput |
        Set-Content -LiteralPath (Join-Path $qualification 'mount-output.txt') -Encoding utf8NoBOM
    $mountText = $mountOutput -join "`n"
    $binMountMatch = [regex]::Match($mountText, 'on (?:/usr)?/bin type .+ \((\w+)[,\)]')
    $rootMountMatch = [regex]::Match($mountText, '(?m)^.+ on / type .+ \(([^)]+)\)')
    $cygdriveMountMatch = [regex]::Match($mountText, '(?m)^.+ on /cygdrive/c type .+ \(([^)]+)\)')
    if (!$binMountMatch.Success -or !$rootMountMatch.Success -or !$cygdriveMountMatch.Success) {
        throw 'mount output did not satisfy the unchanged lib/cygwin.t mount shape'
    }
    [ordered]@{
        literal_path = '/usr/bin/mount'
        bin_mode = $binMountMatch.Groups[1].Value
        root_flags = $rootMountMatch.Groups[1].Value
        cygdrive_flags = $cygdriveMountMatch.Groups[1].Value
        output = $mountOutput
    } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $qualification 'mount-proof.json') -Encoding utf8NoBOM

    $mountInfo = [Diagnostics.ProcessStartInfo]::new()
    $mountInfo.FileName = Join-Path $bin 'mount.exe'
    $mountInfo.WorkingDirectory = $fixture
    $mountInfo.UseShellExecute = $false
    $mountInfo.RedirectStandardOutput = $true
    $mountInfo.RedirectStandardError = $true
    $mountModules = @()
    $mountRuntime = $null
    $mountAttempts = 0
    do {
        ++$mountAttempts
        $mountProcess = [Diagnostics.Process]::Start($mountInfo)
        $mountModules = @()
        while (!$mountProcess.HasExited -and !$mountRuntime) {
            try {
                $mountProcess.Refresh()
                $mountModules = @($mountProcess.Modules | ForEach-Object {
                    [ordered]@{
                        name = $_.ModuleName
                        path = $_.FileName
                        sha256 = if (Test-Path $_.FileName) {
                            (Get-FileHash -Algorithm SHA256 $_.FileName).Hash.ToLowerInvariant()
                        } else {
                            $null
                        }
                    }
                })
                $mountRuntime = $mountModules |
                    Where-Object name -ieq 'msys-2.0.dll' |
                    Select-Object -First 1
            } catch {
            }
        }
        $mountModuleOutput = $mountProcess.StandardOutput.ReadToEndAsync()
        $mountModuleError = $mountProcess.StandardError.ReadToEndAsync()
        $mountProcess.WaitForExit()
        $mountModuleOutput.Result |
            Set-Content -LiteralPath (Join-Path $qualification 'mount-module-run.txt') -Encoding utf8NoBOM
        $mountModuleError.Result |
            Set-Content -LiteralPath (Join-Path $qualification 'mount-module-run.stderr.txt') -Encoding utf8NoBOM
    } while (!$mountRuntime -and $mountAttempts -lt 20)

    $expectedRuntimeHash = '907afa099a69aa3c13d4e3b30eeba18c4a6b1766d5fa39b4746fae23c3f9e76c'
    if ($mountProcess.ExitCode -ne 0 -or !$mountRuntime -or $mountRuntime.sha256 -ne $expectedRuntimeHash) {
        throw 'mount did not load the pinned 907 runtime'
    }
    [ordered]@{
        attempts = $mountAttempts
        modules = $mountModules
    } | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $qualification 'mount-loaded-modules.json') -Encoding utf8NoBOM

    & (Join-Path $bin 'cygpath.exe') --help 2>&1 |
        Set-Content -LiteralPath (Join-Path $qualification 'cygpath-help.txt') -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) {
        throw "cygpath --help failed with exit code $LASTEXITCODE"
    }
    & (Join-Path $bin 'cygpath.exe') --version 2>&1 |
        Set-Content -LiteralPath (Join-Path $qualification 'cygpath-version.txt') -Encoding utf8NoBOM
    if ($LASTEXITCODE -ne 0) {
        throw "cygpath --version failed with exit code $LASTEXITCODE"
    }
    $windowsRoot = (& (Join-Path $bin 'cygpath.exe') -w /).Trim()
    $posixRoot = (& (Join-Path $bin 'cygpath.exe') -u $windowsRoot).Trim()
    $drivePath = (& (Join-Path $bin 'cygpath.exe') 'C:').Trim()
    if ($posixRoot -ne '/' -or $drivePath -notmatch '^/.+/c$') {
        throw "cygpath conversion proof failed: root=$posixRoot drive=$drivePath"
    }
    [ordered]@{
        posix_root = '/'
        windows_root = $windowsRoot
        windows_root_roundtrip = $posixRoot
        drive_input = 'C:'
        drive_output = $drivePath
        derived_cygdrive_prefix = $drivePath.Substring(0, $drivePath.Length - 2)
    } | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $qualification 'cygpath-proof.json') -Encoding utf8NoBOM

    $moduleInfo = [Diagnostics.ProcessStartInfo]::new()
    $moduleInfo.FileName = Join-Path $bin 'ps.exe'
    $moduleInfo.ArgumentList.Add('-W')
    $moduleInfo.WorkingDirectory = $fixture
    $moduleInfo.UseShellExecute = $false
    $moduleInfo.RedirectStandardOutput = $true
    $moduleInfo.RedirectStandardError = $true
    $moduleProcess = [Diagnostics.Process]::Start($moduleInfo)
    $modules = @()
    $moduleDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (
        !$moduleProcess.HasExited -and
        [DateTime]::UtcNow -lt $moduleDeadline -and
        !($modules | Where-Object name -ieq 'msys-2.0.dll')
    ) {
        try {
            $moduleProcess.Refresh()
            $modules = @($moduleProcess.Modules | ForEach-Object {
                [ordered]@{
                    name = $_.ModuleName
                    path = $_.FileName
                    sha256 = if (Test-Path $_.FileName) {
                        (Get-FileHash -Algorithm SHA256 $_.FileName).Hash.ToLowerInvariant()
                    } else {
                        $null
                    }
                }
            })
        } catch {
        }
        Start-Sleep -Milliseconds 1
    }
    $moduleOutput = $moduleProcess.StandardOutput.ReadToEndAsync()
    $moduleError = $moduleProcess.StandardError.ReadToEndAsync()
    $moduleProcess.WaitForExit()
    $moduleOutput.Result |
        Set-Content -LiteralPath (Join-Path $qualification 'windows-module-run.txt') -Encoding utf8NoBOM
    $moduleError.Result |
        Set-Content -LiteralPath (Join-Path $qualification 'windows-module-run.stderr.txt') -Encoding utf8NoBOM
    $runtimeModule = $modules | Where-Object name -ieq 'msys-2.0.dll' | Select-Object -First 1
    if ($moduleProcess.ExitCode -ne 0 -or !$runtimeModule) {
        throw 'ps -W module capture failed'
    }
    if ($runtimeModule.sha256 -ne $expectedRuntimeHash) {
        throw "ps loaded unexpected runtime hash $($runtimeModule.sha256)"
    }
    $modules | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $qualification 'loaded-modules.json') -Encoding utf8NoBOM

    $cygpathInfo = [Diagnostics.ProcessStartInfo]::new()
    $cygpathInfo.FileName = Join-Path $bin 'cygpath.exe'
    $cygpathInfo.ArgumentList.Add('-f')
    $cygpathInfo.ArgumentList.Add('-')
    $cygpathInfo.WorkingDirectory = $fixture
    $cygpathInfo.UseShellExecute = $false
    $cygpathInfo.RedirectStandardInput = $true
    $cygpathInfo.RedirectStandardOutput = $true
    $cygpathInfo.RedirectStandardError = $true
    $cygpathProcess = [Diagnostics.Process]::Start($cygpathInfo)
    $cygpathOutput = $cygpathProcess.StandardOutput.ReadToEndAsync()
    $cygpathError = $cygpathProcess.StandardError.ReadToEndAsync()
    $cygpathModules = @()
    $cygpathDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (
        !$cygpathProcess.HasExited -and
        [DateTime]::UtcNow -lt $cygpathDeadline -and
        !($cygpathModules | Where-Object name -ieq 'msys-2.0.dll')
    ) {
        try {
            $cygpathProcess.Refresh()
            $cygpathModules = @($cygpathProcess.Modules | ForEach-Object {
                [ordered]@{
                    name = $_.ModuleName
                    path = $_.FileName
                    sha256 = if (Test-Path $_.FileName) {
                        (Get-FileHash -Algorithm SHA256 $_.FileName).Hash.ToLowerInvariant()
                    } else {
                        $null
                    }
                }
            })
        } catch {
        }
        Start-Sleep -Milliseconds 1
    }
    $cygpathProcess.StandardInput.WriteLine('/')
    $cygpathProcess.StandardInput.Close()
    if (!$cygpathProcess.WaitForExit(10000) -or $cygpathProcess.ExitCode -ne 0) {
        throw 'cygpath -f - module probe did not exit cleanly'
    }
    $cygpathOutput.Result |
        Set-Content -LiteralPath (Join-Path $qualification 'cygpath-module-run.txt') -Encoding utf8NoBOM
    $cygpathError.Result |
        Set-Content -LiteralPath (Join-Path $qualification 'cygpath-module-run.stderr.txt') -Encoding utf8NoBOM
    $cygpathRuntime = $cygpathModules |
        Where-Object name -ieq 'msys-2.0.dll' |
        Select-Object -First 1
    if (!$cygpathRuntime -or $cygpathRuntime.sha256 -ne $expectedRuntimeHash) {
        throw 'cygpath did not load the pinned 907 runtime'
    }
    $cygpathModules | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $qualification 'cygpath-loaded-modules.json') -Encoding utf8NoBOM
} finally {
    if ($mountProcess -and !$mountProcess.HasExited) {
        $mountProcess.WaitForExit(10000) | Out-Null
    }
    if ($cygpathProcess -and !$cygpathProcess.HasExited) {
        $cygpathProcess.StandardInput.Close()
        $cygpathProcess.WaitForExit(10000) | Out-Null
    }
    if ($catProcess -and !$catProcess.HasExited) {
        $catProcess.StandardInput.Close()
        $catProcess.WaitForExit(10000) | Out-Null
    }
    Pop-Location
    $env:PATH = $oldPath
}
