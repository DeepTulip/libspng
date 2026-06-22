param(
    [string]$OutputDir = "",
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if(-not [Environment]::Is64BitProcess)
{
    throw "Run this script from 64-bit PowerShell."
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($OutputDir))
{
    $OutputDir = Join-Path $RepoRoot "build\libspng-x64"
}

function Add-PathIfExists([string]$Path)
{
    if((Test-Path $Path) -and (($env:Path -split ";") -notcontains $Path))
    {
        $env:Path = "$Path;$env:Path"
    }
}

function Use-CommonToolPaths
{
    Add-PathIfExists "C:\ProgramData\chocolatey\bin"
    Add-PathIfExists "C:\tools\mingw64\bin"
    Add-PathIfExists "C:\ProgramData\mingw64\mingw64\bin"

    if($env:ChocolateyInstall)
    {
        Add-PathIfExists (Join-Path $env:ChocolateyInstall "lib\mingw\tools\install\mingw64\bin")
    }
}

function Require-Command([string]$Name)
{
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if($null -eq $Command)
    {
        throw "$Name was not found on PATH."
    }

    return $Command.Source
}

function Ensure-MinGW64
{
    Use-CommonToolPaths

    $Gcc = Get-Command "gcc.exe" -ErrorAction SilentlyContinue
    if($null -eq $Gcc -and -not $SkipInstall)
    {
        $Choco = Get-Command "choco.exe" -ErrorAction SilentlyContinue
        if($null -eq $Choco)
        {
            throw "gcc.exe is missing and Chocolatey is not available to install mingw."
        }

        & $Choco.Source install mingw -y --no-progress
        if($LASTEXITCODE -ne 0) { throw "Chocolatey failed to install mingw." }

        Use-CommonToolPaths
        $Gcc = Get-Command "gcc.exe" -ErrorAction SilentlyContinue
    }

    if($null -eq $Gcc) { throw "gcc.exe was not found after setup." }

    $DumpMachine = & $Gcc.Source -dumpmachine
    if($LASTEXITCODE -ne 0) { throw "gcc -dumpmachine failed." }
    if($DumpMachine -notmatch "x86_64")
    {
        throw "Expected an x86_64 MinGW compiler, got '$DumpMachine'."
    }

    return $Gcc.Source
}

function Ensure-Zlib([string]$Directory)
{
    if(Test-Path (Join-Path $Directory "zlib.h"))
    {
        return
    }

    if(Test-Path $Directory)
    {
        Remove-Item -Recurse -Force $Directory
    }

    $Git = Require-Command "git.exe"
    & $Git clone --depth 1 --branch "v1.2.13" "https://github.com/madler/zlib.git" $Directory
    if($LASTEXITCODE -ne 0) { throw "Failed to download zlib." }
}

$GccPath = Ensure-MinGW64

$BuildDir = Join-Path $RepoRoot "build"
if(-not (Test-Path $BuildDir))
{
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

$ZlibDir = Join-Path $BuildDir "zlib-1.2.13"
Ensure-Zlib $ZlibDir

if(-not (Test-Path $OutputDir))
{
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$Dll = Join-Path $OutputDir "libspng.dll"
$ImportLib = Join-Path $OutputDir "libspng.dll.a"
$DefFile = Join-Path $OutputDir "libspng.def"

$CompileArgs = @(
    "-m64",
    "-shared",
    "-O2",
    "-std=c99",
    "-Wall",
    "-Wextra",
    "-I", (Join-Path $RepoRoot "spng"),
    "-I", $ZlibDir,
    (Join-Path $RepoRoot "spng\spng.c"),
    (Join-Path $RepoRoot "spng\enc.c"),
    (Join-Path $ZlibDir "adler32.c"),
    (Join-Path $ZlibDir "compress.c"),
    (Join-Path $ZlibDir "crc32.c"),
    (Join-Path $ZlibDir "deflate.c"),
    (Join-Path $ZlibDir "infback.c"),
    (Join-Path $ZlibDir "inffast.c"),
    (Join-Path $ZlibDir "inflate.c"),
    (Join-Path $ZlibDir "inftrees.c"),
    (Join-Path $ZlibDir "trees.c"),
    (Join-Path $ZlibDir "uncompr.c"),
    (Join-Path $ZlibDir "zutil.c"),
    "-o", $Dll,
    "-Wl,--out-implib,$ImportLib",
    "-Wl,--output-def,$DefFile",
    "-static-libgcc",
    "-lm"
)

& $GccPath @CompileArgs
if($LASTEXITCODE -ne 0) { throw "libspng.dll build failed." }

$Objdump = Get-Command "objdump.exe" -ErrorAction SilentlyContinue
if($null -ne $Objdump)
{
    & $Objdump.Source -p $Dll | Select-String -Pattern "enc|enc_free|spng_encode_image" | ForEach-Object { $_.Line }
}

Write-Output "Built $Dll"
