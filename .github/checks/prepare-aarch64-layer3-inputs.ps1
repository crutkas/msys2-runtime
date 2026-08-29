[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Destination,

    [Parameter(Mandatory)]
    [string] $BusyBoxSource,

    [Parameter(Mandatory)]
    [string] $BinutilsSource
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$tag = 'native-binutils-eb40c26f66fc'
$release = "https://github.com/crutkas/binutils-woarm64/releases/download/$tag"
$inputs = @(
    @{
        Name = 'busybox-c26a88d7.tar.gz'
        Size = 4234068
        SHA256 = '23D605DDDCFAE3E1865C5E5CC9BF7C54FA104AD62B2313644FA7E058475F6EAE'
    },
    @{
        Name = 'native-binutils-eb40c26f66fc-aa64.tar.gz'
        Size = 26524679
        SHA256 = '99D3FC14BBEAF359872A573D0EA78EC18D5C6551AAB5EFDA3DD01706797784F7'
    },
    @{
        Name = 'manifest.json'
        Size = 13132
        SHA256 = '2C6D44CBCCC1AF34F7232FDDBF81470887630783A9AD6D11E90418E0A7B253FD'
    },
    @{
        Name = 'validation.json'
        Size = 8829
        SHA256 = 'A5BE27ECF64C07475DDBE78092B4E90CAD8263D4B32ACFCFAF941878AA074DE0'
    },
    @{
        Name = 'native-binutils-eb40c26f66fc-downstream-validation.json'
        Size = 12363
        SHA256 = '219BBADC4E4F250F1FD09C186DAB11D71A8E14323DD74467948F2161F8458D09'
    }
)

function Assert-Sha256([string] $Path, [string] $Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) {
        throw "SHA-256 mismatch for $Path`: expected $Expected, got $actual"
    }
}

function Get-PeMachine([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "$Path is not a PE image"
        }
        $stream.Position = 0x3C
        $stream.Position = $reader.ReadUInt32()
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "$Path has no PE signature"
        }
        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-GitSource(
    [string] $Path,
    [string] $Repository,
    [string] $Commit,
    [string] $Tree,
    [string] $BaseCommit
) {
    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
        throw "Missing source checkout for $Repository at $Path"
    }

    $origin = (& git -C $Path remote get-url origin).Trim()
    $expectedOrigin = "https://github.com/$Repository"
    $normalizedOrigin = $origin -replace '/$', '' -replace '\.git$', ''
    if ($normalizedOrigin -ne $expectedOrigin) {
        throw "Unexpected origin for $Repository`: $origin"
    }

    $head = (& git -C $Path rev-parse 'HEAD^{commit}').Trim()
    $actualTree = (& git -C $Path rev-parse "$Commit^{tree}").Trim()
    if ($head -ne $Commit -or $actualTree -ne $Tree) {
        throw "Source object mismatch for $Repository"
    }
    & git -C $Path cat-file -e "$BaseCommit^{commit}"
    & git -C $Path merge-base --is-ancestor $BaseCommit $Commit
}

Assert-GitSource $BusyBoxSource 'crutkas/busybox-w32' `
    'c26a88d7e1ec96a1b96fce442e35378f3ddecba4' `
    'f9ec2d1f3ca1ab362d739c3d400ab0a902ab3ecd' `
    'e7299058b4074a19cfae0f446ec45ab87e804a27'
Assert-GitSource $BinutilsSource 'crutkas/binutils-woarm64' `
    'eb40c26f66fc723d7e87c294c2a4ca840d5d7f7d' `
    'bb2010ace765f0d0ce1e0dc8c4b257f7a00cbb76' `
    'e59c24a75436ad48f1c0270b6d759bfafdc45757'
$resolvedTag = (& git -C $BinutilsSource rev-parse "$tag^{commit}").Trim()
if ($resolvedTag -ne 'eb40c26f66fc723d7e87c294c2a4ca840d5d7f7d') {
    throw "Release tag $tag does not resolve to the reviewed source"
}

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($input in $inputs) {
    $path = Join-Path $Destination $input.Name
    Invoke-WebRequest -Uri "$release/$($input.Name)" -OutFile $path
    if ((Get-Item -LiteralPath $path).Length -ne $input.Size) {
        throw "Size mismatch for $($input.Name)"
    }
    Assert-Sha256 $path $input.SHA256
}

