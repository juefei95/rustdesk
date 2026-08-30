$ErrorActionPreference = "Stop"

$FlutterDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDirectory = Split-Path -Parent $FlutterDirectory
$OriginalDirectory = Get-Location

function Invoke-CommandChecked {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Test-LlvmPath {
    param([string]$Path)

    return $Path -and (Test-Path (Join-Path $Path "bin\libclang.dll"))
}

function Find-LlvmPath {
    $Candidates = @(
        $env:LLVM_PATH,
        $env:LLVM_HOME,
        "C:\Program Files\LLVM",
        "C:\Program Files (x86)\LLVM"
    )

    $VsWhere = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe",
        "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($VsWhere) {
        $VsInstallations = & $VsWhere -products * -property installationPath
        foreach ($VsInstallation in $VsInstallations) {
            $Candidates += @(
                (Join-Path $VsInstallation "VC\Tools\Llvm\x64"),
                (Join-Path $VsInstallation "VC\Tools\Llvm")
            )
        }
    }

    foreach ($Candidate in $Candidates) {
        if (Test-LlvmPath $Candidate) {
            return $Candidate
        }
    }

    $Libclang = Get-ChildItem -Path @(
        "C:\Program Files\Microsoft Visual Studio",
        "C:\Program Files (x86)\Microsoft Visual Studio",
        "D:\Program Files\Microsoft Visual Studio",
        "D:\Program Files (x86)\Microsoft Visual Studio"
    ) -Filter libclang.dll -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($Libclang) {
        $BinDirectory = Split-Path -Parent $Libclang.FullName
        if ((Split-Path -Leaf $BinDirectory) -eq "bin") {
            return Split-Path -Parent $BinDirectory
        }
    }

    return $null
}

function Find-CmakeBinPath {
    $CmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    if ($CmakeCommand) {
        return Split-Path -Parent $CmakeCommand.Source
    }

    $Candidates = @()
    $VsWhere = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe",
        "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($VsWhere) {
        $VsInstallations = & $VsWhere -products * -property installationPath
        foreach ($VsInstallation in $VsInstallations) {
            $Candidates += Join-Path $VsInstallation "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
        }
    }

    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path (Join-Path $Candidate "cmake.exe"))) {
            return $Candidate
        }
    }

    return $null
}

function Install-VcpkgPackages {
    Invoke-CommandChecked vcpkg @(
        "install",
        "--triplet=x64-windows-static",
        "--host-triplet=x64-windows"
    )
}

function Initialize-VcpkgEnvironment {
    $InstalledRoot = Join-Path $ProjectDirectory "vcpkg_installed"
    $CargoVcpkgRoot = Join-Path $ProjectDirectory "target\vcpkg-root"
    $CargoInstalledRoot = Join-Path $CargoVcpkgRoot "installed"

    if (-not (Test-Path $InstalledRoot)) {
        Write-Error "vcpkg packages were not installed at $InstalledRoot"
        exit 1
    }

    New-Item -ItemType Directory -Path $CargoVcpkgRoot -Force | Out-Null
    if (Test-Path $CargoInstalledRoot) {
        $Existing = Get-Item -LiteralPath $CargoInstalledRoot -Force
        if (-not $Existing.LinkType) {
            Write-Error "$CargoInstalledRoot already exists and is not a directory link."
            exit 1
        }
    } else {
        New-Item -ItemType Junction -Path $CargoInstalledRoot -Target $InstalledRoot | Out-Null
    }

    $env:VCPKG_ROOT = $CargoVcpkgRoot
    $env:VCPKG_INSTALLED_ROOT = $InstalledRoot
}

try {
Set-Location $ProjectDirectory

if (-not (Test-Path "./libs/hbb_common/Cargo.toml")) {
    Write-Host "Initializing Git submodules..."
    Invoke-CommandChecked git @("submodule", "update", "--init", "--recursive")
}

$LlvmPath = Find-LlvmPath
if (-not $LlvmPath) {
    Write-Error "LLVM was not found. Install LLVM for Windows, or set LLVM_PATH to the folder that contains bin\libclang.dll, for example: C:\Program Files\LLVM"
    exit 1
}
$env:LIBCLANG_PATH = Join-Path $LlvmPath "bin"

Remove-Item Env:VCPKG_FORCE_SYSTEM_BINARIES -ErrorAction SilentlyContinue
$CmakeBinPath = Find-CmakeBinPath
if ($CmakeBinPath) {
    $env:PATH = "$CmakeBinPath;$env:PATH"
}
Install-VcpkgPackages
Initialize-VcpkgEnvironment

Invoke-CommandChecked cargo @(
    "install", "cargo-expand", "--version", "1.0.95", "--locked"
)
Invoke-CommandChecked cargo @(
    "install", "flutter_rust_bridge_codegen", "--version", "1.80.1",
    "--features", "uuid", "--locked"
)

Set-Location $FlutterDirectory
Invoke-CommandChecked flutter @("pub", "get")
Set-Location $ProjectDirectory

Invoke-CommandChecked flutter_rust_bridge_codegen @(
    "--rust-input", "./src/flutter_ffi.rs",
    "--dart-output", "./flutter/lib/generated_bridge.dart",
    "--c-output", "./flutter/macos/Runner/bridge_generated.h",
    "--llvm-path", $LlvmPath
)

Invoke-CommandChecked cargo @("build", "--locked", "--features", "flutter")

Set-Location $FlutterDirectory
Invoke-CommandChecked flutter (@("run", "-d", "windows") + $args)
} finally {
    Set-Location $OriginalDirectory
}
