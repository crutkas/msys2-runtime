$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$temporaryRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$work = Join-Path $temporaryRoot 'layer4-x64-fastcwd'
if (-not $env:LAYER4_LLVM_BIN) {
    throw 'LAYER4_LLVM_BIN must point to the native ARM64 LLVM tools'
}

$clang = Join-Path $env:LAYER4_LLVM_BIN 'clang.exe'
$dlltool = Join-Path $env:LAYER4_LLVM_BIN 'llvm-dlltool.exe'
$linker = Join-Path $env:LAYER4_LLVM_BIN 'lld-link.exe'
$readobj = Join-Path $env:LAYER4_LLVM_BIN 'llvm-readobj.exe'
foreach ($tool in @($clang, $dlltool, $linker, $readobj)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required LLVM tool is unavailable: $tool"
    }
}

$production = Join-Path $repo 'winsup\cygwin\aarch64\fastcwd.cc'
$control = Join-Path $repo '.github\checks\aarch64-layer4-fastcwd.cc'
$includes = Join-Path $repo '.github\checks\aarch64-layer4-stubs'
$program = Join-Path $work 'fastcwd-x64-on-arm64.exe'
$productionObject = Join-Path $work 'fastcwd-production.obj'
$controlObject = Join-Path $work 'fastcwd-control.obj'
$definition = Join-Path $work 'kernel32.def'
$importLibrary = Join-Path $work 'kernel32.lib'
$headers = Join-Path $work 'headers.txt'
if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $work | Out-Null

@(
    'LIBRARY KERNEL32.dll',
    'EXPORTS',
    'GetModuleHandleA',
    'GetProcAddress',
    'GetCurrentProcess',
    'IsWow64Process2',
    'GetProcessInformation',
    'VirtualQuery',
    'ExitProcess'
) | Set-Content -LiteralPath $definition -Encoding ascii

& $clang -target x86_64-w64-windows-gnu -DNDEBUG -O2 -Wall -Wextra `
    -Werror "-I$includes" -c $production -o $productionObject
& $clang -target x86_64-w64-windows-gnu -DNDEBUG -O2 -Wall -Wextra `
    -Werror -DLAYER4_EXPECTED_PROCESS_MACHINE=0x8664 `
    -c $control -o $controlObject
& $dlltool -m i386:x86-64 -d $definition -l $importLibrary
& $linker /machine:x64 /subsystem:console /entry:mainCRTStartup /dynamicbase `
    "/out:$program" $productionObject $controlObject $importLibrary

& $readobj --file-headers $program | Set-Content -LiteralPath $headers
$headerText = Get-Content -Raw -LiteralPath $headers
if ($headerText -notmatch 'Machine: IMAGE_FILE_MACHINE_AMD64 \(0x8664\)' -or
    $headerText -notmatch 'IMAGE_FILE_EXECUTABLE_IMAGE') {
    throw 'fastcwd control is not an executable x86_64 PE image'
}

$process = Start-Process -FilePath $program -Wait -PassThru -NoNewWindow
if ($process.ExitCode -ne 0) {
    throw "x86_64-on-ARM64 production fastcwd control failed: $($process.ExitCode)"
}

Write-Host 'x86_64-on-ARM64 fastcwd thunk discovery passed under emulation.'
