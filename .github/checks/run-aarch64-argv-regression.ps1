$ErrorActionPreference = 'Stop'

if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne
    [Runtime.InteropServices.Architecture]::Arm64) {
  throw 'A native Windows ARM64 runner is required'
}

$runtime = (Resolve-Path $args[0]).Path
$child = Join-Path $runtime 'aarch64-argv-dump.exe'
$marker = 'native-arm64-environment'
$long = ('0123456789abcdef' * 40)
$corpus = @(
  '',
  'alpha',
  'ISO-8859-1',
  'LATIN1',
  '--to-code=UTF-8',
  'C:\path with spaces\iconv-latin1.bin',
  'repeat--aaabbbccc111',
  'quote"inside',
  'trail\\',
  'café-中-🙂',
  $long
)

function ConvertTo-WindowsArgument([string]$Value) {
  if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
    return $Value
  }
  $result = '"'
  $slashes = 0
  foreach ($character in $Value.ToCharArray()) {
    if ($character -eq '\') {
      ++$slashes
    } elseif ($character -eq '"') {
      $result += ('\' * (2 * $slashes + 1)) + '"'
      $slashes = 0
    } else {
      $result += ('\' * $slashes) + $character
      $slashes = 0
    }
  }
  return $result + ('\' * (2 * $slashes)) + '"'
}

function Assert-Dump([string]$Name, [string[]]$Expected) {
  $dumpPath = Join-Path $env:RUNNER_TEMP "$Name.txt"
  if (-not (Test-Path $dumpPath)) {
    throw "$Name did not produce an argv dump"
  }
  $dump = Get-Content $dumpPath
  $dump | Set-Content (Join-Path $runtime "$Name.txt")
  $values = @{}
  foreach ($line in $dump) {
    $parts = $line -split '=', 2
    if ($parts.Count -eq 2) { $values[$parts[0]] = $parts[1] }
  }
  if ($values.process_machine -ne '0000' -or
      $values.native_machine -ne 'aa64' -or
      $values.module_machine -ne 'aa64') {
    throw "$Name used a non-native process or module"
  }
  if ($values.environment -ne
      [Convert]::ToHexString([Text.Encoding]::UTF8.GetBytes($marker)).ToLower()) {
    throw "$Name environment mismatch"
  }
  if ([int]$values.argc -ne $Expected.Count + 1) {
    throw "$Name argc mismatch: $($values.argc)"
  }
  for ($index = 0; $index -lt $Expected.Count; ++$index) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Expected[$index])
    $actualIndex = $index + 1
    $actualHex = $values["arg.$actualIndex.hex"]
    $expectedHex = [Convert]::ToHexString($bytes).ToLower()
    if ($actualHex -ne $expectedHex -or
        [int]$values["arg.$actualIndex.len"] -ne $bytes.Length) {
      throw "$Name argv[$actualIndex] mismatch: '$actualHex' != '$expectedHex'"
    }
  }
}

$env:ARM64_ARGV_MARKER = $marker

$argumentListOutput = Join-Path $env:RUNNER_TEMP 'argument-list.txt'
$env:ARM64_ARGV_OUTPUT = $argumentListOutput
$startInfo = [Diagnostics.ProcessStartInfo]::new($child)
$startInfo.UseShellExecute = $false
foreach ($argument in $corpus) { $startInfo.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($startInfo)
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "ArgumentList child exited $($process.ExitCode)" }
Assert-Dump 'argument-list' $corpus

$rawOutput = Join-Path $env:RUNNER_TEMP 'raw-arguments.txt'
$env:ARM64_ARGV_OUTPUT = $rawOutput
$startInfo = [Diagnostics.ProcessStartInfo]::new($child)
$startInfo.UseShellExecute = $false
$startInfo.Arguments = ($corpus | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
$process = [Diagnostics.Process]::Start($startInfo)
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw "raw Arguments child exited $($process.ExitCode)" }
Assert-Dump 'raw-arguments' $corpus

$signature = @'
using System;
using System.Runtime.InteropServices;
public static class NativeProcess {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct STARTUPINFO {
    public int cb; public string reserved; public string desktop; public string title;
    public int x; public int y; public int xSize; public int ySize;
    public int xCountChars; public int yCountChars; public int fillAttribute;
    public int flags; public short showWindow; public short reserved2Size;
    public IntPtr reserved2; public IntPtr stdInput; public IntPtr stdOutput;
    public IntPtr stdError;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION {
    public IntPtr process; public IntPtr thread; public int processId; public int threadId;
  }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CreateProcessW(string applicationName,
    System.Text.StringBuilder commandLine, IntPtr processAttributes,
    IntPtr threadAttributes, bool inheritHandles, int flags, IntPtr environment,
    string currentDirectory, ref STARTUPINFO startupInfo,
    out PROCESS_INFORMATION processInformation);
  [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
  [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
Add-Type $signature
$nativeOutput = Join-Path $env:RUNNER_TEMP 'native-createprocess.txt'
$env:ARM64_ARGV_OUTPUT = $nativeOutput
$commandLine = ConvertTo-WindowsArgument $child
foreach ($argument in $corpus) {
  $commandLine += ' ' + (ConvertTo-WindowsArgument $argument)
}
$startupInfo = [NativeProcess+STARTUPINFO]::new()
$startupInfo.cb = [Runtime.InteropServices.Marshal]::SizeOf($startupInfo)
$processInfo = [NativeProcess+PROCESS_INFORMATION]::new()
$mutableCommandLine = [Text.StringBuilder]::new($commandLine)
if (-not [NativeProcess]::CreateProcessW($child, $mutableCommandLine,
    [IntPtr]::Zero, [IntPtr]::Zero, $false, 0, [IntPtr]::Zero, $runtime,
    [ref]$startupInfo, [ref]$processInfo)) {
  throw "CreateProcessW failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
[void][NativeProcess]::WaitForSingleObject($processInfo.process, 30000)
[uint32]$exitCode = 0
[void][NativeProcess]::GetExitCodeProcess($processInfo.process, [ref]$exitCode)
[void][NativeProcess]::CloseHandle($processInfo.thread)
[void][NativeProcess]::CloseHandle($processInfo.process)
if ($exitCode -ne 0) { throw "CreateProcessW child exited $exitCode" }
Assert-Dump 'native-createprocess' $corpus

$cmdCorpus = @('ISO-8859-1', 'LATIN1', '--to-code=UTF-8',
  'C:\path with spaces\iconv-latin1.bin', 'repeat--aaabbbccc111')
$cmdOutput = Join-Path $env:RUNNER_TEMP 'cmd.txt'
$env:ARM64_ARGV_OUTPUT = $cmdOutput
$cmdLine = '"' + $child + '"'
foreach ($argument in $cmdCorpus) {
  $cmdLine += ' ' + (ConvertTo-WindowsArgument $argument)
}
& $env:ComSpec /d /s /c "`"$cmdLine`""
if ($LASTEXITCODE -ne 0) { throw "cmd child exited $LASTEXITCODE" }
Assert-Dump 'cmd' $cmdCorpus
