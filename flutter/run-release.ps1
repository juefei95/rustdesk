$ErrorActionPreference = "Stop"

$FlutterDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDirectory = Split-Path -Parent $FlutterDirectory
$OriginalDirectory = Get-Location
$Script:RunPs1ExitCode = 0

function Stop-ScriptWithExitCode {
    param(
        [int]$ExitCode,
        [string]$Message
    )

    $Script:RunPs1ExitCode = $ExitCode
    throw $Message
}

function Invoke-CommandChecked {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        Stop-ScriptWithExitCode $LASTEXITCODE "$Command failed with exit code $LASTEXITCODE"
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
        Stop-ScriptWithExitCode 1 "vcpkg packages were not installed at $InstalledRoot"
    }

    New-Item -ItemType Directory -Path $CargoVcpkgRoot -Force | Out-Null
    if (Test-Path $CargoInstalledRoot) {
        $Existing = Get-Item -LiteralPath $CargoInstalledRoot -Force
        if (-not $Existing.LinkType) {
            Stop-ScriptWithExitCode 1 "$CargoInstalledRoot already exists and is not a directory link."
        }
        if ($Existing.Target -ne $InstalledRoot) {
            Remove-Item -LiteralPath $CargoInstalledRoot
            New-Item -ItemType Junction -Path $CargoInstalledRoot -Target $InstalledRoot | Out-Null
        }
    } else {
        New-Item -ItemType Junction -Path $CargoInstalledRoot -Target $InstalledRoot | Out-Null
    }

    $env:VCPKG_ROOT = $CargoVcpkgRoot
    $env:VCPKG_INSTALLED_ROOT = $InstalledRoot
}

function Get-CargoBuildArguments {
    param([string[]]$BuildArguments)

    $CargoArguments = @("build", "--locked", "--features", "flutter", "--lib")
    if ($BuildArguments -notcontains "--debug") {
        $CargoArguments += "--release"
    }
    return $CargoArguments
}

function Get-FlutterBuildModeDirectory {
    param([string[]]$BuildArguments)

    if ($BuildArguments -contains "--debug") {
        return "Debug"
    }
    if ($BuildArguments -contains "--profile") {
        return "Profile"
    }
    return "Release"
}

function Stop-BuildOutputProcess {
    param([string[]]$BuildArguments)

    $BuildModeDirectory = Get-FlutterBuildModeDirectory $BuildArguments
    $OutputExe = Join-Path $FlutterDirectory "build\windows\x64\runner\$BuildModeDirectory\rustdesk.exe"
    $OutputExeFullPath = [System.IO.Path]::GetFullPath($OutputExe)

    Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -eq $OutputExeFullPath)
            } catch {
                $false
            }
        } |
        ForEach-Object {
            Write-Host "Stopping running build output: $($_.Path)"
            Stop-Process -Id $_.Id -Force
            $_.WaitForExit()
        }
}

function New-DirectoryJunction {
    param(
        [string]$Path,
        [string]$Target
    )

    if (Test-Path $Path) {
        $Existing = Get-Item -LiteralPath $Path -Force
        if ($Existing.LinkType -and $Existing.Target -eq $Target) {
            return
        }
        throw "$Path already exists and does not point to $Target"
    }

    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
}

function Set-FileContentIfChanged {
    param(
        [string]$Path,
        [string]$Content
    )

    if ((Test-Path $Path) -and ([System.IO.File]::ReadAllText($Path) -eq $Content)) {
        return
    }

    [System.IO.File]::WriteAllText($Path, $Content)
}

