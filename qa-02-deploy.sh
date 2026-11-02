#!/usr/bin/env bash
# qa-02: deploy the version in each repo's manifest. ./qa-02-deploy.sh all|assistant|mcp|agents
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_deploy qa "$@"; }
main "$@"
exit
