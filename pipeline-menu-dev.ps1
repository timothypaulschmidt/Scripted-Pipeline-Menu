# Scripted Pipeline Menu for Windows: a numbered text menu over the dev-, qa- and prod- scripts.
#   .\pipeline-menu-dev.ps1
# Each choice runs the script in a child PowerShell in THIS window and shows its output, then waits
# for Enter, so you can read any error before the menu redraws. A script that fails cannot close the menu.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")

$menuTitle = "Scripted Pipeline Menu v" + $global:LabVersion + ": Windows"
Set-Title $menuTitle
$ps = (Get-Process -Id $PID).Path     # the same PowerShell that is running this menu

function Ask-Choice {
    param([string]$Prompt, [string]$Default, [string[]]$Options)
    while ($true) {
        $a = Read-Host ("{0} ({1}) [{2}]" -f $Prompt, ($Options -join "/"), $Default)
        if (-not $a) { $a = $Default }
        if ($Options -contains $a) { return $a }
        Write-Host "Please type one of the options shown." -ForegroundColor Yellow
    }
}

function Invoke-MenuScript {
    param([string]$Script, [string[]]$ScriptArgs = @())
    Write-Host ""
    Write-Host ("  $ .\" + $Script + " " + ($ScriptArgs -join " ")) -ForegroundColor DarkYellow
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ScriptArgs
    if ($LASTEXITCODE -ne 0) { Warn "That script stopped with an error (shown above)." }
    Write-Host ""
    [void](Read-Host "Press Enter to return to the menu")
    Set-Title $menuTitle
}

$one = @("assistant", "mcp", "agents")
$all = @("all") + $one

while ($true) {
    Clear-Host
    Write-Host ("=== Scripted Pipeline Menu v" + $global:LabVersion + ": Windows ===") -ForegroundColor Cyan
    if (Test-Verbose) { Write-Host "  Explanations: ON  (press v to turn off)" -ForegroundColor Green } else { Write-Host "  Explanations: OFF (press v to turn on)" -ForegroundColor DarkGray }
    Write-Host "  THIS COMPUTER"
    Write-Host "   1  Get the code (clone / pull)      dev-01"
    Write-Host "   2  Run with Python                  dev-02"
    Write-Host "   3  Download Docker images           dev-03"
    Write-Host "   4  Run Docker containers            dev-04"
    Write-Host "   5  Build + push a new version       dev-05"
    Write-Host "   6  Save / change my Gemini key      dev-06"
    Write-Host "   7  Stop Docker containers           dev-07"
    Write-Host "  QA   (ssh to $($Lab['QA_HOST']))"
    Write-Host "  11  Ship to QA                       qa-10"
    Write-Host "  12  QA status                        qa-11"
    Write-Host "  13  QA logs                          qa-11"
    Write-Host "  14  QA reset MCP data                qa-11"
    Write-Host "  15  QA change Gemini key             qa-12"
    Write-Host "  PROD (ssh to $($Lab['PROD_HOST']))" -ForegroundColor Red
    Write-Host "  21  Ship to PROD                     prod-10"
    Write-Host "  22  PROD status                      prod-11"
    Write-Host "  23  PROD logs                        prod-11"
    Write-Host "  24  PROD reset MCP data              prod-11"
    Write-Host "  25  PROD change Gemini key           prod-12"
    Write-Host "  SETUP / INFO"
    Write-Host "  30  First-time setup of this computer   dev-00"
    Write-Host "  31  First-time setup of a VM (ssh key, clone, setup)   dev-08"
    Write-Host "  32  Show every address               dev-09"
    Write-Host "   v  Turn explanations on/off"
    Write-Host "   q  Quit"
    $c = Read-Host "Choose"
    switch ($c) {
        "1"  { $a = Ask-Choice "Which repo" "all" ($all + "menu"); Invoke-MenuScript "dev-01-git-pull.ps1" @($a) }
        "2"  { $a = Ask-Choice "Which app" "all" $all; $m = Ask-Choice "MCP mode" "vulnerable" @("vulnerable", "safe"); Invoke-MenuScript "dev-02-run-python.ps1" @($a, "-Mode", $m) }
        "3"  { $a = Ask-Choice "Which app" "all" $all; Invoke-MenuScript "dev-03-docker-pull.ps1" @($a) }
        "4"  { $a = Ask-Choice "Which app" "all" $all; $m = Ask-Choice "MCP mode" "vulnerable" @("vulnerable", "safe"); Invoke-MenuScript "dev-04-docker-run.ps1" @($a, "-Mode", $m) }
        "5"  { $a = Ask-Choice "Which app" "agents" $one; Invoke-MenuScript "dev-05-docker-build-push.ps1" @($a) }
        "6"  { Invoke-MenuScript "dev-06-gemini-key.ps1" }
        "7"  { $a = Ask-Choice "Which app" "all" $all; Invoke-MenuScript "dev-07-docker-stop.ps1" @($a) }
        { $_ -in "11", "21" } {
            $e = if ($c -eq "11") { "qa" } else { "prod" }
            $a = Ask-Choice "Which app" "all" $all; Invoke-MenuScript ($e + "-10-ship.ps1") @($a)
        }
        { $_ -in "12", "22" } { $e = if ($c -eq "12") { "qa" } else { "prod" }; Invoke-MenuScript ($e + "-11-remote.ps1") @("status") }
        { $_ -in "13", "23" } {
            $e = if ($c -eq "13") { "qa" } else { "prod" }
            $a = Ask-Choice "Which app" "agents" @("assistant", "mcp", "agents", "ollama")
            $f = Ask-Choice "Keep following (Ctrl+C to stop)" "no" @("no", "yes")
            $x = @("logs", $a); if ($f -eq "yes") { $x += "-f" }
            Invoke-MenuScript ($e + "-11-remote.ps1") $x
        }
        { $_ -in "14", "24" } { $e = if ($c -eq "14") { "qa" } else { "prod" }; Invoke-MenuScript ($e + "-11-remote.ps1") @("reset") }
        { $_ -in "15", "25" } { $e = if ($c -eq "15") { "qa" } else { "prod" }; Invoke-MenuScript ($e + "-12-gemini-key.ps1") }
        "30" { Invoke-MenuScript "dev-00-first-time-setup.ps1" }
        "31" { $e = Ask-Choice "Which VM" "qa" @("qa", "prod"); Invoke-MenuScript "dev-08-vm-bootstrap.ps1" @($e) }
        "32" { Invoke-MenuScript "dev-09-urls.ps1" }
        { $_ -in "v", "V" } { if (Test-Verbose) { $env:LAB_VERBOSE = "0" } else { $env:LAB_VERBOSE = "1" } }
        { $_ -in "q", "Q" } { return }
        default { Warn "Not a choice."; Start-Sleep -Seconds 1 }
    }
}
