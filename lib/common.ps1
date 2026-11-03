# Shared helpers for the Windows PowerShell scripts. Dot-source this; do not run it.
# (ASCII only and PowerShell 5.1 compatible, so it works in the Windows PowerShell that ships with Windows.)
# Every command a script runs is printed first, so you can see (and learn) each step.
# Set $env:LAB_DRYRUN = "1" to print the commands without running them.

$global:LabDir = Split-Path -Parent $PSScriptRoot
$global:Dry = ($env:LAB_DRYRUN -eq "1")

# ---- read lab.env (same file the bash scripts use) ------------------------------
function Read-LabEnv {
    $cfg = @{}
    foreach ($line in Get-Content (Join-Path $global:LabDir "lab.env")) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $i = $t.IndexOf("=")
        if ($i -lt 1) { continue }
        $k = $t.Substring(0, $i).Trim()
        $v = $t.Substring($i + 1).Trim()
        if ($v.Length -ge 2 -and (($v.StartsWith("'") -and $v.EndsWith("'")) -or ($v.StartsWith('"') -and $v.EndsWith('"')))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $cfg[$k] = $v
    }
    return $cfg
}
$global:Lab = Read-LabEnv

$global:LabVersion = "?"
$vf = Join-Path $global:LabDir "VERSION"
if (Test-Path $vf) { $global:LabVersion = (Get-Content $vf -TotalCount 1).Trim() }

# ---- verbose mode (on by default; $env:LAB_VERBOSE = "0" turns it off) -----------------
# Why "text"   : a plain-English note about what the next step is for
# Intro "text" : a short paragraph at the top of a script: what it does and why
# Explain cmd  : prints what a command and its options mean, from lib\explain.txt
function Test-Verbose { return ($env:LAB_VERBOSE -ne "0") }
function Why   { param([string]$m) if (Test-Verbose) { Write-Host ("  # " + $m) -ForegroundColor Green } }
function Intro { param([string]$m) if (Test-Verbose) { Write-Host ("  # " + $m) -ForegroundColor Green; Write-Host "" } }

$global:ExplainRules = @()
foreach ($l in (Get-Content (Join-Path $global:LabDir "lib\explain.txt"))) {
    if ($l -eq "" -or $l.StartsWith("#")) { continue }
    $i = $l.IndexOf("`t")
    if ($i -lt 1) { continue }
    $global:ExplainRules += ,@($l.Substring(0, $i), $l.Substring($i + 1))
}

function Explain {
    param([string]$Cmd)
    if (-not (Test-Verbose)) { return }
    $first = $true
    foreach ($r in $global:ExplainRules) {
        if ($Cmd -match $r[0]) {
            if ($first) { Write-Host ("  # " + $r[1]) -ForegroundColor Green; $first = $false }
            else        { Write-Host ("  # " + $r[1]) -ForegroundColor DarkGreen }
        }
    }
}

# ---- talking to you ----------------------------------------------------------------
function Say  { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   { param([string]$m) Write-Host " OK $m" -ForegroundColor Green }
function Warn { param([string]$m) Write-Host " !! $m" -ForegroundColor Yellow }
function Die  { param([string]$m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function Confirm-Yes {
    param([string]$Prompt)
    $a = Read-Host "$Prompt [y/N]"
    return ($a -match '^[Yy]')
}

function Require-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { Die "$Name is not installed (or not on PATH). $Hint" }
}

# ---- running commands ----------------------------------------------------------------
function Format-Arg { param([string]$a) if ($a -match '\s') { return '"' + $a + '"' } else { return $a } }

# Run a command: print it, run it, stop the script if it fails.  Usage: Run docker build -t x .
function Run {
    $exe = [string]$args[0]
    $rest = @()
    if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) }
    $line = $exe + " " + (($rest | ForEach-Object { Format-Arg $_ }) -join " ")
    Explain $line
    Write-Host ("  $ " + $line) -ForegroundColor DarkYellow
    if ($global:Dry) { return }
    & $exe @rest | Out-Host        # Out-Host: show it, but keep it out of any function's return value
    if ($LASTEXITCODE -ne 0) { Die "'$exe' failed with exit code $LASTEXITCODE" }
}

