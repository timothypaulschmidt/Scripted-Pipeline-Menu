#!/usr/bin/env bash
# prod-01: get the code on this VM. ./prod-linux/prod-01-git-pull.sh all|assistant|mcp|agents|menu (clones the first time, pulls after).
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_pull prod "$@"; }
main "$@"
exit