$busyBoxArchive = Join-Path $Destination 'busybox-c26a88d7.tar.gz'
& "$env:SystemRoot\System32\tar.exe" -xzf $busyBoxArchive -C $Destination
$busyBoxRoot = Join-Path $Destination 'busybox-c26a88d7'
$busyBox = Join-Path $busyBoxRoot 'bin\busybox.exe'
$busyBoxManifest = Get-Content -LiteralPath `
    (Join-Path $busyBoxRoot 'manifest.json') -Raw | ConvertFrom-Json
if ($busyBoxManifest.source.commit -ne
        'c26a88d7e1ec96a1b96fce442e35378f3ddecba4' -or
    $busyBoxManifest.source.tree -ne
        'f9ec2d1f3ca1ab362d739c3d400ab0a902ab3ecd' -or
    $busyBoxManifest.artifact.sha256 -ne
        '841D33F4B4C0A615A550D5B7AC480F427AD8CB2340C3408A81BECC21765A3A76' -or
    $busyBoxManifest.artifact.peMachine -ne '0xAA64') {
    throw 'BusyBox manifest does not match the pinned source and artifact'
}
Assert-Sha256 $busyBox $busyBoxManifest.artifact.sha256

$requiredApplets = @('dirname', 'grep', 'mkdir', 'rm', 'sh')
$availableApplets = @(& $busyBox --list)
$aliases = Join-Path $Destination 'busybox-aliases'
New-Item -ItemType Directory -Path $aliases | Out-Null
foreach ($applet in $requiredApplets) {
    if ($applet -notin $availableApplets) {
        throw "Pinned BusyBox does not contain required applet $applet"
    }
    New-Item -ItemType HardLink -Path (Join-Path $aliases "$applet.exe") `
        -Target $busyBox | Out-Null
}

$binutilsArchive = Join-Path $Destination 'native-binutils-eb40c26f66fc-aa64.tar.gz'
& $busyBox tar -xzf $binutilsArchive -C $Destination
$binutilsRoot = Join-Path $Destination 'native-binutils-eb40c26f66fc-aa64'
$manifestPath = Join-Path $Destination 'manifest.json'
$bundleManifestPath = Join-Path $binutilsRoot 'manifest.json'
$validationPath = Join-Path $Destination 'validation.json'
$bundleValidationPath = Join-Path $binutilsRoot 'validation.json'
Assert-Sha256 $bundleManifestPath $inputs[2].SHA256
Assert-Sha256 $bundleValidationPath $inputs[3].SHA256
if ((Get-FileHash $manifestPath).Hash -ne
        (Get-FileHash $bundleManifestPath).Hash -or
    (Get-FileHash $validationPath).Hash -ne
        (Get-FileHash $bundleValidationPath).Hash) {
    throw 'Extracted evidence does not match the public release assets'
}

$manifest = Get-Content -LiteralPath $bundleManifestPath -Raw | ConvertFrom-Json
if ($manifest.Source.Repository -ne 'crutkas/binutils-woarm64' -or
    $manifest.Source.PullRequestNumber -ne 7 -or
    $manifest.Source.Commit -ne
        'eb40c26f66fc723d7e87c294c2a4ca840d5d7f7d' -or
    $manifest.Source.Tree -ne
        'bb2010ace765f0d0ce1e0dc8c4b257f7a00cbb76' -or
    $manifest.Source.Parent -ne
        '007653dc12284a3d07340d47dc71fec24d1b42a9' -or
    $manifest.Source.BaseCommit -ne
        'e59c24a75436ad48f1c0270b6d759bfafdc45757' -or
    $manifest.Source.TrackedObjectMismatches -ne 0 -or
    $manifest.Source.MTimeMismatches -ne 0) {
    throw 'Binutils manifest does not match the reviewed source'
}
if ($manifest.Parents.BusyBox.Commit -ne $busyBoxManifest.source.commit -or
    $manifest.Parents.BusyBox.Tree -ne $busyBoxManifest.source.tree -or
    $manifest.Parents.BusyBox.BundleSHA256 -ne $inputs[0].SHA256 -or
    $manifest.Parents.BusyBox.BusyBoxSHA256 -ne
        $busyBoxManifest.artifact.sha256) {
    throw 'Binutils manifest is not bound to the pinned BusyBox input'
}
if (-not $manifest.Approval.PromotionEligible -or
    $manifest.Approval.ApprovedUse -notmatch 'Focused native AArch64' -or
    $manifest.Approval.NotApproved -notmatch 'Full-runtime success') {
    throw 'Binutils approval boundary is absent or broader than reviewed'
}

