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

function Find-VcpkgRoot {
    $Candidates = @(
        $env:VCPKG_ROOT,
        (Join-Path $ProjectDirectory "vcpkg"),
        (Join-Path (Split-Path -Parent $ProjectDirectory) "vcpkg"),
        "C:\vcpkg",
        "D:\vcpkg",
        "E:\vcpkg"
    )

    $VcpkgCommand = Get-Command vcpkg -ErrorAction SilentlyContinue
    if ($VcpkgCommand) {
        $Candidates += Split-Path -Parent $VcpkgCommand.Source
    }

    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path (Join-Path $Candidate "vcpkg.exe"))) {
            return $Candidate
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
    param([string]$VcpkgRoot)

    $TripletDirectory = Join-Path $VcpkgRoot "installed\x64-windows-static"
    $RequiredFiles = @(
        "lib\vpx.lib",
        "include\libyuv.h",
        "lib\opus.lib",
        "lib\aom.lib"
    )

    $MissingPackage = $false
    foreach ($RequiredFile in $RequiredFiles) {
        if (-not (Test-Path (Join-Path $TripletDirectory $RequiredFile))) {
            $MissingPackage = $true
            break
        }
    }

    if ($MissingPackage) {
        Invoke-CommandChecked (Join-Path $VcpkgRoot "vcpkg.exe") @(
            "install",
            "libvpx:x64-windows-static",
            "libyuv:x64-windows-static",
            "opus:x64-windows-static",
            "aom:x64-windows-static",
            "--classic",
            "--host-triplet=x64-windows",
            "--x-install-root=$(Join-Path $VcpkgRoot "installed")"
        )
    }
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

$VcpkgRoot = Find-VcpkgRoot
if (-not $VcpkgRoot) {
    Write-Error "vcpkg was not found. Clone and bootstrap vcpkg, then set VCPKG_ROOT to that folder."
    exit 1
}
$env:VCPKG_ROOT = $VcpkgRoot
Remove-Item Env:VCPKG_FORCE_SYSTEM_BINARIES -ErrorAction SilentlyContinue
$CmakeBinPath = Find-CmakeBinPath
if ($CmakeBinPath) {
    $env:PATH = "$CmakeBinPath;$env:PATH"
}
Install-VcpkgPackages $VcpkgRoot

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
