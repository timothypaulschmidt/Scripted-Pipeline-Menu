#!/usr/bin/env bash
# The logic behind the qa-* and prod-* scripts. Source lib/common.sh first.
# Each function takes the environment (qa or prod) as its first argument.

secret_exists() { kubectl -n "$NAMESPACE" get secret "$1" >/dev/null 2>&1; }

ensure_namespace() {
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    say "Creating namespace $NAMESPACE (first deploy on this cluster)"
    run kubectl create namespace "$NAMESPACE"
  fi
}

# ---- 01: get the code ---------------------------------------------------------
vm_pull() {
  vm_env "$1"; shift
  local target="${1:-}" list="" t name path
  [ -n "$target" ] || die "Usage: ${LAB_ENV}-01-git-pull.sh <all|assistant|mcp|agents|menu>"
  require git "Install it with: sudo apt install git"
  if [ "$target" = "menu" ]; then
    list="menu"
  elif [ "$target" = "all" ]; then
    list="$(resolve_apps all | tr '\n' ' ') menu"
  else
    list="$(resolve_apps "$target" | tr '\n' ' ')"
  fi
  for t in $list; do
    if [ "$t" = "menu" ]; then name="$MENU_REPO"; else name="$(app_val "$t" REPO)"; fi
    path="$ROOT/$name"
    if [ -d "$path/.git" ]; then
      say "Updating $name (git pull)"
      run git -C "$path" fetch origin
      run git -C "$path" checkout main
      run git -C "$path" pull --ff-only origin main
      run git -C "$path" log --oneline -3
    else
      say "First time here: cloning $name"
      run git clone "https://github.com/$GITHUB_USER/$name.git" "$path"
    fi
  done
}

# ---- 02: deploy ---------------------------------------------------------------
preflight_secrets() {
  case "$1" in
    assistant)
      secret_exists gemini-api-key || die "Secret gemini-api-key is missing; the pod would not start. Run ./${LAB_ENV}-06-secrets.sh gemini first." ;;
    mcp|agents)
      secret_exists mcp-admin || warn "Secret mcp-admin is missing: the reset/insert buttons will be off. Run ./${LAB_ENV}-06-secrets.sh admin" ;;
  esac
}

show_address() {
  local envup; envup="$(upper "$LAB_ENV")"
  case "$1" in
    assistant) say "Open: $(val "${envup}_ASSISTANT_URL")" ;;
    agents)    say "Open: $(val "${envup}_AGENTS_URL")" ;;
    mcp)       say "MCP server is internal only (inside the cluster: $CLUSTER_MCP_URL). Nothing to open." ;;
  esac
}

vm_deploy() {
  vm_env "$1"; shift
  require kubectl "k3s should have installed it."
  local apps a dir tagfile image tag dep envup
  apps="$(resolve_apps "${1:-}")"
  envup="$(upper "$LAB_ENV")"
  guard_prod
  for a in $apps; do
    dir="$(repo_dir "$a")/$(app_val "$a" "${envup}_DEPLOY")"
    tagfile="$(repo_dir "$a")/$(app_val "$a" TAG_FILE)"
    [ -d "$dir" ] || die "$dir not found. Run ./${LAB_ENV}-01-git-pull.sh $a first."
    image="$DOCKER_NS/$(app_val "$a" IMAGE)"
    tag="$(manifest_tag "$tagfile" "$image")"
    [ -n "$tag" ] || die "Could not read the image tag for $image from $tagfile"
    dep="$(app_val "$a" DEPLOYMENT)"
    say "Deploying $a: $image:$tag to $LAB_ENV"
    ensure_namespace
    preflight_secrets "$a"
    run kubectl apply -k "$dir"
    if ! run kubectl -n "$NAMESPACE" rollout status "deployment/$dep" --timeout=300s; then
      warn "$dep did not become ready in time. Is the image $image:$tag on Docker Hub? Details:"
      run kubectl -n "$NAMESPACE" get pods
      run kubectl -n "$NAMESPACE" describe deployment "$dep"
      die "Deploy of $a failed."
    fi
    ok "$a is running $image:$tag"
    show_address "$a"
  done
  vm_urls "$LAB_ENV"
}

