#!/usr/bin/env bash
# The logic behind the qa-* and prod-* scripts. Source lib/common.sh first.
# Each function takes the environment (qa or prod) as its first argument.

secret_exists() { kubectl -n "$NAMESPACE" get secret "$1" >/dev/null 2>&1; }

# ---- cluster access: let kubectl talk to k3s as a normal user -----------------------
# k3s writes its login file to /etc/rancher/k3s/k3s.yaml, readable only by root. Your own copy
# lives at ~/.kube/config. This uses it when it exists, and explains the one-time fix when not.
[ -r "$HOME/.kube/config" ] && export KUBECONFIG="$HOME/.kube/config"

kube_access() {
  [ -r "$HOME/.kube/config" ] && export KUBECONFIG="$HOME/.kube/config"
  if kubectl get nodes >/dev/null 2>&1; then return 0; fi
  warn "kubectl cannot reach the cluster as $(id -un)."
  warn "k3s keeps its login file in /etc/rancher/k3s/k3s.yaml where only root can read it."
  warn "One-time fix on this VM (makes your own copy of that file), then run this step again:"
  # shellcheck disable=SC2016
  printf '    mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown "$(id -un)": ~/.kube/config && chmod 600 ~/.kube/config\n' >&2
  die "No cluster access yet."
}

ensure_namespace() {
  kube_access
  why "Checking that the namespace exists first, because every app and secret lives inside it."
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    say "Creating namespace $NAMESPACE (first deploy on this cluster)"
    run kubectl create namespace "$NAMESPACE"
  fi
}

# ---- 01: get the code ---------------------------------------------------------
vm_pull() {
  vm_env "$1"; shift
  local target="${1:-}" list="" t name path
  [ -n "$target" ] || die "Usage: ./${LAB_ENV}-linux/${LAB_ENV}-01-git-pull.sh <all|assistant|mcp|agents|menu>"
  require git "Install it with: sudo apt install git"
  intro "GETTING THE CODE: this VM keeps its own clone of each repo (under $ROOT). The first time we clone from GitHub; after that we pull the newest main. Deploys then read the manifests from these clones, so nothing is copied by hand with scp."
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

# The MCP admin token is random and needs no input from you, so create it when it is missing
# (never print it). Change it later with the secrets script, option "admin".
ensure_admin_token() {
  if secret_exists mcp-admin; then
    why "Secret mcp-admin already exists, so it is left alone. (Rotate it with ./${LAB_ENV}-linux/${LAB_ENV}-06-secrets.sh admin)"
    return 0
  fi
  require openssl "sudo apt install openssl"
  say "The MCP admin token does not exist yet: creating a random one"
  why "The MCP server and the Agents page share this token. The reset and insert buttons only work when it exists."
  apply_secret mcp-admin token "$(openssl rand -hex 24)"
}

# The QA/prod Ingress sends http:// visitors to https:// through a Traefik Middleware called
# default/redirect-https. That object belongs to the cluster layer (k3s / Traefik / FortiAIGate
# setup), not to this pipeline, so we only CHECK for it and warn. The app still works on its
# NodePort without it; only the https:// address misbehaves.
check_traefik_middleware() {
  why "The Assistant's Ingress (QA and prod) points at a Traefik Middleware named default/redirect-https, which sends HTTP visitors to HTTPS. It belongs to the cluster setup, so this script only checks that it is there."
  if kubectl -n default get middlewares.traefik.io redirect-https >/dev/null 2>&1; then
    ok "Traefik Middleware default/redirect-https exists"
    return 0
  fi
  warn "Traefik Middleware default/redirect-https is MISSING. The https:// address will not redirect until it exists."
  warn "The app still works on its NodePort (see the addresses below). Create the Middleware in your k3s/FortiAIGate setup (FAIG's installer makes it), or run this once on the cluster:"
  cat >&2 <<'MWEOF'
kubectl apply -f - <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
  namespace: default
spec:
  redirectScheme:
    scheme: https
    permanent: true
EOF
MWEOF
  return 0
}

# ---- 02: deploy ---------------------------------------------------------------
preflight_secrets() {
  case "$1" in
    assistant)
      secret_exists gemini-api-key || die "Secret gemini-api-key is missing; the pod would not start. Run ./${LAB_ENV}-linux/${LAB_ENV}-06-secrets.sh gemini first." ;;
    mcp|agents)
      ensure_admin_token ;;
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
  local apps a dir tagfile image tag dep envup pull_models=0
  apps="$(resolve_apps "${1:-}")"
  envup="$(upper "$LAB_ENV")"
  intro "DEPLOYING to $LAB_ENV: for each app we read the image version from its manifest (deploy/.../kustomization.yaml, the newTag line), make sure the secrets it needs exist, tell Kubernetes to match the manifest, then wait until the new pod is healthy. A new version rolls out simply because the newTag changed."
  guard_prod
  for a in $apps; do
    dir="$(repo_dir "$a")/$(app_val "$a" "${envup}_DEPLOY")"
    tagfile="$(repo_dir "$a")/$(app_val "$a" TAG_FILE)"
    [ -d "$dir" ] || die "$dir not found. Run ./${LAB_ENV}-linux/${LAB_ENV}-01-git-pull.sh $a first."
    image="$DOCKER_NS/$(app_val "$a" IMAGE)"
    tag="$(manifest_tag "$tagfile" "$image")"
    [ -n "$tag" ] || die "Could not read the image tag for $image from $tagfile"
    dep="$(app_val "$a" DEPLOYMENT)"
    say "Deploying $a: $image:$tag to $LAB_ENV"
    ensure_namespace
    preflight_secrets "$a"
    if [ "$a" = "assistant" ]; then check_traefik_middleware; pull_models=1; fi
    run kubectl apply -k "$dir"
    if [ "$a" = "mcp" ]; then apply_saved_mcp_mode; fi
    if ! run kubectl -n "$NAMESPACE" rollout status "deployment/$dep" --timeout=300s; then
      warn "$dep did not become ready in time. Is the image $image:$tag on Docker Hub? Details:"
      run kubectl -n "$NAMESPACE" get pods
      run kubectl -n "$NAMESPACE" describe deployment "$dep"
      die "Deploy of $a failed."
    fi
    ok "$a is running $image:$tag"
    show_address "$a"
  done
  if [ "$pull_models" = 1 ] && [ "${LAB_SKIP_MODELS:-0}" != "1" ]; then
    vm_pull_models "$LAB_ENV"
  fi
  vm_urls "$LAB_ENV"
}

