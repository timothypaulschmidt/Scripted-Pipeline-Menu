#!/usr/bin/env bash
# prod-09: print every address.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_urls prod "$@"; }
main "$@"
exit
