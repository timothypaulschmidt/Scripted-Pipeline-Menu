# dev-06: save (or replace) your Gemini API key for the local scripts.
# It is encrypted with Windows DPAPI: only your Windows login on this computer can read it.
# It is never written into the repo or into any script. For QA and prod use .\qa-12-gemini-key.ps1
# and .\prod-12-gemini-key.ps1.
$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "lib\common.ps1")
$s = Read-Host "Paste the new Gemini API key (typing is hidden)" -AsSecureString
if ($s.Length -lt 20) { Die "That is too short to be a Gemini key. Nothing saved." }
if (-not $Dry) { Save-GeminiKey $s }
Ok "Saved for this Windows login. New python/docker starts use it. Already-running ones keep the old key until restarted."