# ---- 07: language models for Ollama ---------------------------------------------------
# vm_pull_models <env> [model ...]   (no models given: the OLLAMA_MODELS list in lab.env)
vm_pull_models() {
  vm_env "$1"; shift
  require kubectl "k3s should have installed it."
  local models=("$@") m have
  if [ "${#models[@]}" -eq 0 ]; then read -r -a models <<< "$OLLAMA_MODELS"; fi
  intro "LANGUAGE MODELS: the Assistant's local model runs inside the Ollama pod, which starts with no models. Each model is a multi-GB download kept on the ollama-models disk. We only download the ones that are missing, so running this again is quick."
  say "Waiting for the Ollama pod to be ready (its image is large; the first start takes a few minutes)"
  run kubectl -n "$NAMESPACE" rollout status deployment/ollama --timeout=900s \
    || die "The Ollama pod is not ready. Check: ./${LAB_ENV}-linux/${LAB_ENV}-04-logs.sh ollama"
  have="$(kubectl -n "$NAMESPACE" exec deploy/ollama -- ollama list 2>/dev/null | awk 'NR>1 {print $1}')"
  for m in "${models[@]}"; do
    if grep -qxF "$m" <<< "$have"; then
      ok "$m is already downloaded"
      continue
    fi
    say "Downloading $m (several minutes; progress shows below)"
    run kubectl -n "$NAMESPACE" exec deploy/ollama -- ollama pull "$m" \
      || die "Could not download $m. The Ollama pod may lack internet access or disk space."
    ok "$m downloaded"
  done
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
  say "MCP server mode (vulnerable = 14 tools, safe = 10)"
  printf '  %s\n' "$(mcp_current_mode || true)"
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
  printf '  AI Assistant  %s\n  AI Agents     %s\n  MCP server    %s   (inside the cluster only)\n  Ollama        %s   (inside the cluster only)\n  Assistant     %s   (inside the cluster only)\n  Agents        %s   (inside the cluster only)\n' \
    "$(val "${envup}_ASSISTANT_URL")" "$(val "${envup}_AGENTS_URL")" "$CLUSTER_MCP_URL" "$CLUSTER_OLLAMA_URL" "$CLUSTER_ASSISTANT_URL" "$CLUSTER_AGENTS_URL"
  printf '  SSH           %s@%s\n' "$(env_val "$LAB_ENV" USER)" "$(env_val "$LAB_ENV" HOST)"
  printf '  Inside the cluster these names work only from pods in namespace %s. From another namespace (for example FortiAIGate) add it: http://mcp-server.%s.svc.cluster.local:8000/mcp\n' "$NAMESPACE" "$NAMESPACE"
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
    *) die "Usage: ./${LAB_ENV}-linux/${LAB_ENV}-04-logs.sh <assistant|mcp|agents|ollama> [-f]   (-f keeps following; Ctrl+C to stop)" ;;
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
  intro "RESETTING DATA: the MCP server builds its fake company data when it starts. Restarting its pod throws away every change (deleted rows, inserted tickets) and rebuilds the seed data."
  say "Restarting the MCP server: every table goes back to the seed data"
  run kubectl -n "$NAMESPACE" rollout restart deployment/mcp-server
  run kubectl -n "$NAMESPACE" rollout status deployment/mcp-server --timeout=180s
  ok "Data reset. (The ticket-queue reset buttons on the agents page do a lighter reset without a restart.)"
}

