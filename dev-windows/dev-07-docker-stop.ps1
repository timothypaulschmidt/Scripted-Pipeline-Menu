# dev-07: stop and remove the local containers (all of them, or one app).
param([string]$App = "all")
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
Require-Command docker "Install Docker Desktop and start it"
foreach ($a in (Resolve-Apps $App)) {
    $name = Get-AppValue $a "CONTAINER"
    Say "Stopping $name"
    $null = TryRun docker rm -f $name
}
Run docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
