#!/usr/bin/env bash
# qa-00: run ONCE on a new qa VM (after cloning Scripted-Pipeline-Menu). Clones the app repos, creates the admin token.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_first_time qa "$@"; }
main "$@"
exit
