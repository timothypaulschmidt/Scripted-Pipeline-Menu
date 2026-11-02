# dev-03: download the ready-made Docker images (no source code or Python needed).
# This is the "first time on a new computer" docker step. It pulls the exact version each
# repo's deploy manifest asks for, so you test what QA will run.
#   .\dev-03-docker-pull.ps1 all | assistant | mcp | agents
param([string]$App = "all")
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
Require-Command docker "Install Docker Desktop and start it"
if (-not (Test-Quiet docker info)) { Die "Docker is not running. Start Docker Desktop first." }

Intro "DOWNLOAD DOCKER IMAGES: each repo records which image version it wants in its deploy manifest (the newTag line). We read that, then pull exactly that version from Docker Hub, so what you test here is what QA runs."
foreach ($a in (Resolve-Apps $App)) {
    $image = Get-Image $a
    $tag = Get-ManifestTag $a
    if (-not $tag) {
        # Repo not cloned here: read the manifest straight from GitHub instead.
        $url = "https://raw.githubusercontent.com/{0}/{1}/main/{2}" -f $Lab["GITHUB_USER"], (Get-AppValue $a "REPO"), (Get-AppValue $a "TAG_FILE")
        Say "$a is not cloned here; reading its version from GitHub"
        try { $tag = Get-ManifestTagFromText ((Invoke-WebRequest -UseBasicParsing $url).Content -split "`r?`n") $image }
        catch { Die "Could not read $url : $($_.Exception.Message)" }
    }
    if (-not $tag) { Die "No version found for $image" }
    Say "Pulling $image`:$tag"
    Run docker pull ($image + ":" + $tag)
}
Ok "Images downloaded. Run them with .\dev-04-docker-run.ps1"