# ---- 03: status ---------------------------------------------------------------
vm_status() {
  vm_env "$1"
  require kubectl "k3s should have installed it."
  local envup a path
  envup="$(upper "$LAB_ENV")"
  say "Pods"
  run kubectl -n "$NAMESPACE" get pods -o wide
  say "What is running (image per deployment)"
  run kubectl -n "$NAMESPACE" get deploy -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
  say "Services"
  run kubectl -n "$NAMESPACE" get svc
  say "Secrets (names only)"
  run kubectl -n "$NAMESPACE" get secrets
  say "Code on this machine (latest commit per repo)"
  # shellcheck disable=SC2153,SC2086
  for a in $APPS; do
    path="$(repo_dir "$a")"
    if [ -d "$path/.git" ]; then printf '  %-14s %s\n' "$(app_val "$a" REPO)" "$(git -C "$path" log --oneline -1)"; else printf '  %-14s not cloned\n' "$(app_val "$a" REPO)"; fi
  done
  vm_urls "$LAB_ENV"
}

# ---- 09: every address, so nothing has to be remembered --------------------------
vm_urls() {
  vm_env "$1"
  local envup; envup="$(upper "$LAB_ENV")"
  say "Addresses ($LAB_ENV)"
  printf '  AI Assistant  %s\n  AI Agents     %s\n  MCP server    internal only (%s)\n' \
    "$(val "${envup}_ASSISTANT_URL")" "$(val "${envup}_AGENTS_URL")" "$CLUSTER_MCP_URL"
  printf '  SSH           %s@%s\n' "$(env_val "$LAB_ENV" USER)" "$(env_val "$LAB_ENV" HOST)"
}

# ---- 04: logs -----------------------------------------------------------------
vm_logs() {
  vm_env "$1"; shift
  require kubectl "k3s should have installed it."
  local app="${1:-}" follow="${2:-}" dep
  case "$app" in
    assistant) dep=ai-assistant ;;
    mcp)       dep=mcp-server ;;
    agents)    dep=ai-agents ;;
    ollama)    dep=ollama ;;
    *) die "Usage: ${LAB_ENV}-04-logs.sh <assistant|mcp|agents|ollama> [-f]   (-f keeps following; Ctrl+C to stop)" ;;
  esac
  if [ "$follow" = "-f" ]; then
    run kubectl -n "$NAMESPACE" logs "deploy/$dep" --tail=50 -f
  else
    run kubectl -n "$NAMESPACE" logs "deploy/$dep" --tail=80
  fi
}

# ---- 05: reset the lab data ---------------------------------------------------
vm_reset_mcp() {
  vm_env "$1"
  require kubectl "k3s should have installed it."
  guard_prod
  say "Restarting the MCP server: every table goes back to the seed data"
  run kubectl -n "$NAMESPACE" rollout restart deployment/mcp-server
  run kubectl -n "$NAMESPACE" rollout status deployment/mcp-server --timeout=180s
  ok "Data reset. (The ticket-queue reset buttons on the agents page do a lighter reset without a restart.)"
}

# ---- 06: secrets --------------------------------------------------------------
# Write a secret from a value held in a temp file (mode 600), so the value never shows
# up in a process list or in this terminal. Usage: apply_secret <name> <key> <value>
apply_secret() {
  local name="$1" key="$2" value="$3" tmp
  if [ "$DRY" = "1" ]; then
    printf '  $ (dry run) would create or replace secret %s (key %s, value hidden)\n' "$name" "$key"
    return 0
  fi
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  printf '%s' "$value" > "$tmp"
  if kubectl -n "$NAMESPACE" create secret generic "$name" --from-file="$key=$tmp" --dry-run=client -o yaml \
      | kubectl apply -f - ; then
    rm -f "$tmp"
  else
    rm -f "$tmp"
    die "Could not write secret $name"
  fi
}

