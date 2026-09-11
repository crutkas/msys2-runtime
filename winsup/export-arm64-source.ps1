param(
    [Parameter(Mandatory)] [string] $OutputDirectory
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$root = Split-Path $PSScriptRoot -Parent
$out = [IO.Path]::GetFullPath($OutputDirectory)
$relative = [IO.Path]::GetRelativePath($root, $out)
if ($relative -ne '..' -and
    -not $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar) -and
    -not [IO.Path]::IsPathRooted($relative)) {
    throw 'The export directory must be outside the source checkout'
}
if (Test-Path -LiteralPath $out) { throw "Use a new export directory: $out" }
New-Item -ItemType Directory -Path $out | Out-Null
Push-Location $root
try {
    $commit = git rev-parse HEAD
    $epoch = git show -s --format=%ct HEAD
    $version = (git describe --abbrev=12 --long --match 'cygwin*' --dirty) -replace '^cygwin-', ''
    if ($commit -notmatch '^[0-9a-f]{40}$' -or $epoch -notmatch '^\d+$' -or
        $version -notmatch '^[a-zA-Z0-9.+-]+$') { throw 'Invalid source metadata' }
    git -c core.autocrlf=false archive --format=tar --output="$out\base.tar" HEAD
    git diff --binary --output="$out\tracked.patch" HEAD
    $untracked = @(git ls-files --others --exclude-standard)
    $deleted = @(git diff --name-only --diff-filter=D HEAD)
    $files = @(git ls-files --cached --others --exclude-standard |
        Where-Object { $_ -notin $deleted } | Sort-Object -Unique -CaseSensitive)
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText("$out\source-files.txt", ($files -join "`n") + "`n", $utf8)
    [IO.File]::WriteAllText("$out\untracked-files.txt", ($untracked -join "`n") + "`n", $utf8)
    if ($untracked.Count) {
        tar.exe -cf "$out\untracked.tar" -T "$out\untracked-files.txt"
    }
    [IO.File]::WriteAllText("$out\source-version.env",
        "export MSYS2_RUNTIME_COMMIT='$commit'`nexport SOURCE_DATE_EPOCH='$epoch'`nexport UNAME_DEV_VERSION='$version'`n",
        $utf8)
    $manifest = Get-ChildItem -LiteralPath $out -File | Sort-Object Name | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
    }
    [IO.File]::WriteAllText("$out\SHA256SUMS", ($manifest -join "`n") + "`n", $utf8)
    "Exported $($files.Count) source paths ($($untracked.Count) untracked) at $commit to $out"
} finally {
    Pop-Location
}