# Like Run, but for programs you TYPE into (ssh -t with a prompt). Run pipes output through Out-Host, and
# PowerShell shows text only when a line ends, so a prompt like "Paste the key: " would stay hidden until you
# pressed Enter. Here the program talks to your terminal directly, so prompts appear at once.
function RunInteractive {
    $exe = [string]$args[0]
    $rest = @()
    if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) }
    $line = $exe + " " + (($rest | ForEach-Object { Format-Arg $_ }) -join " ")
    Explain $line
    Write-Host ("  $ " + $line) -ForegroundColor DarkYellow
    if ($global:Dry) { return }
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { Die "'$exe' failed with exit code $LASTEXITCODE" }
}

# Like Run, but returns $true/$false instead of stopping.
function TryRun {
    $exe = [string]$args[0]
    $rest = @()
    if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) }
    $line = $exe + " " + (($rest | ForEach-Object { Format-Arg $_ }) -join " ")
    Explain $line
    Write-Host ("  $ " + $line) -ForegroundColor DarkYellow
    if ($global:Dry) { return $true }
    & $exe @rest | Out-Host
    return ($LASTEXITCODE -eq 0)
}

# Run quietly and say whether it worked (used for checks such as "does this image exist").
function Test-Quiet {
    $exe = [string]$args[0]
    $rest = @()
    if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) }
    $line = $exe + " " + (($rest | ForEach-Object { Format-Arg $_ }) -join " ")
    if (Test-Verbose) {
        Explain $line
        Write-Host ("  ? " + $line + "   (a quick check; its output is hidden)") -ForegroundColor DarkYellow
    }
    $null = & $exe @rest 2>&1
    return ($LASTEXITCODE -eq 0)
}

# ---- apps and folders ----------------------------------------------------------------
function Get-AppList { return @($global:Lab["APPS"] -split '\s+' | Where-Object { $_ -ne "" }) }

function Get-AppValue {
    param([string]$App, [string]$Field)
    return $global:Lab[($App.ToUpper() + "_" + $Field)]
}

# "all" -> every app; one name -> that app (checked).
function Resolve-Apps {
    param([string]$Want)
    $all = Get-AppList
    if (-not $Want) { Die ("Say which app: all, or one of: " + ($all -join ", ")) }
    # The leading comma keeps the result an ARRAY even for one app (PowerShell would unwrap it).
    if ($Want -eq "all") { return ,$all }
    if ($all -contains $Want) { return ,@($Want) }
    Die ("Unknown app '$Want'. Use all, or one of: " + ($all -join ", "))
}

function Get-Root { return $global:Lab["WIN_ROOT"] }
function Get-RepoPath { param([string]$App) return (Join-Path (Get-Root) (Get-AppValue $App "REPO")) }
function Get-Image { param([string]$App) return ($global:Lab["DOCKER_NS"] + "/" + (Get-AppValue $App "IMAGE")) }
function Get-RepoUrl { param([string]$Repo) return ("https://github.com/" + $global:Lab["GITHUB_USER"] + "/" + $Repo + ".git") }

function Assert-RepoExists {
    param([string]$App)
    $p = Get-RepoPath $App
    if (-not (Test-Path (Join-Path $p ".git"))) { Die "$p is not cloned yet. Run .\dev-windows\dev-01-git-pull.ps1 $App first." }
    return $p
}

# ---- the image tag in a kustomization.yaml ---------------------------------------------
function Get-ManifestTagFromText {
    param([string[]]$Lines, [string]$Image)
    $found = $false
    foreach ($l in $Lines) {
        if (-not $found) { if ($l -match ("name:\s*" + [regex]::Escape($Image) + "\s*$")) { $found = $true }; continue }
        if ($l -match 'newTag:\s*"?([^"\s]+)"?') { return $Matches[1] }
    }
    return $null
}

function Get-ManifestTag {
    param([string]$App)
    $file = Join-Path (Get-RepoPath $App) (Get-AppValue $App "TAG_FILE")
    if (-not (Test-Path $file)) { return $null }
    return (Get-ManifestTagFromText (Get-Content $file) (Get-Image $App))
}

