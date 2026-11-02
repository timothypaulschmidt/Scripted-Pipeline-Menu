#!/usr/bin/env bash
# prod-02: deploy the version in each repo's manifest. ./prod-02-deploy.sh all|assistant|mcp|agents
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_deploy prod "$@"; }
main "$@"
exit
