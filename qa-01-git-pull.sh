#!/usr/bin/env bash
# qa-01: get the code on this VM. ./qa-01-git-pull.sh all|assistant|mcp|agents|menu (clones the first time, pulls after).
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_pull qa "$@"; }
main "$@"
exit
