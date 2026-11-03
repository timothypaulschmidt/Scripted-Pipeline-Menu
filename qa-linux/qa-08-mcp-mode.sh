#!/usr/bin/env bash
# qa-08: show or switch the MCP server mode.  ./qa-linux/qa-08-mcp-mode.sh [vulnerable|safe]
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_mcp_mode qa "$@"; }
main "$@"
exit
