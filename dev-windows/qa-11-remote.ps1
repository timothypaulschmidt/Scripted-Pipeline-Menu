# qa-11: run one of the qa VM's scripts from Windows, over ssh.
#   .\dev-windows\qa-11-remote.ps1 status
#   .\dev-windows\qa-11-remote.ps1 logs agents -f
#   .\dev-windows\qa-11-remote.ps1 reset
#   .\dev-windows\qa-11-remote.ps1 secrets gemini
# Actions: pull, deploy, status, logs, reset, secrets, urls
param([string]$Action = "", [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\ship.ps1")
Invoke-Remote -EnvName qa -Action $Action -Rest $Rest
