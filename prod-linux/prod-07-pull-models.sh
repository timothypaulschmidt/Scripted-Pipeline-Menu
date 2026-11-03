#!/usr/bin/env bash
# prod-07: download the language models the Assistant's Ollama needs. ./prod-linux/prod-07-pull-models.sh [model ...]
# With no arguments it uses the OLLAMA_MODELS list in lab.env and skips models already downloaded.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"
source "$LAB_DIR/lib/vm.sh"
main() { vm_pull_models prod "$@"; }
main "$@"
exit
