#!/usr/bin/env bash
# qa-03: what is running: pods, image versions, secrets (names only), code versions, addresses.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_status qa "$@"; }
main "$@"
exit
