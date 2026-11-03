# Shared by qa-10-ship.ps1 and prod-10-ship.ps1. Dot-source after common.ps1.

# Read a file as it is on GitHub main (not whatever is in your working folder).
function Get-RemoteMainFile {
    param([string]$App, [string]$RelPath)
    $repo = Get-RepoPath $App
    $null = & git -C $repo fetch origin main 2>&1
    return (& git -C $repo show ("origin/main:" + $RelPath))
}

function Invoke-Ship {
    param([string]$EnvName, [string]$App)
    Require-Command git "Install Git for Windows"
    Require-Command docker "Install Docker Desktop"
    $apps = Resolve-Apps $App
    $vm = Get-VmInfo $EnvName
    $p = $EnvName + "-"

    Intro "SHIPPING to ${EnvName}: first we check, from your computer, that GitHub main wants a version that really exists on Docker Hub. Then ONE ssh session on the VM updates its copy of these scripts, pulls the app code, and deploys. Nothing is copied by hand."
    Say "Checking that each app's new version is ready to ship"
    foreach ($a in $apps) {
        $null = Assert-RepoExists $a
        $image = Get-Image $a
        $lines = @(Get-RemoteMainFile $a (Get-AppValue $a "TAG_FILE"))
        $tag = Get-ManifestTagFromText $lines $image
        if (-not $tag) { Die "No version for $image found in $a's manifest on GitHub main." }
        if (Test-ImageOnHub $image $tag) { Ok "$a : $image`:$tag is on GitHub main and on Docker Hub" }
        else { Die "$a : GitHub main wants $image`:$tag but that image is not on Docker Hub. Run .\dev-windows\dev-05-docker-build-push.ps1 $a first." }
    }

    Confirm-Prod $EnvName
    $yes = ""; if ($EnvName -eq "prod") { $yes = "LAB_YES=1 " }

    # One ssh session does it all: update the scripts, update the code, deploy.
    $cmd = "cd " + $vm.Root + "/" + $Lab["MENU_REPO"] + " && git pull --ff-only origin main"
    foreach ($a in $apps) {
        $cmd += " && " + $yes + "./" + $EnvName + "-linux/" + $p + "01-git-pull.sh " + $a
        $cmd += " && " + $yes + "./" + $EnvName + "-linux/" + $p + "02-deploy.sh " + $a
    }
    Say ("Shipping to " + $EnvName + " (" + $vm.Host + ")")
    Invoke-Vm $EnvName $cmd
    Show-Addresses
}

# Run one of the VM's scripts from Windows.  .\dev-windows\qa-11-remote.ps1 logs agents -f
function Invoke-Remote {
    param([string]$EnvName, [string]$Action, [string[]]$Rest)
    $map = [ordered]@{
        "pull" = "01-git-pull.sh"; "deploy" = "02-deploy.sh"; "status" = "03-status.sh"; "logs" = "04-logs.sh";
        "reset" = "05-reset-mcp-data.sh"; "secrets" = "06-secrets.sh"; "models" = "07-pull-models.sh"; "mode" = "08-mcp-mode.sh"; "urls" = "09-urls.sh"
    }
    if (-not $Action -or -not $map.Contains($Action)) {
        Die ("Usage: .\" + $EnvName + "-11-remote.ps1 <" + ($map.Keys -join "|") + "> [arguments]   e.g. logs agents -f")
    }
    $readOnly = @("status", "logs", "urls")
    $isRead = ($readOnly -contains $Action) -or ($Action -eq "mode" -and -not $Rest)   # "mode" with no argument only shows the mode
    if (-not $isRead) { Confirm-Prod $EnvName }
    $yes = ""; if ($EnvName -eq "prod" -and -not $isRead) { $yes = "LAB_YES=1 " }
    $vm = Get-VmInfo $EnvName
    $cmd = "cd " + $vm.Root + "/" + $Lab["MENU_REPO"] + " && " + $yes + "./" + $EnvName + "-linux/" + $EnvName + "-" + $map[$Action]
    if ($Rest) { $cmd += " " + ($Rest -join " ") }
    Invoke-Vm $EnvName $cmd
}
