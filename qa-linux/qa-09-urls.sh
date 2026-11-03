#!/usr/bin/env bash
# qa-09: print every address.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_urls qa "$@"; }
main "$@"
exit
