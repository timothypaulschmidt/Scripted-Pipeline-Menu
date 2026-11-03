#!/usr/bin/env bash
# prod-10: show or change where an app's traffic goes (direct, or through FortiAIGate).
#   ./prod-linux/prod-10-route.sh                         show both apps
#   ./prod-linux/prod-10-route.sh assistant model         the Assistant's model through FortiAIGate
#   ./prod-linux/prod-10-route.sh agents model+mcp        the Agents' model and MCP through FortiAIGate
#   ./prod-linux/prod-10-route.sh agents direct           back to direct
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_route prod "$@"; }
main "$@"
exit
