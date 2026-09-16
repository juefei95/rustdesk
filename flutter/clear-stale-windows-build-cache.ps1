$ErrorActionPreference = "Stop"

$FlutterDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedTarget = "dianlian"
$BuildRoot = Join-Path $FlutterDirectory "build\windows\x64"
$CachePath = Join-Path $BuildRoot "CMakeCache.txt"

if (-not (Test-Path $CachePath)) {
    exit 0
}

$CacheContent = Get-Content -LiteralPath $CachePath -Raw
if ($CacheContent -match '\$<TARGET_FILE_DIR:([^>]+)>') {
    $CachedTarget = $Matches[1]
    if ($CachedTarget -ne $ExpectedTarget) {
        Write-Host "Removing stale Flutter Windows CMake cache: target '$CachedTarget' != '$ExpectedTarget'"
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
        exit 0
    }
}

$ExpectedProject = Join-Path $BuildRoot "runner\$ExpectedTarget.vcxproj"
if (-not (Test-Path $ExpectedProject)) {
    Write-Host "Removing stale Flutter Windows CMake cache: missing $ExpectedTarget.vcxproj"
    Remove-Item -LiteralPath $BuildRoot -Recurse -Force
}
