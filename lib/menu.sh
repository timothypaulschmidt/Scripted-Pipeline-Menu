#!/usr/bin/env bash
# The text menu behind pipeline-menu-qa.sh and pipeline-menu-prod.sh. Source lib/common.sh first.
# Each choice runs one of the numbered scripts in this same terminal, shows its output, then
# waits for you to press Enter, so you can read any error before the menu redraws.

ask_choice() { # prompt default option... -> chosen value on stdout
  local prompt="$1" default="$2" ans o; shift 2
  while true; do
    read -r -p "$prompt ($(printf '%s/' "$@" | sed 's#/$##')) [$default]: " ans >&2
    ans="${ans:-$default}"
    for o in "$@"; do [ "$o" = "$ans" ] && { printf '%s' "$ans"; return; }; done
    printf 'Please type one of the options shown.\n' >&2
  done
}

menu_run() { # script args... : run in a subshell so a failure cannot close the menu
  local script="$1"; shift
  printf '\n'
  printf '\033[0;33m  $ ./%s-linux/%s\033[0m\n' "$LAB_ENV" "$script $*"
  ( cd "$LAB_DIR" && "./$LAB_ENV-linux/$script" "$@" ) || warn "That script stopped with an error (shown above)."
  printf '\n'
  read -r -p "Press Enter to return to the menu... " _
}

vm_menu() {
  local e="$1" c a f title
  vm_env "$e"
  title="Scripted Pipeline Menu v$LAB_VERSION: $(upper "$e")"
  while true; do
    set_title "$title"
    clear 2>/dev/null || true
    printf '\033[1;36m=== Scripted Pipeline Menu v%s: %s (%s) ===\033[0m\n' "$LAB_VERSION" "$(upper "$e")" "$(env_val "$e" HOST)"
    if verbose; then printf '  Explanations: ON (press v to turn off)\n'; else printf '  Explanations: OFF (press v to turn on)\n'; fi
    [ "$e" = "prod" ] && printf '\033[1;31m  PRODUCTION: changes ask you to type "prod".\033[0m\n'
    printf '\033[2m   #  %-27s%s\033[0m\n' "What it does" "Script Name"
    cat <<EOF2
   1  Get the code               ($e-01)  clone / pull
   2  Deploy                     ($e-02)  apply the version in each manifest
   3  Status                     ($e-03)  pods, versions, secrets (names), addresses
   4  Logs                       ($e-04)
   5  Reset MCP data             ($e-05)
   6  Secrets / Gemini key       ($e-06)
   7  Addresses                  ($e-09)
   8  Download language models   ($e-07)  Ollama models from lab.env
   9  MCP mode                   ($e-08)  vulnerable or safe
   0  First-time setup           ($e-00)  once per VM
   v  Turn explanations on/off
   q  Quit
EOF2
    read -r -p "Choose: " c
    case "$c" in
      1) a="$(ask_choice "Which repo" all all assistant mcp agents menu)"; menu_run "$e-01-git-pull.sh" "$a" ;;
      2) a="$(ask_choice "Which app" all all assistant mcp agents)"; menu_run "$e-02-deploy.sh" "$a" ;;
      3) menu_run "$e-03-status.sh" ;;
      4) a="$(ask_choice "Which app" agents assistant mcp agents ollama)"
         f="$(ask_choice "Keep following (Ctrl+C to stop)" no no yes)"
         if [ "$f" = "yes" ]; then menu_run "$e-04-logs.sh" "$a" -f; else menu_run "$e-04-logs.sh" "$a"; fi ;;
      5) menu_run "$e-05-reset-mcp-data.sh" ;;
      6) menu_run "$e-06-secrets.sh" ;;
      7) menu_run "$e-09-urls.sh" ;;
      8) menu_run "$e-07-pull-models.sh" ;;
      9) a="$(ask_choice "MCP mode" show show vulnerable safe)"
         if [ "$a" = "show" ]; then menu_run "$e-08-mcp-mode.sh"; else menu_run "$e-08-mcp-mode.sh" "$a"; fi ;;
      0) menu_run "$e-00-first-time-setup.sh" ;;
      v|V) if verbose; then export LAB_VERBOSE=0; else export LAB_VERBOSE=1; fi ;;
      q|Q) return 0 ;;
      *) warn "Not a choice."; sleep 1 ;;
    esac
  done
}