function Initialize-CargoManifestOverlay {
    $OverlayRoot = Join-Path $ProjectDirectory "target\run-ps1-overlay"
    New-Item -ItemType Directory -Path $OverlayRoot -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $ProjectDirectory "Cargo.toml") -Destination (Join-Path $OverlayRoot "Cargo.toml") -Force
    Copy-Item -LiteralPath (Join-Path $ProjectDirectory "Cargo.lock") -Destination (Join-Path $OverlayRoot "Cargo.lock") -Force
    Copy-Item -LiteralPath (Join-Path $ProjectDirectory "build.rs") -Destination (Join-Path $OverlayRoot "build.rs") -Force

    New-DirectoryJunction (Join-Path $OverlayRoot "src") (Join-Path $ProjectDirectory "src")
    New-DirectoryJunction (Join-Path $OverlayRoot "flutter") (Join-Path $ProjectDirectory "flutter")
    New-DirectoryJunction (Join-Path $OverlayRoot "res") (Join-Path $ProjectDirectory "res")

    $OverlayLibs = Join-Path $OverlayRoot "libs"
    New-Item -ItemType Directory -Path $OverlayLibs -Force | Out-Null
    foreach ($Name in @("hbb_common", "enigo", "clipboard", "virtual_display", "portable", "remote_printer", "libxdo-sys-stub")) {
        $Target = Join-Path $ProjectDirectory "libs\$Name"
        if (Test-Path $Target) {
            New-DirectoryJunction (Join-Path $OverlayLibs $Name) $Target
        }
    }

    $OverlayScrap = Join-Path $OverlayLibs "scrap"
    New-Item -ItemType Directory -Path $OverlayScrap -Force | Out-Null
    $ScrapManifestPath = Join-Path $ProjectDirectory "libs\scrap\Cargo.toml"
    $OriginalScrapManifest = [System.IO.File]::ReadAllText($ScrapManifestPath)
    $PatchedScrapManifest = $OriginalScrapManifest -replace `
        'drm = \["wayland", "hbb_common/wayland_probe"\]', `
        'drm = ["wayland"]'
    Set-FileContentIfChanged (Join-Path $OverlayScrap "Cargo.toml") $PatchedScrapManifest

    Get-ChildItem -LiteralPath (Join-Path $ProjectDirectory "libs\scrap") -Force |
        Where-Object { $_.Name -ne "Cargo.toml" } |
        ForEach-Object {
            $OverlayPath = Join-Path $OverlayScrap $_.Name
            if ($_.PSIsContainer) {
                New-DirectoryJunction $OverlayPath $_.FullName
            } else {
                Copy-Item -LiteralPath $_.FullName -Destination $OverlayPath -Force
            }
        }

    return $OverlayRoot
}

function Invoke-WithCargoManifestOverlay {
    param([scriptblock]$ScriptBlock)

    $OverlayRoot = Initialize-CargoManifestOverlay
    $OriginalCargoTargetDir = $env:CARGO_TARGET_DIR
    try {
        $env:CARGO_TARGET_DIR = Join-Path $ProjectDirectory "target"
        Set-Location $OverlayRoot
        & $ScriptBlock
    } finally {
        if ($null -eq $OriginalCargoTargetDir) {
            Remove-Item Env:CARGO_TARGET_DIR -ErrorAction SilentlyContinue
        } else {
            $env:CARGO_TARGET_DIR = $OriginalCargoTargetDir
        }
        Set-Location $ProjectDirectory
    }
}

try {
Set-Location $ProjectDirectory
$ScriptArguments = $args

if (-not (Test-Path "./libs/hbb_common/Cargo.toml")) {
    Write-Host "Initializing Git submodules..."
    Invoke-CommandChecked git @("submodule", "update", "--init", "--recursive")
}

$LlvmPath = Find-LlvmPath
if (-not $LlvmPath) {
    Stop-ScriptWithExitCode 1 "LLVM was not found. Install LLVM for Windows, or set LLVM_PATH to the folder that contains bin\libclang.dll, for example: C:\Program Files\LLVM"
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

Invoke-WithCargoManifestOverlay {
    Invoke-CommandChecked flutter_rust_bridge_codegen @(
        "--rust-input", "./src/flutter_ffi.rs",
        "--dart-output", "./flutter/lib/generated_bridge.dart",
        "--c-output", "./flutter/macos/Runner/bridge_generated.h",
        "--llvm-path", $LlvmPath
    )

    Invoke-CommandChecked cargo (Get-CargoBuildArguments $ScriptArguments)
}

Set-Location $FlutterDirectory
Stop-BuildOutputProcess $ScriptArguments
Invoke-CommandChecked flutter (@("build", "windows") + $ScriptArguments)
} catch {
    if (-not $Script:RunPs1ExitCode) {
        $Script:RunPs1ExitCode = 1
    }
    Write-Error $_
    exit $Script:RunPs1ExitCode
} finally {
    Set-Location $OriginalDirectory
}
