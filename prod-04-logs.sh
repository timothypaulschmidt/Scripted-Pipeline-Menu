#!/usr/bin/env bash
# prod-04: recent logs. ./prod-04-logs.sh assistant|mcp|agents|ollama [-f]
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_logs prod "$@"; }
main "$@"
exit
