# dev-04: run the apps as Docker containers on this computer (what k3s runs, but local).
#   .\dev-04-docker-run.ps1 all -Mode vulnerable
#   .\dev-04-docker-run.ps1 agents
# Order matters when starting several: the MCP server first. 'all' handles that.
# Containers run in the background; stop them with .\dev-07-docker-stop.ps1
param([string]$App = "all", [ValidateSet("vulnerable", "safe")][string]$Mode = "vulnerable")
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
Require-Command docker "Install Docker Desktop and start it"
if (-not (Test-Quiet docker info)) { Die "Docker is not running. Start Docker Desktop first." }
$L = $Lab
Initialize-GeminiKey

$net = $L["DOCKER_NETWORK"]
if (-not (Test-Quiet docker network inspect $net)) { Say "Creating Docker network $net"; Run docker network create $net }

# The order to start in: mcp, then the apps that talk to it.
$order = @("mcp", "assistant", "agents") | Where-Object { (Resolve-Apps $App) -contains $_ }
foreach ($a in $order) {
    $image = Get-Image $a
    $tag = Get-ManifestTag $a
    if (-not $tag) { Die "Cannot tell which version of $a to run. Run .\dev-01-git-pull.ps1 $a or .\dev-03-docker-pull.ps1 $a first." }
    $name = Get-AppValue $a "CONTAINER"
    $ref = $image + ":" + $tag
    if (-not (Test-Quiet docker image inspect $ref)) { Say "$ref is not on this computer yet"; Run docker pull $ref }
    Say "Starting $a ($ref)"
    $null = TryRun docker rm -f $name      # replace an older copy if one is running
    $mcpInside = "http://mcp-server:{0}/mcp" -f $L["MCP_CONTAINER_PORT"]
    $ports = ("{0}:{1}" -f (Get-AppValue $a "LOCAL_PORT"), (Get-AppValue $a "CONTAINER_PORT"))
    switch ($a) {
        "mcp"       { Run docker run -d --rm --name $name --network $net -p $ports -e ("MCP_MODE=" + $Mode) -e ("ADMIN_TOKEN=" + $L["DEV_ADMIN_TOKEN"]) $ref }
        "assistant" { Run docker run -d --rm --name $name --network $net -p $ports -e GEMINI_API_KEY -e ("OLLAMA_BASE_URL=" + $L["DEV_OLLAMA_URL_DOCKER"]) -e ("MCP_SERVER_URL=" + $mcpInside) $ref }
        "agents"    { Run docker run -d --rm --name $name --network $net -p $ports -e GEMINI_API_KEY -e ("OLLAMA_BASE_URL=" + $L["DEV_OLLAMA_URL_DOCKER"]) -e ("MCP_SERVER_URL=" + $mcpInside) -e ("ADMIN_TOKEN=" + $L["DEV_ADMIN_TOKEN"]) $ref }
    }
}
Say "Running containers"
Run docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
Show-Addresses
