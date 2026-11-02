# prod-12: change the Gemini API key on prod. You paste the key into the ssh terminal (hidden);
# it goes straight into a Kubernetes Secret and the pods that use it restart.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\ship.ps1")
Invoke-Remote -EnvName prod -Action secrets -Rest @("gemini")
