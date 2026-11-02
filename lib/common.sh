#!/usr/bin/env bash
# Shared helpers for the bash scripts (QA and prod VMs). Source this; do not run it.
# Every command a script runs is printed first, so you can see (and learn) each step.
# Set LAB_DRYRUN=1 to print the commands without running them.

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lab.env
# shellcheck disable=SC1091
source "$LAB_DIR/lab.env"

DRY="${LAB_DRYRUN:-0}"

say()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m OK %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m !! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# shellcheck disable=SC2034
LAB_VERSION="$(cat "$LAB_DIR/VERSION" 2>/dev/null || echo "?")"

# ---- verbose mode (on by default; LAB_VERBOSE=0 turns it off) ----------------------
# why "text"   : a plain-English note about what the next step is for
# intro "text" : a short paragraph at the top of a script: what it does and why
# explain "cmd": prints what a command and its options mean, from lib/explain.txt
verbose() { [ "${LAB_VERBOSE:-1}" != "0" ]; }
why()   { verbose && printf '\033[0;32m  # %s\033[0m\n' "$*"; return 0; }
intro() { verbose && printf '\033[0;32m  # %s\033[0m\n\n' "$*"; return 0; }
explain() {
  verbose || return 0
  local cmd="$1" re txt first=1
  while IFS=$'\t' read -r re txt; do
    case "$re" in ''|'#'*) continue ;; esac
    if [[ "$cmd" =~ $re ]]; then
      if [ "$first" = 1 ]; then printf '\033[1;32m  # %s\033[0m\n' "$txt"; first=0
      else printf '\033[0;32m  # %s\033[0m\n' "$txt"; fi
    fi
  done < "$LAB_DIR/lib/explain.txt"
  return 0
}

# Print a command, then run it (unless dry-run). Use for every real command.
run() {
  explain "$*"
  printf '\033[0;33m  $ %s\033[0m\n' "$*"
  [ "$DRY" = "1" ] && return 0
  "$@"
}

confirm() { local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }
require() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed (or not on PATH). $2"; }

upper() { printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'; }
# value of a variable whose NAME is in $1 (empty if unset)
val()   { local n="$1"; printf '%s' "${!n:-}"; }
# app_val assistant REPO -> value of ASSISTANT_REPO
app_val() { val "$(upper "$1")_$2"; }
# env_val qa ROOT -> value of QA_ROOT
env_val() { val "$(upper "$1")_$2"; }

# Expand "all" to every app; check each name is known. Prints one name per line.
resolve_apps() {
  local want="${1:-}" a
  [ -n "$want" ] || die "Say which app: all, or one of: $APPS"
  # shellcheck disable=SC2086
  if [ "$want" = "all" ]; then printf '%s\n' $APPS; return; fi
  for a in $APPS; do [ "$a" = "$want" ] && { printf '%s\n' "$a"; return; }; done
  die "Unknown app '$want'. Use all, or one of: $APPS"
}

# The image tag a manifest asks for: manifest_tag <kustomization.yaml> <image like ns/name>
manifest_tag() {
  awk -v img="$2" 'index($0, "name: " img) && !f {f=1; next} f && /newTag:/ {print $2; exit}' "$1"
}

# ---- VM helpers: every qa-* / prod-* script sets the environment first ----------
# vm_env qa|prod   -> sets LAB_ENV, ROOT, URL helpers
vm_env() {
  LAB_ENV="$1"
  [ "$LAB_ENV" = "qa" ] || [ "$LAB_ENV" = "prod" ] || die "environment must be qa or prod"
  ROOT="$(env_val "$LAB_ENV" ROOT)"
  [ -d "$ROOT" ] || die "Root folder $ROOT does not exist on this machine. Are you on the $LAB_ENV VM?"
}

repo_dir() { printf '%s/%s' "$ROOT" "$(app_val "$1" REPO)"; }

# Prod changes need a typed confirmation (skipped when a Windows ship script already asked).
guard_prod() {
  [ "$LAB_ENV" = "prod" ] || return 0
  [ "${LAB_YES:-0}" = "1" ] && return 0
  local a; read -r -p "This changes PRODUCTION. Type 'prod' to continue: " a
  [ "$a" = "prod" ] || die "Cancelled."
}
