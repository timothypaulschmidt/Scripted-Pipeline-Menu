#!/usr/bin/env bash
# qa-04: recent logs. ./qa-linux/qa-04-logs.sh assistant|mcp|agents|ollama [-f]
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_logs qa "$@"; }
main "$@"
exit
