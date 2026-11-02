# dev-02: run an app from source with Python on this computer (fast edit-and-reload).
#   .\dev-02-run-python.ps1 all -Mode vulnerable     opens one window per app
#   .\dev-02-run-python.ps1 mcp -Mode safe           runs one app in this window
# -Mode only matters for the MCP server (vulnerable = the attack lab, safe = hardened).
param([string]$App = "all", [ValidateSet("vulnerable", "safe")][string]$Mode = "vulnerable", [switch]$SkipInstall)
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
Require-Command python "Install Python 3.11 or newer from python.org"

$apps = Resolve-Apps $App
Initialize-GeminiKey      # puts the key in THIS window's environment; child windows inherit it

if ($apps.Count -gt 1) {
    foreach ($a in $apps) {
        Say "Opening a window for $a"
        $args2 = "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" $a -Mode $Mode"
        if ($SkipInstall) { $args2 += " -SkipInstall" }
        if ($Dry) { Write-Host "  $ powershell $args2" -ForegroundColor DarkYellow } else { Start-Process powershell -ArgumentList $args2 }
        Start-Sleep -Seconds 2    # let the MCP server come up before the apps that talk to it
    }
    Show-Addresses
    return
}

$a = $apps[0]
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
