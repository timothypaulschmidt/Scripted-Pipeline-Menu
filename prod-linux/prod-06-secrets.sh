#!/usr/bin/env bash
# prod-06: change secrets: ./prod-linux/prod-06-secrets.sh [gemini|admin|custom|show]. Values are typed hidden, never shown.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_secrets prod "$@"; }
main "$@"
exit