function Set-ManifestTag {
    param([string]$App, [string]$NewTag)
    $file = Join-Path (Get-RepoPath $App) (Get-AppValue $App "TAG_FILE")
    $image = Get-Image $App
    Why "Editing ${file}: the image version lives on the 'newTag:' line under this image's name. Changing it is what tells Kubernetes (and the VM) which version to run."
    $text = [IO.File]::ReadAllText($file)
    $eol = "`n"; if ($text.Contains("`r`n")) { $eol = "`r`n" }
    $lines = $text -split "`r?`n"
    $found = $false; $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $found) { if ($lines[$i] -match ("name:\s*" + [regex]::Escape($image) + "\s*$")) { $found = $true }; continue }
        if (-not $done -and $lines[$i] -match '^(\s*newTag:\s*)') {
            $lines[$i] = $Matches[1] + $NewTag; $done = $true; break
        }
    }
    if (-not $done) { Die "Could not find newTag for $image in $file" }
    [IO.File]::WriteAllText($file, ($lines -join $eol), (New-Object Text.UTF8Encoding($false)))
}

# Next patch version: v0.2.1 -> v0.2.2
function Get-NextPatch {
    param([string]$Tag)
    if ($Tag -match '^v?(\d+)\.(\d+)\.(\d+)$') { return ("v{0}.{1}.{2}" -f $Matches[1], $Matches[2], ([int]$Matches[3] + 1)) }
    return $null
}

function Test-TagFormat { param([string]$Tag) return ($Tag -cmatch '^v\d+\.\d+\.\d+$') }

# Does this image:tag exist on Docker Hub? (asks the registry; pulls nothing)
function Test-ImageOnHub {
    param([string]$Image, [string]$Tag)
    return (Test-Quiet docker manifest inspect ($Image + ":" + $Tag))
}

# ---- the Gemini key: never in a file in plain text, never in git -------------------------
function Get-KeyFile {
    $dir = Join-Path $env:LOCALAPPDATA "Scripted-Pipeline-Menu"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    return (Join-Path $dir "gemini.key")
}

