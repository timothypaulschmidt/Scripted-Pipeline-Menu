# qa-13: store the FortiAIGate API key on qa. You paste the key into the ssh terminal (masked);
# it goes straight into a Kubernetes Secret and the ai-assistant restarts (its route returns to direct).
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\ship.ps1")
Invoke-Remote -EnvName qa -Action secrets -Rest @("faig")
