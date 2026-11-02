#!/usr/bin/env bash
# Scripted Pipeline Menu for qa: a numbered text menu over the qa-NN scripts.
# Run it on the qa VM:  ./pipeline-menu-qa.sh
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"
source "$LAB_DIR/lib/menu.sh"
vm_menu qa
exit
