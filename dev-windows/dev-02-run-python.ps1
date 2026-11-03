# dev-02: run an app from source with Python on this computer (fast edit-and-reload).
#   .\dev-windows\dev-02-run-python.ps1 all -Mode vulnerable     opens one tab per app (or one window per app without Windows Terminal)
#   .\dev-windows\dev-02-run-python.ps1 mcp -Mode safe           runs one app in this window
# -Mode only matters for the MCP server (vulnerable = the attack lab, safe = hardened).
param([string]$App = "all", [ValidateSet("vulnerable", "safe")][string]$Mode = "vulnerable", [switch]$SkipInstall)
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
Require-Command python "Install Python 3.11 or newer from python.org"

Intro "RUN WITH PYTHON: this runs the app straight from the source code on this computer, with auto-reload when you edit a file. We install the packages, set the settings the app reads (where Ollama, the MCP server and the admin token are), then start the web server. The MCP server must be up before the apps that call it."
$apps = Resolve-Apps $App
Initialize-GeminiKey      # puts the key in THIS window's environment; child windows inherit it

if ($apps.Count -gt 1) {
    # Windows Terminal (wt.exe) can open each app as a TAB. Without it we open separate windows.
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    $me = (Get-Process -Id $PID).Path
    # Inside Windows Terminal already: add tabs to THIS window (-w 0). Otherwise open one new
    # Terminal window with a fixed name, so all the tabs land together.
    $target = "pipeline"; if ($env:WT_SESSION) { $target = "0" }
    if ($wt) { Why "Windows Terminal found: each app opens as a tab in one window." }
    else     { Why "Windows Terminal (wt.exe) not found, so each app gets its own window. Install 'Windows Terminal' from the Microsoft Store to get tabs." }
    # Start the MCP server first, then the apps that call it.
    $ordered = @("mcp", "assistant", "agents") | Where-Object { $apps -contains $_ }
    foreach ($a in $ordered) {
        $title = "Python: " + (Get-AppValue $a "REPO")
        Say "Opening $title"
        $inner = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, $a, "-Mode", $Mode)
        if ($SkipInstall) { $inner += "-SkipInstall" }
        if ($wt) {
            $wtArgs = @("-w", $target, "new-tab", "--title", $title, "--suppressApplicationTitle", $me) + $inner
            Write-Host ("  $ wt " + (($wtArgs | ForEach-Object { Format-Arg $_ }) -join " ")) -ForegroundColor DarkYellow
            if (-not $Dry) { Start-Process wt.exe -ArgumentList ($wtArgs | ForEach-Object { Format-Arg $_ }) }
        } else {
            Write-Host ("  $ powershell " + (($inner | ForEach-Object { Format-Arg $_ }) -join " ")) -ForegroundColor DarkYellow
            if (-not $Dry) { Start-Process $me -ArgumentList ($inner | ForEach-Object { Format-Arg $_ }) }
        }
        Start-Sleep -Seconds 2    # let the MCP server come up before the apps that talk to it
    }
    Show-Addresses
    return
}

$a = $apps[0]
Set-Title ("Python: " + (Get-AppValue $a "REPO"))     # the text at the top of this window
$path = Assert-RepoExists $a
Push-Location $path
try {
    if (-not $SkipInstall) {
        Say "Installing $a's Python packages (quick if already installed)"
        if (Test-Path "requirements-dev.txt") { Run python -m pip install -q -r requirements-dev.txt; Run python -m pip install -q -e . }
        else { Run python -m pip install -q -e ".[dev]" }
    }
    $L = $Lab
    $env:OLLAMA_BASE_URL = $L["DEV_OLLAMA_URL"]
    $env:MCP_SERVER_URL = ("http://localhost:{0}/mcp" -f $L["MCP_LOCAL_PORT"])
    $env:ADMIN_TOKEN = $L["DEV_ADMIN_TOKEN"]
    Say "Starting $a  (stop it with Ctrl+C)"
    switch ($a) {
        "mcp"       { Run python -m mcp_server --mode $Mode --transport streamable-http --port $L["MCP_LOCAL_PORT"] }
        "assistant" { Run python -m uvicorn ai_assistant.web.main:app --reload --port $L["ASSISTANT_LOCAL_PORT"] }
        "agents"    { Run python -m uvicorn ai_agents.web.main:app --reload --port $L["AGENTS_LOCAL_PORT"] }
    }
} finally { Pop-Location }
