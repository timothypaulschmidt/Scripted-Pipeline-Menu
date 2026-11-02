# qa-11: run one of the qa VM's scripts from Windows, over ssh.
#   .\qa-11-remote.ps1 status
#   .\qa-11-remote.ps1 logs agents -f
#   .\qa-11-remote.ps1 reset
#   .\qa-11-remote.ps1 secrets gemini
# Actions: pull, deploy, status, logs, reset, secrets, urls
param([string]$Action = "", [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\ship.ps1")
Invoke-Remote -EnvName qa -Action $Action -Rest $Rest
