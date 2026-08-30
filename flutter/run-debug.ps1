$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $ScriptDirectory "run-release.ps1") --debug @args
exit $LASTEXITCODE
