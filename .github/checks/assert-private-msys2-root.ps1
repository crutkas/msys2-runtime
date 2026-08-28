param(
  [Parameter(Mandatory = $true)]
  [string] $BasePath,

  [Parameter(Mandatory = $true)]
  [string] $CandidatePath,

  [Parameter(Mandatory = $true)]
  [string] $ExpectedLeaf,

  [Parameter(Mandatory = $true)]
  [string] $EvidencePath
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class DiagnosticPathNativeMethods
{
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint FILE_SHARE_DELETE = 0x00000004;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle file,
        StringBuilder filePath,
        uint filePathLength,
        uint flags);

    public static string GetFinalPath(string path)
    {
        using (SafeFileHandle handle = CreateFileW(
            path,
            0,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS,
            IntPtr.Zero))
        {
            if (handle.IsInvalid)
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Unable to open path for final-path validation: " + path);

            StringBuilder result = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandleW(
                handle, result, (uint) result.Capacity, 0);
            if (length == 0)
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "Unable to resolve final path: " + path);
            if (length >= result.Capacity)
                throw new InvalidOperationException(
                    "Resolved path exceeds the diagnostic buffer: " + path);

            string finalPath = result.ToString();
            if (finalPath.StartsWith(@"\\?\UNC\", StringComparison.Ordinal))
                return @"\\" + finalPath.Substring(8);
            if (finalPath.StartsWith(@"\\?\", StringComparison.Ordinal))
                return finalPath.Substring(4);
            return finalPath;
        }
    }
}
'@

function Get-NormalizedPath {
  param([string] $Path)

  $full = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($full)
  if ($full.Length -gt $root.Length) {
    $full = $full.TrimEnd('\', '/')
  }
  return $full
}

$base = Get-NormalizedPath $BasePath
$candidate = Get-NormalizedPath $CandidatePath
$expected = Get-NormalizedPath (Join-Path $base $ExpectedLeaf)

if (-not [string]::Equals(
    $candidate, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "MSYS2 root is not the run-scoped path: $candidate"
}
if (-not (Test-Path -LiteralPath $base -PathType Container)) {
  throw "Runner temporary base does not exist: $base"
}
if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
  throw "MSYS2 root does not exist: $candidate"
}

$relative = [System.IO.Path]::GetRelativePath($base, $candidate)
if ([System.IO.Path]::IsPathRooted($relative) -or
    $relative -eq '..' -or
    $relative.StartsWith(
      "..$([System.IO.Path]::DirectorySeparatorChar)",
      [System.StringComparison]::Ordinal)) {
  throw "MSYS2 root escapes the runner temporary base: $candidate"
}

$cursor = $base
foreach ($component in $relative.Split(
    [char[]] @('\', '/'),
    [System.StringSplitOptions]::RemoveEmptyEntries)) {
  $cursor = Join-Path $cursor $component
  $item = Get-Item -Force -LiteralPath $cursor
  if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "MSYS2 root path crosses a reparse point: $cursor"
  }
}

$baseFinal = Get-NormalizedPath (
  [DiagnosticPathNativeMethods]::GetFinalPath($base))
$candidateFinal = Get-NormalizedPath (
  [DiagnosticPathNativeMethods]::GetFinalPath($candidate))
$basePrefix = $baseFinal + [System.IO.Path]::DirectorySeparatorChar
if (-not $candidateFinal.StartsWith(
    $basePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Final MSYS2 root escapes the final runner temporary base: $candidateFinal"
}

@(
  'classification=diagnostic'
  'consumable=false'
  "base_lexical=$base"
  "base_final=$baseFinal"
  "candidate_lexical=$candidate"
  "candidate_final=$candidateFinal"
  'reparse_points_below_base=0'
) | Out-File -LiteralPath $EvidencePath -Encoding ascii
