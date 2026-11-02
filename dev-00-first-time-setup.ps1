# dev-00: run this ONCE on a new Windows computer (after you have cloned Scripted-Pipeline-Menu).
# What it does: checks the tools you need, makes the shared Docker network, and clones
# the three app repos next to Scripted-Pipeline-Menu. Safe to run again: it only fills in what is missing.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")

Say "Checking the tools this lab needs"
$missing = 0
foreach ($t in @(
    @("git",    "Install Git for Windows: https://git-scm.com/download/win"),
    @("python", "Install Python 3.11 or newer from python.org (tick 'Add to PATH')"),
    @("docker", "Install Docker Desktop and start it"),
    @("ssh",    "Settings > Apps > Optional features > add 'OpenSSH Client'"))) {
    if (Get-Command $t[0] -ErrorAction SilentlyContinue) { Ok ($t[0] + " found") }
    else { Warn ($t[0] + " is missing. " + $t[1]); $missing++ }
}
if ($missing -gt 0) { Die "Install the missing tools above, open a NEW PowerShell window, and run this again." }

Say "Checking that Docker is running"
if (-not (Test-Quiet docker info)) { Die "Docker is installed but not running. Start Docker Desktop and run this again." }
Ok "Docker is running"

Say "Docker network '$($Lab['DOCKER_NETWORK'])' (lets the containers find each other by name)"
if (Test-Quiet docker network inspect $Lab["DOCKER_NETWORK"]) { Ok "already exists" }
else { Run docker network create $Lab["DOCKER_NETWORK"] }

Say "Cloning the app repos next to Scripted-Pipeline-Menu"
& (Join-Path $PSScriptRoot "dev-01-git-pull.ps1") all

Say "Docker Hub login (only needed on computers that BUILD and push images)"
Write-Host "  Pulling public images needs no login. To push, run:  docker login"

Show-Addresses
Say "Next steps"
Write-Host "  .\dev-02-run-python.ps1 all      run the three apps from source"
Write-Host "  .\dev-03-docker-pull.ps1 all     or fetch the ready-made images"
Write-Host "  .\dev-04-docker-run.ps1 all      and run those"
