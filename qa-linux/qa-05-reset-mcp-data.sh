#!/usr/bin/env bash
# qa-05: put the MCP server's data back to the seed data (restarts the MCP pod).
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_reset_mcp qa "$@"; }
main "$@"
exit
