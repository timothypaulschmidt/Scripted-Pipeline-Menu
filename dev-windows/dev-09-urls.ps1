# dev-09: print every address and port, so you never have to remember them.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\common.ps1")
Show-Addresses
