# dev-01: get the code. First time on a computer it CLONES; after that it PULLS the latest main
# (this is how a change that was merged on GitHub reaches this computer).
#   .\dev-windows\dev-01-git-pull.ps1 all | assistant | mcp | agents | menu
param([string]$Target = "all")
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
Require-Command git "Install Git for Windows: https://git-scm.com/download/win"

Intro "GETTING THE CODE: if a repo is not on this computer yet we CLONE it (a full copy from GitHub). If it is, we PULL (download the newest main and merge it in). A change merged on GitHub reaches you this way. A repo with unsaved edits of yours is skipped so nothing is overwritten."
$root = Get-Root
if (-not (Test-Path $root)) { Say "Creating $root"; if (-not $Dry) { New-Item -ItemType Directory -Path $root | Out-Null } }

$repos = @()
if ($Target -eq "menu") { $repos += $Lab["MENU_REPO"] }
elseif ($Target -eq "all") { foreach ($a in (Get-AppList)) { $repos += (Get-AppValue $a "REPO") }; $repos += $Lab["MENU_REPO"] }
else { foreach ($a in (Resolve-Apps $Target)) { $repos += (Get-AppValue $a "REPO") } }

foreach ($r in $repos) {
    $path = Join-Path $root $r
    if (Test-Path (Join-Path $path ".git")) {
        Say "Updating $r (git pull)"
        $dirty = (& git -C $path status --porcelain)
        if ($dirty) { Warn "$r has uncommitted changes, so I will not touch it:"; $dirty | ForEach-Object { Write-Host "    $_" }; continue }
        Run git -C $path fetch origin
        Run git -C $path checkout main
        Run git -C $path pull --ff-only origin main
        Run git -C $path log --oneline -3
    } else {
        Say "First time on this computer: cloning $r"
        Run git clone (Get-RepoUrl $r) $path
    }
}
Ok "Code is up to date"
