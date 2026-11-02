#!/usr/bin/env bash
# Scripted Pipeline Menu for prod: a numbered text menu over the prod-NN scripts.
# Run it on the prod VM:  ./pipeline-menu-prod.sh
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/menu.sh"
vm_menu prod
exit
