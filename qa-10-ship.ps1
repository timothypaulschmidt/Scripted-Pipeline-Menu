# qa-10: ship an app to qa. Run on Windows after dev-05 has published the image and the
# change is merged on GitHub main.  .\qa-10-ship.ps1 assistant | mcp | agents | all
# It checks the image exists, then over ssh updates the VM's scripts and code and deploys.
param([string]$App = "")
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\ship.ps1")
Invoke-Ship -EnvName qa -App $App