restart_deployments() {
  local d
  for d in "$@"; do
    if kubectl -n "$NAMESPACE" get deployment "$d" >/dev/null 2>&1; then
      say "Restarting $d so it picks up the new secret"
      run kubectl -n "$NAMESPACE" rollout restart "deployment/$d"
    else
      warn "$d is not deployed here; skipping its restart"
    fi
  done
}

read_secret_value() { # prompt -> value on stdout (typed value is not echoed)
  local v
  read -rsp "$1: " v; printf '\n' >&2
  [ -n "$v" ] || die "Nothing entered."
  printf '%s' "$v"
}

vm_secrets() {
  vm_env "$1"; shift
  require kubectl "k3s should have installed it."
  local choice="${1:-}" v name key list
  if [ -z "$choice" ]; then
    cat <<EOF
Secrets on $LAB_ENV (values are never shown):
  1) gemini  - Gemini API key  (used by ai-assistant and ai-agents)
  2) admin   - MCP admin token (used by mcp-server and ai-agents); makes a new random one
  3) custom  - any other secret (you give the name, key and value)
  4) show    - list secrets and their key names
EOF
    read -r -p "Choose 1-4 (or q to quit): " choice
  fi
  case "$choice" in
    1|gemini)
      guard_prod; ensure_namespace
      v="$(read_secret_value "Paste the Gemini API key")"
      [ "${#v}" -ge 20 ] || warn "That key looks short (${#v} characters). Continuing anyway."
      apply_secret gemini-api-key GEMINI_API_KEY "$v"
      restart_deployments ai-assistant ai-agents
      ok "Gemini key updated." ;;
    2|admin)
      guard_prod; ensure_namespace
      require openssl "sudo apt install openssl"
      v="$(openssl rand -hex 24)"
      apply_secret mcp-admin token "$v"
      restart_deployments mcp-server ai-agents
      ok "New MCP admin token written (not shown; the pods read it themselves)." ;;
    3|custom)
      guard_prod; ensure_namespace
      read -r -p "Secret name (e.g. my-api-key): " name
      read -r -p "Key name inside it (e.g. API_KEY): " key
      [ -n "$name" ] && [ -n "$key" ] || die "Name and key are required."
      v="$(read_secret_value "Value for $name/$key")"
      apply_secret "$name" "$key" "$v"
      read -r -p "Deployments to restart (space separated, blank for none): " list
      # shellcheck disable=SC2086
      [ -z "$list" ] || restart_deployments $list
      ok "Secret $name updated." ;;
    4|show)
      run kubectl -n "$NAMESPACE" get secrets
      for name in $(kubectl -n "$NAMESPACE" get secrets -o name 2>/dev/null | sed 's#secret/##'); do
        printf '  %-28s keys: ' "$name"
        # shellcheck disable=SC2016
        kubectl -n "$NAMESPACE" get secret "$name" -o go-template='{{range $k,$v := .data}}{{$k}} {{end}}{{"\n"}}'
      done ;;
    q|"") say "No changes." ;;
    *) die "Unknown choice '$choice'" ;;
  esac
}

# ---- 00: first-time setup of a VM ---------------------------------------------
vm_first_time() {
  vm_env "$1"
  require git "sudo apt install git"
  require kubectl "k3s should have installed it."
  say "Checking that kubectl can reach the cluster"
  run kubectl get nodes
  say "Cloning the app repos next to Scripted-Pipeline-Menu"
  vm_pull "$LAB_ENV" all
  ensure_namespace
  if secret_exists mcp-admin; then
    ok "mcp-admin secret already exists"
  else
    require openssl "sudo apt install openssl"
    say "Creating the MCP admin token (random, never shown)"
    apply_secret mcp-admin token "$(openssl rand -hex 24)"
  fi
  say "Next:"
  printf '  1) ./%s-06-secrets.sh gemini     (paste your Gemini key)\n  2) ./%s-02-deploy.sh all          (deploy everything)\n' "$LAB_ENV" "$LAB_ENV"
}
