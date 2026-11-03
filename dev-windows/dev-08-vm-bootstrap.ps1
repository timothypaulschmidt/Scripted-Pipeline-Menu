# dev-08: prepare a QA or prod VM for the first time, from Windows.
#   .\dev-windows\dev-08-vm-bootstrap.ps1 qa      (or prod)
# 1. makes you an ssh key if you have none, and installs it on the VM (uses the key file from lab.env, or asks your VM password once)
# 2. clones Scripted-Pipeline-Menu on the VM
# 3. runs the VM's qa-00 / prod-00 first-time setup (clones the apps, creates the admin token)
param([Parameter(Mandatory = $true)][ValidateSet("qa", "prod")][string]$EnvName)
$ErrorActionPreference = "Continue"
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
Require-Command ssh "Turn on 'OpenSSH Client' in Windows Optional Features."
Intro "PREPARING A VM: (1) an ssh key lets you log in without a password, (2) the VM gets its own clone of this scripts repo, (3) its first-time setup script clones the app repos and creates the MCP admin token. After this, the ship scripts can do everything over ssh."
$vm = Get-VmInfo $EnvName
$target = $vm.User + "@" + $vm.Host

$key = Join-Path $HOME ".ssh\id_ed25519"
if (-not (Test-Path $key)) {
    Say "Making an ssh key (press Enter for no passphrase, or type one)"
    Run ssh-keygen -t ed25519 -f $key
}
$k = Get-SshKeyArgs $vm
if ($vm.Key) { Say ("Installing your key on $target (logging in with " + $vm.Key + "; no password needed)") }
else { Say "Installing your key on $target (you type the VM password this once)" }
Why "Only the PUBLIC half of your key is sent, and it is added to ~/.ssh/authorized_keys only if it is not already there, so running this again is harmless."
if ($Dry) { Write-Host "  $ (dry run) would append $key.pub to ~/.ssh/authorized_keys on $target" -ForegroundColor DarkYellow }
else {
    $install = 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && tr -d ''\r'' > ~/.ssh/.new_key && { grep -qxFf ~/.ssh/.new_key ~/.ssh/authorized_keys 2>/dev/null || cat ~/.ssh/.new_key >> ~/.ssh/authorized_keys; } && rm -f ~/.ssh/.new_key && chmod 600 ~/.ssh/authorized_keys'
    Get-Content ($key + ".pub") | ssh @k -o StrictHostKeyChecking=accept-new $target $install
    if ($LASTEXITCODE -ne 0) { Die "Could not install the key." }
}

Confirm-Prod $EnvName
$tools = $vm.Root + "/" + $Lab["MENU_REPO"]
$clone = "[ -d " + $tools + "/.git ] || git clone " + (Get-RepoUrl $Lab["MENU_REPO"]) + " " + $tools
$yes = ""; if ($EnvName -eq "prod") { $yes = "LAB_YES=1 " }
Say "Cloning Scripted-Pipeline-Menu on the VM and running its first-time setup"
Invoke-Vm $EnvName ($clone + " && cd " + $tools + " && chmod +x " + $EnvName + "-linux/*.sh *.sh && " + $yes + "./" + $EnvName + "-linux/" + $EnvName + "-00-first-time-setup.sh")
Show-Addresses
