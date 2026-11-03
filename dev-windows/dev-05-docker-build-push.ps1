# dev-05: release a new version of one app: test it, build the Docker image, push it to
# Docker Hub, and record the new version in the repo's deploy manifest.
#   .\dev-windows\dev-05-docker-build-push.ps1 assistant | mcp | agents
# It shows the version now in the manifest, checks whether that version is already on
# Docker Hub, suggests the next one, and asks you. Nothing is pushed until you confirm.
# Why the order: the image goes to Docker Hub BEFORE the manifest is pushed to GitHub, so
# QA can never be told to run a version that does not exist yet.
param([Parameter(Mandatory = $true)][string]$App, [switch]$SkipTests)
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
Require-Command docker "Install Docker Desktop and start it"
Require-Command git "Install Git for Windows"
if (-not (Test-Quiet docker info)) { Die "Docker is not running. Start Docker Desktop first." }
$a = (Resolve-Apps $App)[0]
if ((Resolve-Apps $App).Count -ne 1) { Die "Pick one app: assistant, mcp or agents" }
$path = Assert-RepoExists $a
$image = Get-Image $a
$tagFile = Get-AppValue $a "TAG_FILE"

Intro "RELEASING A NEW VERSION: (1) pick a version number, (2) run the tests, (3) build the image, (4) push it to Docker Hub, (5) only then record the version in the repo manifest and push that to GitHub. Doing Docker Hub first means QA is never told to run an image that does not exist yet."
Push-Location $path
try {
    Say "Where this repo is"
    $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
    Write-Host "  branch: $branch"
    if ($branch -ne "main") { Warn "You are not on main. Releases normally come from main." ; if (-not (Confirm-Yes "Continue anyway?")) { Die "Cancelled." } }
    $dirty = (& git status --porcelain)
    if ($dirty) { Warn "Uncommitted changes (they will be part of the image build but NOT of the commit):"; $dirty | ForEach-Object { Write-Host "    $_" } }

    $current = Get-ManifestTag $a
    if (-not $current) { Die "Could not read the current version of $image from $tagFile" }
    Say "Versions"
    Write-Host "  In the manifest ($tagFile): $current"
    $onHub = Test-ImageOnHub $image $current
    if ($onHub) { Write-Host "  On Docker Hub:              $current is already published" }
    else        { Write-Host "  On Docker Hub:              $current is NOT published yet" }

    if ($onHub) { $suggest = Get-NextPatch $current } else { $suggest = $current }
    $new = Read-Host "New version [$suggest]"
    if (-not $new) { $new = $suggest }
    if (-not (Test-TagFormat $new)) { Die "Versions look like v0.2.2 (lowercase v, three numbers). You typed '$new'." }
    if ($new -ne $current -and (Test-ImageOnHub $image $new)) { Die "$image`:$new is already on Docker Hub. Pick a different version." }
    if ($new -eq $current -and $onHub) { Die "$image`:$new is already on Docker Hub. Pick a new version." }

    Say "Plan"
    Write-Host "  1. run the tests"
    Write-Host "  2. docker build  -> $image`:$new"
    Write-Host "  3. docker push   -> Docker Hub"
    if ($new -ne $current) { Write-Host "  4. change $tagFile from $current to $new, commit, push to GitHub main" }
    if (-not (Confirm-Yes "Go ahead?")) { Die "Cancelled. Nothing was changed." }

    if (-not $SkipTests) {
        Say "Running the tests"
        if (Test-Path "requirements-dev.txt") { Run python -m pip install -q -r requirements-dev.txt; Run python -m pip install -q -e . }
        else { Run python -m pip install -q -e ".[dev]" }
        Run python -m pytest -q
    }

    Say "Building the image"
    Run docker build -t ($image + ":" + $new) .
    Say "Pushing to Docker Hub (if this asks you to log in, run: docker login)"
    Run docker push ($image + ":" + $new)

    if ($new -ne $current) {
        Say "Recording $new in the deploy manifest"
        if (-not $Dry) { Set-ManifestTag $a $new }
        Run git add $tagFile
        Run git commit -m ("Release " + (Get-AppValue $a "IMAGE") + " " + $new)
        Run git push origin $branch
        if ($branch -ne "main") { Warn "You pushed branch '$branch'. Merge it on GitHub before shipping." }
    } else {
        Ok "The manifest already says $new, so there is nothing to commit."
    }
} finally { Pop-Location }

Ok "$image`:$new is published"
Say "Next: ship it to QA"
Write-Host "  .\dev-windows\qa-10-ship.ps1 $a"
Show-Addresses