$toolPins = @{
    'ld.exe' = '84E93E4DED6321E85ADA5AAA636F16821ED87D55815608287076CAA815EC06B4'
    'as.exe' = 'DD48D22DAE0DD0CF40E2072BFA0F37D98F45F9C871F888F2290FE83B8D5ED03D'
    'ar.exe' = 'A4DC15897D108E2D48189AC689C1FC2911C52DCBA03BE8FBDB62E488325B2077'
    'objdump.exe' = '4B8ED1232D2D55B6D97B0030D10BE8C8E8433E2072F6BEA96B7B95D6F00BE0FC'
}
$binutilsBin = Join-Path $binutilsRoot 'bin'
foreach ($entry in $toolPins.GetEnumerator()) {
    $path = Join-Path $binutilsBin $entry.Key
    Assert-Sha256 $path $entry.Value
    if ((Get-PeMachine $path) -ne 0xAA64) {
        throw "$($entry.Key) is not PE ARM64"
    }
    $manifestTool = $manifest.Tools | Where-Object Name -eq $entry.Key
    if ($null -eq $manifestTool -or
        $manifestTool.SHA256 -ne $entry.Value -or
        $manifestTool.PEMachine -ne '0xAA64' -or
        $manifestTool.ProcessMachineTypeInfo -ne '0xAA64' -or
        $manifestTool.NativeMachine -ne '0xAA64' -or
        $manifestTool.ExecutionClassification -ne 'native-arm64' -or
        $manifestTool.ExitCode -ne 0) {
        throw "$($entry.Key) does not match the reviewed manifest"
    }
    & $path --version | Select-Object -First 1
}

$pthread = Join-Path $binutilsBin 'libwinpthread-1.dll'
Assert-Sha256 $pthread `
    '8CC5CFB48256A27A1764AE0AF6C230152BEF374FA97CE641D7C41BEB55E4AF54'
if ((Get-PeMachine $busyBox) -ne 0xAA64 -or
    (Get-PeMachine $pthread) -ne 0xAA64) {
    throw 'Pinned native dependency closure is not PE ARM64'
}

$shell = Join-Path $aliases 'sh.exe'
& $shell -c 'test "$(printf layer3-busybox)" = layer3-busybox'

if ($env:GITHUB_ENV) {
    "BUSYBOX_BIN=$aliases" | Add-Content -LiteralPath $env:GITHUB_ENV
    "BUSYBOX_SH=$shell" | Add-Content -LiteralPath $env:GITHUB_ENV
    "LAYER3_LD=$(Join-Path $binutilsBin 'ld.exe')" |
        Add-Content -LiteralPath $env:GITHUB_ENV
    "LAYER3_AS=$(Join-Path $binutilsBin 'as.exe')" |
        Add-Content -LiteralPath $env:GITHUB_ENV
    "LAYER3_AR=$(Join-Path $binutilsBin 'ar.exe')" |
        Add-Content -LiteralPath $env:GITHUB_ENV
    "LAYER3_OBJDUMP=$(Join-Path $binutilsBin 'objdump.exe')" |
        Add-Content -LiteralPath $env:GITHUB_ENV
}

Write-Host 'Verified pinned BusyBox and sealed successor Binutils inputs'
