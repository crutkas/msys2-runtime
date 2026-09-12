param(
    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string] $SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string] $PsapiLibrary,

    [Parameter(Mandatory = $true)]
    [string] $UserenvLibrary
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = (Resolve-Path $SourceDirectory).Path
$buildRoot = Join-Path $OutputDirectory 'build'
$linkRoot = Join-Path $OutputDirectory 'link-lib'
$compilerRoot = 'C:\ag-readline-e138-01\combined-20260911-01\compiler'
$cxx = Join-Path $compilerRoot 'bin\g++.exe'
$runtimeImport = Join-Path $compilerRoot 'aarch64-pc-cygwin\lib\libmsys-2.0.a'
$psapiImport = (Resolve-Path $PsapiLibrary).Path
$userenvImport = (Resolve-Path $UserenvLibrary).Path
$specs = Join-Path $compilerRoot 'lib\gcc\aarch64-pc-cygwin\15.0.1\specs'

function ConvertTo-GccPath {
    param([string] $Path)
    $Path.Replace('\', '/')
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
New-Item -ItemType Directory -Force -Path $linkRoot | Out-Null
Copy-Item -LiteralPath $psapiImport -Destination (Join-Path $linkRoot 'libpsapi.a') -Force
Copy-Item -LiteralPath $userenvImport -Destination (Join-Path $linkRoot 'libuserenv.a') -Force

$sourceGcc = ConvertTo-GccPath $sourceRoot
$buildGcc = ConvertTo-GccPath $buildRoot
$linkGcc = ConvertTo-GccPath $linkRoot
$compilerGcc = ConvertTo-GccPath $compilerRoot
$specsGcc = ConvertTo-GccPath $specs
$prefixMappings = @(
    [ordered]@{ path = $sourceRoot; target = '/usr/src/msys2-runtime' },
    [ordered]@{ path = $buildRoot; target = '/usr/src/msys2-build' },
    [ordered]@{ path = $compilerRoot; target = '/opt/arm64-msys2-toolchain' },
    [ordered]@{ path = $repoRoot; target = '/usr/src/msys2-build-driver' },
    [ordered]@{ path = (Join-Path $sourceRoot 'utils'); target = '/usr/src/msys2-runtime/winsup/utils' },
    [ordered]@{ path = (Join-Path $sourceRoot 'cygwin'); target = '/usr/src/msys2-runtime/winsup/cygwin' },
    [ordered]@{ path = (Join-Path $sourceRoot 'newlib'); target = '/usr/src/msys2-runtime/newlib' },
    [ordered]@{ path = (Join-Path $buildRoot 'cygwin'); target = '/usr/src/msys2-build/winsup/cygwin' },
    [ordered]@{ path = (Join-Path $buildRoot 'newlib'); target = '/usr/src/msys2-build/newlib' }
)
$prefixMapArguments = foreach ($mapping in $prefixMappings) {
    $forms = @($mapping.path, (ConvertTo-GccPath $mapping.path)) | Select-Object -Unique
    foreach ($form in $forms) {
        "-ffile-prefix-map=$form=$($mapping.target)"
        "-fdebug-prefix-map=$form=$($mapping.target)"
        "-fmacro-prefix-map=$form=$($mapping.target)"
    }
}

$common = @(
    '-DHAVE_CONFIG_H',
    "-I$sourceGcc/utils",
    "-I$buildGcc/cygwin",
    '-U_FORTIFY_SOURCE',
    '-D__MSYS__',
    "-I$sourceGcc/cygwin/local_includes",
    "-I$buildGcc/cygwin",
    "-isystem$sourceGcc/cygwin/include",
    "-isystem$buildGcc/newlib/targ-include",
    "-isystem$sourceGcc/newlib/libc/include",
    '-fno-rtti',
    '-fno-exceptions',
    '-fno-use-cxa-atexit',
    '-Wall',
    '-Wstrict-aliasing',
    '-Wwrite-strings',
    '-fno-common',
    '-pipe',
    '-fbuiltin',
    '-fmessage-length=0',
    '-Wimplicit-fallthrough=4',
    '-Werror',
    '-D_WIN32_WINNT=0x0a00',
    '-DNTDDI_VERSION=WDK_NTDDI_VERSION',
    '-g',
    '-O2'
) + $prefixMapArguments

function Invoke-Compiler {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Step,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & $cxx @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

$recipes = @(
    [ordered]@{
        name = 'ps'
        sources = @('ps.cc')
        compile_flags = @()
        link_libraries = @('-lnetapi32', '-lpsapi', '-lntdll')
    },
    [ordered]@{
        name = 'mount'
        sources = @('mount.cc', 'path.cc')
        compile_flags = @('-DFSTAB_ONLY')
        link_libraries = @('-lnetapi32')
    },
    [ordered]@{
        name = 'cygpath'
        sources = @('cygpath.cc')
        compile_flags = @('-fno-threadsafe-statics')
        link_libraries = @('-lnetapi32', '-luserenv', '-lntdll')
    }
)

$records = @()
Push-Location $buildRoot
try {
    $records = foreach ($recipe in $recipes) {
        $objects = foreach ($sourceName in $recipe.sources) {
            $baseName = [IO.Path]::GetFileNameWithoutExtension($sourceName)
            $object = Join-Path $buildRoot "$($recipe.name)-$baseName.o"
            $objectGcc = ConvertTo-GccPath $object
            $sourceFile = Join-Path $sourceRoot "utils\$sourceName"
            $sourceFileGcc = ConvertTo-GccPath $sourceFile
            $compileArguments = $common + $recipe.compile_flags + @(
                '-c',
                '-o',
                $objectGcc,
                $sourceFileGcc
            )
            Invoke-Compiler -Step "$sourceName compilation" -Arguments $compileArguments
            [ordered]@{
                source = $sourceFile
                object = $object
                argv = @($cxx) + $compileArguments
            }
        }

        $output = Join-Path $buildRoot "$($recipe.name).exe"
        $linkMap = Join-Path $buildRoot "$($recipe.name).map"
        $linkArguments = $common + $recipe.compile_flags + @(
            '-static',
            '-Wl,--enable-auto-import',
            '-Wl,--no-insert-timestamp',
            "-Wl,-Map=$(ConvertTo-GccPath $linkMap)",
            "-specs=$specsGcc",
            "-L$linkGcc",
            '-o',
            (ConvertTo-GccPath $output)
        ) + @($objects.object | ForEach-Object { ConvertTo-GccPath $_ }) + $recipe.link_libraries
        Invoke-Compiler -Step "$($recipe.name).exe link" -Arguments $linkArguments

        [ordered]@{
            name = $recipe.name
            sources = @($objects)
            output = $output
            link_map = $linkMap
            link_argv = @($cxx) + $linkArguments
        }
    }
} finally {
    Pop-Location
}

[ordered]@{
    compiler = $cxx
    compiler_specs = $specs
    runtime_import = $runtimeImport
    psapi_import = $psapiImport
    userenv_import = $userenvImport
    compiler_working_directory = $buildRoot
    prefix_mappings = $prefixMappings
    recipes = @($records)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-command.json') -Encoding utf8NoBOM
