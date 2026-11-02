# prod-11: run one of the prod VM's scripts from Windows, over ssh.
#   .\prod-11-remote.ps1 status
#   .\prod-11-remote.ps1 logs agents -f
#   .\prod-11-remote.ps1 reset
#   .\prod-11-remote.ps1 secrets gemini
# Actions: pull, deploy, status, logs, reset, secrets, urls
param([string]$Action = "", [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
. (Join-Path $PSScriptRoot "lib\ship.ps1")
Invoke-Remote -EnvName prod -Action $Action -Rest $Rest
