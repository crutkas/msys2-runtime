param(
  [Parameter(Mandatory = $true)]
  [string] $ExpectedNativeMachine,

  [Parameter(Mandatory = $true)]
  [string] $ExpectedProcessArchitecture,

  [Parameter(Mandatory = $true)]
  [string] $EvidencePath
)

$ErrorActionPreference = 'Stop'

# The runner label is a scheduling hint, not an architecture fact, so the
# native machine is read from the kernel through IsWow64Process2 and the
# managed process architecture is read independently.  Both must agree with
# what the lane claims before any diagnostic result is attributed to an
# architecture.

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class DiagnosticArchitectureNativeMethods
{
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWow64Process2(
        IntPtr process,
        out ushort processMachine,
        out ushort nativeMachine);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    public static string Describe(ushort machine)
    {
        switch (machine)
        {
            case 0x0000: return "UNKNOWN";
            case 0x014c: return "I386";
            case 0x01c4: return "ARMNT";
            case 0x8664: return "AMD64";
            case 0xaa64: return "ARM64";
            default: return "0x" + machine.ToString("x4");
        }
    }

    /* IsWow64Process2 reports IMAGE_FILE_MACHINE_UNKNOWN as the process
       machine for a process that is not running under WOW64, so only the
       native machine is authoritative here; the process machine is kept as
       evidence. */
    public static string[] Machines()
    {
        ushort processMachine;
        ushort nativeMachine;
        if (!IsWow64Process2(
                GetCurrentProcess(), out processMachine, out nativeMachine))
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "IsWow64Process2 failed");
        return new string[]
        {
            Describe(processMachine),
            Describe(nativeMachine)
        };
    }
}
'@

$machines = [DiagnosticArchitectureNativeMethods]::Machines()
$processMachine = $machines[0]
$nativeMachine = $machines[1]

$runtime = [System.Runtime.InteropServices.RuntimeInformation]
$osArchitecture = $runtime::OSArchitecture.ToString()
$processArchitecture = $runtime::ProcessArchitecture.ToString()

if (-not [string]::Equals(
    $nativeMachine, $ExpectedNativeMachine,
    [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Native machine is $nativeMachine, expected $ExpectedNativeMachine"
}
if (-not [string]::Equals(
    $processArchitecture, $ExpectedProcessArchitecture,
    [System.StringComparison]::OrdinalIgnoreCase)) {
  throw ("Process architecture is $processArchitecture, " +
    "expected $ExpectedProcessArchitecture")
}

@(
  'classification=diagnostic'
  'consumable=false'
  "runner_os=$([System.Environment]::OSVersion.VersionString)"
  "native_machine=$nativeMachine"
  "wow64_process_machine=$processMachine"
  "os_architecture=$osArchitecture"
  "process_architecture=$processArchitecture"
  "expected_native_machine=$ExpectedNativeMachine"
  "expected_process_architecture=$ExpectedProcessArchitecture"
) | Out-File -LiteralPath $EvidencePath -Encoding ascii