function ConvertTo-PlainText {
    param([System.Security.SecureString]$Secure)
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# Saved with Windows DPAPI: only your Windows login on this computer can read it back.
function Save-GeminiKey {
    param([System.Security.SecureString]$Secure)
    Why "Saving the key: ConvertFrom-SecureString encrypts it with Windows DPAPI (tied to your Windows login), then it is written to $(Get-KeyFile). The text in that file is useless on any other computer or account."
    ($Secure | ConvertFrom-SecureString) | Set-Content -Path (Get-KeyFile) -Encoding ASCII
}

# Order: this window's $env:GEMINI_API_KEY, then the saved key, else $null.
function Get-GeminiKey {
    if ($env:GEMINI_API_KEY) { return $env:GEMINI_API_KEY }
    $f = Get-KeyFile
    if (Test-Path $f) {
        try {
            $s = (Get-Content $f -Raw).Trim() | ConvertTo-SecureString
            return (ConvertTo-PlainText $s)
        } catch { Warn "The saved key could not be read (different Windows user?). Run .\dev-windows\dev-06-gemini-key.ps1 again."; return $null }
    }
    return $null
}

# Make sure $env:GEMINI_API_KEY is set for this window; offer to save it if we have to ask.
function Initialize-GeminiKey {
    $k = Get-GeminiKey
    if (-not $k) {
        Warn "No Gemini key saved yet. It is stored encrypted for your Windows login only."
        $s = Read-Host "Paste your Gemini API key (typing is hidden), or press Enter to skip" -AsSecureString
        $k = ConvertTo-PlainText $s
        if ($k) {
            Save-GeminiKey $s
            Ok "Saved (encrypted). Change it any time with .\dev-windows\dev-06-gemini-key.ps1"
        }
    }
    if ($k) { $env:GEMINI_API_KEY = $k } else { Warn "Continuing without a Gemini key: only the Ollama model will work." }
}

# ---- addresses: one place that prints them all -----------------------------------------------
function Show-Addresses {
    $L = $global:Lab
    Write-Host ""
    Say "Addresses"
    Write-Host "  On this computer (when the local copies are running)"
    Write-Host ("    MCP server    http://localhost:{0}/mcp" -f $L["MCP_LOCAL_PORT"])
    Write-Host ("    AI Assistant  http://localhost:{0}" -f $L["ASSISTANT_LOCAL_PORT"])
    Write-Host ("    AI Agents     http://localhost:{0}" -f $L["AGENTS_LOCAL_PORT"])
    Write-Host ("    Ollama        {0}" -f $L["DEV_OLLAMA_URL"])
    Write-Host "  QA"
    Write-Host ("    AI Assistant  {0}" -f $L["QA_ASSISTANT_URL"])
    Write-Host ("    AI Agents     {0}" -f $L["QA_AGENTS_URL"])
    Write-Host ("    MCP server    {0}   (inside the cluster only)" -f $L["CLUSTER_MCP_URL"])
    Write-Host ("    Ollama        {0}   (inside the cluster only)" -f $L["CLUSTER_OLLAMA_URL"])
    Write-Host ("    Assistant     {0}   (inside the cluster only)" -f $L["CLUSTER_ASSISTANT_URL"])
    Write-Host ("    Agents        {0}   (inside the cluster only)" -f $L["CLUSTER_AGENTS_URL"])
    Write-Host ("    SSH           {0}@{1}" -f $L["QA_USER"], $L["QA_HOST"])
    Write-Host "  Prod"
    Write-Host ("    AI Assistant  {0}" -f $L["PROD_ASSISTANT_URL"])
    Write-Host ("    AI Agents     {0}" -f $L["PROD_AGENTS_URL"])
    Write-Host ("    MCP server    {0}   (inside the cluster only)" -f $L["CLUSTER_MCP_URL"])
    Write-Host ("    Ollama        {0}   (inside the cluster only)" -f $L["CLUSTER_OLLAMA_URL"])
    Write-Host ("    Assistant     {0}   (inside the cluster only)" -f $L["CLUSTER_ASSISTANT_URL"])
    Write-Host ("    Agents        {0}   (inside the cluster only)" -f $L["CLUSTER_AGENTS_URL"])
    Write-Host ("    SSH           {0}@{1}" -f $L["PROD_USER"], $L["PROD_HOST"])
    Write-Host ""
    Write-Host ("  Inside the cluster these names work only from pods in namespace " + $L["NAMESPACE"] + ". From another namespace (for example FortiAIGate) add the namespace: http://mcp-server." + $L["NAMESPACE"] + ".svc.cluster.local:8000/mcp")
    Write-Host ""
}

# ---- talking to the VMs over ssh ------------------------------------------------------------------
function Get-VmInfo {
    param([string]$EnvName)
    $u = $EnvName.ToUpper()
    $L = $global:Lab
    $key = ""
    if ($L[$u + "_SSH_KEY"]) { $key = Join-Path $HOME $L[$u + "_SSH_KEY"] }
    return @{ Name = $EnvName; Host = $L[$u + "_HOST"]; User = $L[$u + "_USER"]; Root = $L[$u + "_ROOT"]; Key = $key }
}

# The ssh options that choose the login key: "-i <file>" when lab.env names one, otherwise nothing.
function Get-SshKeyArgs {
    param($vm)
    if (-not $vm.Key) { return ,@() }
    if (-not (Test-Path $vm.Key)) {
        if ($global:Dry) { return ,@("-i", $vm.Key) }
        Die ("This VM needs the ssh key file " + $vm.Key + " (set in lab.env). Copy it there, then run this again.")
    }
    Why ("ssh -i: log in with the key file " + $vm.Key + " (set in lab.env). Some VMs, like the AWS one, accept only that key.")
    return ,@("-i", $vm.Key)
}

# Run a command line on the VM. -t gives you a real terminal so prompts (like the key paste) work.
function Invoke-Vm {
    param([string]$EnvName, [string]$Command)
    Require-Command ssh "Turn on 'OpenSSH Client' in Windows Optional Features."
    $vm = Get-VmInfo $EnvName
    $k = Get-SshKeyArgs $vm
    RunInteractive ssh -t @k ($vm.User + "@" + $vm.Host) $Command
}

# Prod needs a typed 'prod' (the VM scripts then run with LAB_YES=1 so you are not asked twice).
function Confirm-Prod {
    param([string]$EnvName)
    if ($EnvName -ne "prod") { return }
    $a = Read-Host "This changes PRODUCTION. Type 'prod' to continue"
    if ($a -ne "prod") { Die "Cancelled." }
}

function Get-VmScriptPrefix { param([string]$EnvName) return ($EnvName + "-") }

# ---- window title: the text at the top of the PowerShell window ------------------------------
function Set-Title {
    param([string]$Text)
    try { $Host.UI.RawUI.WindowTitle = $Text } catch { }
}
# Every script gets a title from its own file name; a script or the menu can set a nicer one after.
$caller = (Get-PSCallStack)[1]
if ($caller -and $caller.ScriptName) {
    Set-Title ("Scripted Pipeline Menu: " + [IO.Path]::GetFileNameWithoutExtension($caller.ScriptName))
}
