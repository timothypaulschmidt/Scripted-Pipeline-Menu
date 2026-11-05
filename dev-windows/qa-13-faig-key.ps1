# qa-13: store the FortiAIGate API key on qa. You paste the key into the ssh terminal (masked);
# it goes straight into a Kubernetes Secret and the chosen app (ai-assistant or ai-agents, each has its own key) restarts (its route returns to direct).
param([string]$App = "assistant")
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\ship.ps1")
Invoke-Remote -EnvName qa -Action secrets -Rest @($(if ($App -eq "agents") { "faig-agents" } else { "faig" }))