# ---- 08: MCP mode (vulnerable / safe) --------------------------------------------
# The MCP server reads MCP_MODE once, when it starts. "vulnerable" has 14 tools (adds run_sql, delete_records,
# read_file, send_email); "safe" has 10. The repo's manifest says vulnerable. A choice made here is saved in a
# small file on this VM (not in git) so a later deploy does not silently put it back.
MCP_MODE_FILE="$HOME/.lab-mcp-mode"

mcp_current_mode() {
  kubectl -n "$NAMESPACE" get deployment mcp-server \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MCP_MODE")].value}' 2>/dev/null
}

# Called by the deploy right after kubectl apply: if you chose a mode earlier, put it back.
apply_saved_mcp_mode() {
  local want cur
  [ -r "$MCP_MODE_FILE" ] || return 0
  want="$(tr -d '[:space:]' < "$MCP_MODE_FILE")"
  case "$want" in safe|vulnerable) ;; *) return 0 ;; esac
  cur="$(mcp_current_mode || true)"
  [ "$cur" = "$want" ] && return 0
  why "You chose the MCP mode '$want' earlier on this VM, but the manifest in git says '${cur:-?}'. Applying your choice again so the deploy does not undo it."
  run kubectl -n "$NAMESPACE" set env deployment/mcp-server "MCP_MODE=$want"
}

# vm_mcp_mode <env> [vulnerable|safe]    (no mode given: just show the current one)
vm_mcp_mode() {
  vm_env "$1"; shift
  require kubectl "k3s should have installed it."
  local want="${1:-}" cur
  intro "MCP MODE: the MCP server decides which tools exist when it starts. 'vulnerable' is the attack lab (14 tools, including run_sql, delete_records, read_file and send_email). 'safe' is read-only with narrow tools (10). Switching restarts the MCP pod, which also rebuilds its fake data. Your choice is remembered on this VM, so a later deploy keeps it."
  cur="$(mcp_current_mode || true)"
  [ -n "$cur" ] || die "The MCP server is not deployed yet. Ship it first (deploy mcp)."
  if [ -z "$want" ]; then
    say "MCP server mode on $LAB_ENV: $cur"
    return 0
  fi
  case "$want" in safe|vulnerable) ;; *) die "Usage: ./${LAB_ENV}-linux/${LAB_ENV}-08-mcp-mode.sh [vulnerable|safe]   (no argument shows the current mode)" ;; esac
  guard_prod
  if [ "$cur" = "$want" ]; then
    ok "Already in $want mode."
  else
    say "Switching the MCP server from $cur to $want"
    run kubectl -n "$NAMESPACE" set env deployment/mcp-server "MCP_MODE=$want"
    run kubectl -n "$NAMESPACE" rollout status deployment/mcp-server --timeout=180s
  fi
  if [ "$DRY" != "1" ]; then printf '%s\n' "$want" > "$MCP_MODE_FILE"; fi
  ok "MCP server is in $want mode. Reload the Assistant page to see the tool count change."
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
  why "Writing the secret: the value goes into a temp file only you can read (chmod 600), is handed to kubectl, then the file is deleted. It never appears on the command line, in this window, or in git."
  printf '\033[0;33m  $ kubectl -n %s create secret generic %s --from-file=%s=<temp file> --dry-run=client -o yaml | kubectl apply -f -\033[0m\n' "$NAMESPACE" "$name" "$key"
  why "create secret ... --dry-run=client -o yaml: builds the Secret definition on this machine without sending it. apply -f - : sends it to the cluster, creating the secret or replacing the old one."
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

read_secret_value() { # prompt -> value on stdout; shows one * per typed character (never the text itself)
  local v="" ch
  printf '%s: ' "$1" >&2
  while IFS= read -rs -n1 ch; do
    case "$ch" in
      ''|$'\r') break ;;                                   # Enter
      $'\177'|$'\b') if [ -n "$v" ]; then v="${v%?}"; printf '\b \b' >&2; fi ;;   # Backspace
      *) v+="$ch"; printf '*' >&2 ;;
    esac
  done
  printf '\n' >&2
  [ -n "$v" ] || die "Nothing entered."
  printf '%s' "$v"
}

vm_secrets() {
  vm_env "$1"; shift
  require kubectl "k3s should have installed it."
  local choice="${1:-}" v name key list
  intro "SECRETS: passwords and API keys live in Kubernetes Secret objects inside the cluster, never in git or in these scripts. Pods read them as environment variables when they start, which is why changing one restarts the pods that use it."
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
  why "Your own login file for k3s (~/.kube/config) is used if it exists. If not, this stops and shows the one-time command to make it."
  kube_access
  run kubectl get nodes
  say "Cloning the app repos next to Scripted-Pipeline-Menu"
  vm_pull "$LAB_ENV" all
  ensure_namespace
  ensure_admin_token
  check_traefik_middleware
  say "Next:"
  printf '  1) ./%s-linux/%s-06-secrets.sh gemini     (paste your Gemini key)\n  2) ./%s-linux/%s-02-deploy.sh all          (deploy everything)\n' "$LAB_ENV" "$LAB_ENV" "$LAB_ENV" "$LAB_ENV"
}
