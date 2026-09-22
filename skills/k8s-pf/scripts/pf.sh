#!/usr/bin/env bash
# pf.sh — Housi k8s port-forward manager: mapped targets, multi-tunnel
# supervision with reconnect, and a self-refreshing catalog. See ../SKILL.md.
#
# IMPORTANT SECURITY PROPERTY: this script never executes `kubectl` itself.
# `plan`/`up` RESOLVE the target and PRINT the exact command to run; the
# caller (agent or human) executes it via the Bash tool. This keeps the
# literal `kubectl ... port-forward ...` string visible to the PreToolUse
# guard (~/.claude/hooks/housi-k8s-guard.sh), which only inspects command
# text and would silently miss a wrapper that called kubectl internally.
# Never change `up` to exec kubectl directly, and never wrap the printed
# command in `setsid` — both defeat the guard for prod/homolog targets.
#
# Usage:
#   pf.sh plan   <target> [--env sandbox|homolog|prod] [--port NAME] [--local-port N] [--json]
#   pf.sh up     <target> [--env E] [--port NAME] [--local-port N] [--json]
#   pf.sh status [--deep] [--json] [<id>]
#   pf.sh list   [--env E] [--json]
#   pf.sh down   <id>|--all
#   pf.sh logs   <id> [-n N]
#   pf.sh sync   (--env E | --all) [--dry-run]
#   pf.sh doctor
#   pf.sh compile   # internal: registry.yaml -> catalog.json (needs yq)
#
# Exit codes:
#   0  ok
#   2  usage error / missing dependency
#   3  unknown target (not in the catalog, not even after an auto-sync retry)
#   4  environment missing or ambiguous for this target — ask, don't guess
#   5  local port already in use by something else
#   6  no such open forward / resource not found
#   7  service exists but has zero ready endpoints
#   8  auth/RBAC failure
#   9  the security guard denied confirmation for this command
#   10 supervisor gave up (restart budget exhausted or fatal error classified)

set -uo pipefail

# ---- path resolution (symlink-safe: this file is often a symlink target
# under ~/.claude/skills/k8s-pf/scripts/pf.sh) -------------------------------
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"
DATA_DIR="$SKILL_DIR/data"
REGISTRY="$DATA_DIR/registry.yaml"
CATALOG="$DATA_DIR/catalog.json"
PF_SELF="$SCRIPT_DIR/pf.sh"

STATE_DIR="${HOUSI_PF_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/housi-pf}"
FORWARDS_DIR="$STATE_DIR/forwards"

CATALOG_TTL_DAYS=7
RESTART_BUDGET=20
RESTART_WINDOW_SECS=300
JSON_MODE=false

mkdir -p "$FORWARDS_DIR" 2>/dev/null

# ---- dependency checks ------------------------------------------------------
need_jq() { command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required (brew install jq)" >&2; exit 2; }; }
need_yq() { command -v yq >/dev/null 2>&1 || { echo "error: 'yq' (mikefarah/yq) is required to compile data/registry.yaml (brew install yq). This only matters if you edited registry.yaml — the committed data/catalog.json is already usable without yq." >&2; exit 2; }; }
need_kubectl() { command -v kubectl >/dev/null 2>&1 || { echo "error: 'kubectl' not found in PATH" >&2; exit 2; }; }

need_jq

# ---- output helpers ----------------------------------------------------------
emit_error() { # $1=exit code  $2=human message
  local code=$1 msg=$2
  if [ "$JSON_MODE" = true ]; then
    jq -n --arg error "$msg" --argjson code "$code" '{ok:false, exit:$code, error:$error}'
  else
    echo "error: $msg" >&2
  fi
  exit "$code"
}

# ---- catalog compile & freshness ---------------------------------------------
cmd_compile() {
  need_yq
  local tmp_reg tmp_cat
  tmp_reg=$(mktemp) || exit 2
  tmp_cat=$(mktemp) || { rm -f "$tmp_reg"; exit 2; }

  if ! yq -o=json eval '.' "$REGISTRY" > "$tmp_reg"; then
    rm -f "$tmp_reg" "$tmp_cat"
    emit_error 2 "failed to parse $REGISTRY"
  fi
  if ! jq -f "$SCRIPT_DIR/compile.jq" --arg generated_at "$(date -u +%FT%TZ)" "$tmp_reg" > "$tmp_cat"; then
    rm -f "$tmp_reg" "$tmp_cat"
    emit_error 2 "failed to compile catalog from registry.yaml"
  fi
  mv "$tmp_cat" "$CATALOG"
  rm -f "$tmp_reg"
  echo "compiled $(jq '.entries|length' "$CATALOG") entries -> $CATALOG"
}

ensure_catalog_fresh() {
  if [ ! -f "$CATALOG" ]; then
    if command -v yq >/dev/null 2>&1; then
      cmd_compile >/dev/null
    else
      emit_error 2 "data/catalog.json is missing and 'yq' is not available to compile it. Restore it from git, or install yq and run 'pf.sh compile'."
    fi
    return 0
  fi
  if [ "$REGISTRY" -nt "$CATALOG" ] && command -v yq >/dev/null 2>&1; then
    cmd_compile >/dev/null
  fi
}

catalog_age_notice() {
  [ "$JSON_MODE" = true ] && return 0
  [ -f "$CATALOG" ] || return 0
  local gen gen_epoch now age_days
  gen=$(jq -r '.generated_at // empty' "$CATALOG" 2>/dev/null)
  [ -z "$gen" ] && return 0
  gen_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$gen" +%s 2>/dev/null) || return 0
  now=$(date +%s)
  age_days=$(( (now - gen_epoch) / 86400 ))
  if [ "$age_days" -ge "$CATALOG_TTL_DAYS" ]; then
    echo "note: catalog is ${age_days}d old — run 'pf.sh sync --all' to refresh" >&2
  fi
}

# ---- catalog lookups ----------------------------------------------------------
resolve_target() { # $1 = target name or alias -> canonical name
  jq -r --arg n "$1" '(.aliases[$n] // $n)' "$CATALOG"
}

list_envs_for_target() { # $1 = canonical target -> comma-joined env list
  jq -r --arg t "$1" '[.entries[] | select(.target==$t) | .env] | unique | join(", ")' "$CATALOG"
}

lookup_entry() { # $1=env $2=canonical target -> JSON entry or empty
  jq -c --arg env "$1" --arg t "$2" '.entries[] | select(.env==$env and .target==$t)' "$CATALOG"
}

suggest_targets() { # $1 = user's typo'd input -> up to 5 comma-joined near names
  jq -r --arg q "$1" '
    ([.entries[].target] + (.aliases | keys)) | unique
    | map(select(
        (. | ascii_downcase | contains($q | ascii_downcase))
        or ($q | ascii_downcase | contains(. | ascii_downcase))
        or (.[0:3] == $q[0:3])
      ))
    | .[0:5] | join(", ")
  ' "$CATALOG"
}

port_owner() { lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }

tcp_probe() { # $1 = local port -> 0 if something accepts a TCP connection
  bash -c 'exec 3<>"/dev/tcp/127.0.0.1/'"$1"'"' >/dev/null 2>&1
}

is_slot_alive() { # $1 = id
  local slot="$FORWARDS_DIR/$1"
  [ -f "$slot/supervisor.pid" ] || return 1
  local pid; pid=$(cat "$slot/supervisor.pid" 2>/dev/null)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ---- shared target/env/port resolution ---------------------------------------
# Sets globals: R_ID R_ENV R_TARGET R_CONTEXT R_NAMESPACE R_RESOURCE R_RISK
# R_SECRET_REF R_PORTS_JSON. Calls emit_error (and exits) on any failure.
resolve_and_plan() {
  local target_arg=$1 env_arg=${2:-} port_name=${3:-} local_port_override=${4:-}

  ensure_catalog_fresh
  local canonical; canonical=$(resolve_target "$target_arg")
  local available_envs; available_envs=$(list_envs_for_target "$canonical")

  if [ -z "$available_envs" ] && [ -n "$env_arg" ] && command -v kubectl >/dev/null 2>&1; then
    # cache-aside miss: sync just this env, then retry resolution once.
    cmd_sync --env "$env_arg" >/dev/null 2>&1 || true
    canonical=$(resolve_target "$target_arg")
    available_envs=$(list_envs_for_target "$canonical")
  fi

  if [ -z "$available_envs" ]; then
    local sugg; sugg=$(suggest_targets "$target_arg")
    if [ -n "$sugg" ]; then
      emit_error 3 "unknown target '$target_arg'. Did you mean: $sugg? (ran an auto-sync and still no match — try 'pf.sh sync --all' or 'pf.sh list')"
    else
      emit_error 3 "unknown target '$target_arg' — not in the catalog even after an auto-sync. Try 'pf.sh list' to see everything mapped."
    fi
  fi

  if [ -z "$env_arg" ]; then
    emit_error 4 "target '$canonical' needs --env. Available for this target: $available_envs"
  fi

  local entry; entry=$(lookup_entry "$env_arg" "$canonical")
  if [ -z "$entry" ]; then
    emit_error 4 "target '$canonical' is not mapped in env '$env_arg'. Available envs for this target: $available_envs"
  fi

  R_ID=$(jq -r '.id' <<<"$entry")
  R_ENV=$env_arg
  R_TARGET=$canonical
  R_CONTEXT=$(jq -r '.context' <<<"$entry")
  R_NAMESPACE=$(jq -r '.namespace' <<<"$entry")
  R_RESOURCE=$(jq -r '.resource' <<<"$entry")
  R_RISK=$(jq -r '.risk' <<<"$entry")
  R_SECRET_REF=$(jq -c '.secret_ref' <<<"$entry")

  local ports_json
  if [ -n "$port_name" ]; then
    ports_json=$(jq -c --arg p "$port_name" '[.ports[] | select(.name==$p)]' <<<"$entry")
    if [ "$(jq 'length' <<<"$ports_json")" -eq 0 ]; then
      local allports; allports=$(jq -r '[.ports[].name] | join(", ")' <<<"$entry")
      emit_error 2 "port '$port_name' not found for $canonical/$env_arg. Available: $allports"
    fi
  else
    ports_json=$(jq -c '.ports' <<<"$entry")
  fi

  if [ -n "$local_port_override" ]; then
    if [ "$(jq 'length' <<<"$ports_json")" -ne 1 ]; then
      emit_error 2 "--local-port requires selecting exactly one port via --port (this target/env exposes more than one)"
    fi
    ports_json=$(jq --argjson lp "$local_port_override" '.[0].local = $lp' <<<"$ports_json")
  fi

  R_PORTS_JSON=$ports_json
}

port_pairs() { jq -r '[.[] | "\(.local):\(.remote)"] | join(" ")' <<<"$R_PORTS_JSON"; }

# ---- plan / up -----------------------------------------------------------------
parse_resolve_args() { # fills TARGET ENV PORT_NAME LOCAL_PORT_OVERRIDE, may set JSON_MODE
  TARGET="" ENV="" PORT_NAME="" LOCAL_PORT_OVERRIDE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --env) ENV=${2:-}; shift 2 ;;
      --port) PORT_NAME=${2:-}; shift 2 ;;
      --local-port) LOCAL_PORT_OVERRIDE=${2:-}; shift 2 ;;
      --json) JSON_MODE=true; shift ;;
      -*) emit_error 2 "unknown flag: $1" ;;
      *) TARGET=$1; shift ;;
    esac
  done
}

cmd_plan() {
  parse_resolve_args "$@"
  [ -z "$TARGET" ] && emit_error 2 "usage: pf.sh plan <target> [--env E] [--port NAME] [--local-port N] [--json]"
  resolve_and_plan "$TARGET" "$ENV" "$PORT_NAME" "$LOCAL_PORT_OVERRIDE"

  local id=$R_ID pairs cmdline
  pairs=$(port_pairs)
  cmdline="kubectl --context $R_CONTEXT -n $R_NAMESPACE port-forward $R_RESOURCE $pairs"

  local busy=""
  local lp owner
  for lp in $(jq -r '.[].local' <<<"$R_PORTS_JSON"); do
    owner=$(port_owner "$lp")
    if [ -n "$owner" ]; then
      if [ -f "$FORWARDS_DIR/$id/supervisor.pid" ] && pgrep -P "$owner" >/dev/null 2>&1 && [ "$(cat "$FORWARDS_DIR/$id/supervisor.pid" 2>/dev/null)" = "$owner" ]; then
        : # it's our own already-open tunnel for this exact id
      else
        busy="$busy $lp(pid=$owner)"
      fi
    fi
  done

  if [ "$JSON_MODE" = true ]; then
    jq -n --arg id "$id" --arg env "$R_ENV" --arg target "$R_TARGET" --arg cmd "$cmdline" \
      --arg risk "$R_RISK" --argjson ports "$R_PORTS_JSON" --arg busy "$busy" \
      '{ok:true, id:$id, env:$env, target:$target, risk:$risk, ports:$ports, command:$cmd, busy_ports:$busy}'
  else
    echo "id:      $id"
    echo "env:     $R_ENV  (risk: $R_RISK)"
    echo "target:  $R_TARGET  ($R_RESOURCE in ns/$R_NAMESPACE)"
    echo "ports:   $pairs  (local:remote)"
    [ -n "$busy" ] && echo "warning: local port(s) already in use:$busy"
    echo ""
    echo "command:"
    echo "  $cmdline"
  fi
}

cmd_up() {
  parse_resolve_args "$@"
  [ -z "$TARGET" ] && emit_error 2 "usage: pf.sh up <target> [--env E] [--port NAME] [--local-port N] [--json]"
  resolve_and_plan "$TARGET" "$ENV" "$PORT_NAME" "$LOCAL_PORT_OVERRIDE"

  local id=$R_ID slot="$FORWARDS_DIR/$R_ID"

  if is_slot_alive "$id"; then
    if [ "$JSON_MODE" = true ]; then
      jq -n --arg id "$id" '{ok:true, already_up:true, id:$id}'
    else
      echo "already up: $id — see 'pf.sh status $id'"
    fi
    return 0
  fi

  local pairs; pairs=$(port_pairs)
  local lp owner
  for lp in $(jq -r '.[].local' <<<"$R_PORTS_JSON"); do
    owner=$(port_owner "$lp")
    if [ -n "$owner" ]; then
      local ownercmd; ownercmd=$(ps -p "$owner" -o command= 2>/dev/null)
      emit_error 5 "local port $lp is already in use by pid $owner ($ownercmd). Use --local-port to pick another, or 'pf.sh down $id' first if it's a stale tunnel of ours."
    fi
  done

  rm -rf "$slot"
  mkdir -p "$slot"
  : > "$slot/log"
  echo "pending" > "$slot/state"
  jq -n --arg id "$id" --arg env "$R_ENV" --arg target "$R_TARGET" --arg context "$R_CONTEXT" \
    --arg namespace "$R_NAMESPACE" --arg resource "$R_RESOURCE" --argjson ports "$R_PORTS_JSON" \
    --arg risk "$R_RISK" --arg created_at "$(date -u +%FT%TZ)" \
    '{id:$id, env:$env, target:$target, context:$context, namespace:$namespace, resource:$resource, ports:$ports, risk:$risk, created_at:$created_at}' \
    > "$slot/meta.json"

  local cmdline="kubectl --context $R_CONTEXT -n $R_NAMESPACE port-forward $R_RESOURCE $pairs"
  local wrapped
  wrapped="nohup bash -c 'echo \$\$ > \"$slot/supervisor.pid\"; echo running > \"$slot/state\"; while :; do $cmdline >>\"$slot/log\" 2>&1; rc=\$?; \"$PF_SELF\" _tick \"$id\" \"\$rc\" || break; done; echo stopped > \"$slot/state\"' >/dev/null 2>&1 &"

  if [ "$JSON_MODE" = true ]; then
    jq -n --arg id "$id" --arg env "$R_ENV" --arg target "$R_TARGET" --arg risk "$R_RISK" \
      --arg run "$wrapped" --argjson ports "$R_PORTS_JSON" \
      '{ok:true, id:$id, env:$env, target:$target, risk:$risk, ports:$ports, run:$run,
        note:"execute this exact string via the Bash tool — the literal kubectl call must stay visible to the security guard; never wrap it further (no setsid)."}'
  else
    if [ "$R_RISK" = "critical" ]; then
      echo "!! risk: critical (production datastore) — confirm with the user before running this !!"
    fi
    echo "id:    $id"
    echo "ports: $pairs (local:remote) — logs: $slot/log"
    echo ""
    echo "Run this exact command (the kubectl call must stay literal for the security guard):"
    echo ""
    echo "$wrapped"
  fi
}

# ---- internal: supervisor tick (never calls kubectl) ---------------------------
cmd__tick() {
  local id=$1 rc=${2:-1}
  local slot="$FORWARDS_DIR/$id"
  [ -d "$slot" ] || exit 1

  if [ "$(cat "$slot/state" 2>/dev/null)" = "stopped" ]; then
    exit 1 # a `down` was issued concurrently — don't restart
  fi

  local tail_log; tail_log=$(tail -n 20 "$slot/log" 2>/dev/null)

  case "$tail_log" in
    *"unable to listen"*|*"Unable to listen"*|*"address already in use"*)
      echo "failed" > "$slot/state"
      echo "$(date -u +%FT%TZ) FATAL: local bind failed, not retrying (exit $rc)" >> "$slot/log"
      exit 1 ;;
  esac
  case "$tail_log" in
    *"orbidden"*|*"nauthorized"*)
      echo "failed" > "$slot/state"
      echo "$(date -u +%FT%TZ) FATAL: auth/RBAC error, not retrying — run 'pf.sh doctor' (exit $rc)" >> "$slot/log"
      exit 1 ;;
  esac

  local now budget_file count
  now=$(date +%s)
  budget_file="$slot/restarts"
  touch "$budget_file"
  awk -v now="$now" -v win="$RESTART_WINDOW_SECS" '$1 > now-win' "$budget_file" > "$budget_file.tmp" 2>/dev/null
  mv "$budget_file.tmp" "$budget_file"
  echo "$now" >> "$budget_file"
  count=$(wc -l < "$budget_file" 2>/dev/null | tr -d ' ')
  [ -z "$count" ] && count=1

  if [ "$count" -gt "$RESTART_BUDGET" ]; then
    echo "failed" > "$slot/state"
    echo "$(date -u +%FT%TZ) FATAL: giving up after $RESTART_BUDGET restarts in ${RESTART_WINDOW_SECS}s" >> "$slot/log"
    exit 1
  fi

  echo "backoff" > "$slot/state"
  local delay
  case "$count" in
    1) delay=1 ;; 2) delay=2 ;; 3) delay=4 ;; 4) delay=8 ;; *) delay=15 ;;
  esac
  echo "$(date -u +%FT%TZ) retry #$count in ${delay}s (kubectl exit $rc)" >> "$slot/log"
  sleep "$delay"
  echo "running" > "$slot/state"
  exit 0
}

# ---- down / status / logs / list ----------------------------------------------
down_one() {
  local id=$1
  local slot="$FORWARDS_DIR/$id"
  [ -d "$slot" ] || emit_error 6 "no such forward: $id"
  if [ -f "$slot/supervisor.pid" ]; then
    local pid; pid=$(cat "$slot/supervisor.pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      local kids k; kids=$(pgrep -P "$pid" 2>/dev/null)
      for k in $kids; do kill -TERM "$k" 2>/dev/null; done
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
      for k in $kids; do kill -0 "$k" 2>/dev/null && kill -KILL "$k" 2>/dev/null; done
    fi
  fi
  echo "stopped" > "$slot/state"
  if [ "$JSON_MODE" = true ]; then
    jq -n --arg id "$id" '{ok:true, id:$id, state:"stopped"}'
  else
    echo "down: $id"
  fi
}

cmd_down() {
  local args=() a
  for a in "$@"; do [ "$a" = "--json" ] && JSON_MODE=true || args+=("$a"); done
  if [ "${args[0]:-}" = "--all" ]; then
    local any=0 d id
    for d in "$FORWARDS_DIR"/*/; do
      [ -d "$d" ] || continue
      id=$(basename "$d")
      down_one "$id"
      any=1
    done
    [ "$any" -eq 0 ] && echo "no forwards open"
    return 0
  fi
  [ -z "${args[0]:-}" ] && emit_error 2 "usage: pf.sh down <id>|--all"
  down_one "${args[0]}"
}

cmd_status() {
  local deep=false id="" a args=()
  for a in "$@"; do
    case "$a" in
      --deep) deep=true ;;
      --json) JSON_MODE=true ;;
      -*) emit_error 2 "unknown flag: $a" ;;
      *) args+=("$a") ;;
    esac
  done
  id=${args[0]:-}

  local ids
  if [ -n "$id" ]; then
    ids=$id
  else
    ids=$(ls -1 "$FORWARDS_DIR" 2>/dev/null)
  fi

  if [ -z "$ids" ]; then
    if [ "$JSON_MODE" = true ]; then echo '{"ok":true,"forwards":[]}'; else echo "no forwards open"; fi
    catalog_age_notice
    return 0
  fi

  local rows="[]" i
  for i in $ids; do
    local slot="$FORWARDS_DIR/$i"
    [ -d "$slot" ] || continue
    local state pid alive=false
    state=$(cat "$slot/state" 2>/dev/null || echo "unknown")
    pid=$(cat "$slot/supervisor.pid" 2>/dev/null || echo "")
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=true

    local env target risk ports
    env=$(jq -r '.env // "?"' "$slot/meta.json" 2>/dev/null)
    target=$(jq -r '.target // "?"' "$slot/meta.json" 2>/dev/null)
    risk=$(jq -r '.risk // "?"' "$slot/meta.json" 2>/dev/null)
    ports=$(jq -c '.ports // []' "$slot/meta.json" 2>/dev/null || echo "[]")

    local listening="[]" healthy="[]" lp
    for lp in $(jq -r '.[].local' <<<"$ports" 2>/dev/null); do
      if [ -n "$(port_owner "$lp")" ]; then
        listening=$(jq --argjson p "$lp" '. + [$p]' <<<"$listening")
      fi
      if [ "$deep" = true ] && tcp_probe "$lp"; then
        healthy=$(jq --argjson p "$lp" '. + [$p]' <<<"$healthy")
      fi
    done

    local row
    if [ "$deep" = true ]; then
      row=$(jq -n --arg id "$i" --arg env "$env" --arg target "$target" --arg risk "$risk" \
        --arg state "$state" --argjson alive "$alive" --argjson ports "$ports" \
        --argjson listening "$listening" --argjson healthy "$healthy" \
        '{id:$id, env:$env, target:$target, risk:$risk, state:$state, alive:$alive, ports:$ports, listening:$listening, healthy:$healthy}')
    else
      row=$(jq -n --arg id "$i" --arg env "$env" --arg target "$target" --arg risk "$risk" \
        --arg state "$state" --argjson alive "$alive" --argjson ports "$ports" --argjson listening "$listening" \
        '{id:$id, env:$env, target:$target, risk:$risk, state:$state, alive:$alive, ports:$ports, listening:$listening}')
    fi
    rows=$(jq --argjson r "$row" '. + [$r]' <<<"$rows")
  done

  if [ "$JSON_MODE" = true ]; then
    jq -n --argjson forwards "$rows" '{ok:true, forwards:$forwards}'
  else
    jq -r '.[] | "\(.id)  env=\(.env) target=\(.target) risk=\(.risk) state=\(.state) alive=\(.alive)  ports=\([.ports[]|"\(.local):\(.remote)"]|join(","))  listening=\(.listening)" + (if has("healthy") then "  healthy=\(.healthy)" else "" end)' <<<"$rows"
  fi
  catalog_age_notice
}

cmd_logs() {
  local id="" n=50 a args=()
  for a in "$@"; do args+=("$a"); done
  local i=0
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      -n) i=$((i+1)); n=${args[$i]:-50} ;;
      --json) JSON_MODE=true ;;
      *) id=${args[$i]} ;;
    esac
    i=$((i+1))
  done
  [ -z "$id" ] && emit_error 2 "usage: pf.sh logs <id> [-n N]"
  local slot="$FORWARDS_DIR/$id"
  [ -d "$slot" ] || emit_error 6 "no such forward: $id"
  if [ "$JSON_MODE" = true ]; then
    jq -Rn --arg id "$id" --arg log "$(tail -n "$n" "$slot/log" 2>/dev/null)" '{ok:true, id:$id, log:$log}'
  else
    tail -n "$n" "$slot/log" 2>/dev/null
  fi
}

cmd_list() {
  local env=""
  local args=("$@") i=0
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      --env) i=$((i+1)); env=${args[$i]:-} ;;
      --json) JSON_MODE=true ;;
    esac
    i=$((i+1))
  done

  ensure_catalog_fresh
  local filtered
  if [ -n "$env" ]; then
    filtered=$(jq -c --arg e "$env" '[.entries[] | select(.env==$e)]' "$CATALOG")
  else
    filtered=$(jq -c '.entries' "$CATALOG")
  fi
  if [ "$JSON_MODE" = true ]; then
    jq -n --argjson e "$filtered" '{ok:true, entries:$e}'
  else
    jq -r '.[] | "\(.env)/\(.target)  \(.resource)  ns=\(.namespace)  ports=\([.ports[]|"\(.local):\(.remote)"]|join(","))  risk=\(.risk)  source=\(.source)"' <<<"$filtered"
  fi
}

# ---- sync (real kubectl discovery, read-only) ----------------------------------
cmd_sync() {
  local env_filter="" all=false dry=false args=("$@") i=0
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      --env) i=$((i+1)); env_filter=${args[$i]:-} ;;
      --all) all=true ;;
      --dry-run) dry=true ;;
      --json) JSON_MODE=true ;;
    esac
    i=$((i+1))
  done

  need_kubectl
  ensure_catalog_fresh

  local envs
  if [ -n "$env_filter" ]; then
    envs=$env_filter
  elif [ "$all" = true ]; then
    envs=$(jq -r '.environments|keys[]' "$CATALOG")
  else
    emit_error 2 "usage: pf.sh sync (--env E | --all) [--dry-run]"
  fi

  local tmp_catalog; tmp_catalog=$(mktemp)
  cp "$CATALOG" "$tmp_catalog"

  local added=0 verified=0 warned=0 e

  for e in $envs; do
    local ctx; ctx=$(jq -r --arg e "$e" '.environments[$e].context // empty' "$CATALOG")
    if [ -z "$ctx" ]; then
      echo "skip: unknown env '$e'" >&2
      warned=$((warned+1))
      continue
    fi
    local base; base=$(jq -r --arg e "$e" '.environments[$e].local_port_base' "$CATALOG")

    local role_ns_pairs; role_ns_pairs=$(jq -r --arg e "$e" '.environments[$e].namespaces | to_entries[] | "\(.key)=\(.value)"' "$CATALOG")
    local pair role ns
    for pair in $role_ns_pairs; do
      role=${pair%%=*}
      ns=${pair#*=}

      local raw errfile; errfile=$(mktemp)
      if ! raw=$(kubectl --context "$ctx" -n "$ns" get svc -o json 2>"$errfile"); then
        echo "warn: could not list services in $e/$ns: $(cat "$errfile")" >&2
        warned=$((warned+1))
        rm -f "$errfile"
        continue
      fi
      rm -f "$errfile"

      local items_file; items_file=$(mktemp)
      jq -c '.items[] | select(.spec.ports != null and (.spec.ports|length) > 0) | {svc: .metadata.name, port: .spec.ports[0].port}' <<<"$raw" > "$items_file"

      local item svc port tname existing_by_resource tmp2
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        svc=$(jq -r '.svc' <<<"$item")
        port=$(jq -r '.port' <<<"$item")
        tname=${svc%-service}

        # Match any curated/discovered entry in this env whose resource is this
        # exact Service — covers datastores too (e.g. mysql's real svc name
        # doesn't match its target name), not just the app-role naming convention.
        existing_by_resource=$(jq -c --arg env "$e" --arg res "svc/$svc" \
          '.entries[] | select(.env==$env and .resource==$res)' "$tmp_catalog")

        if [ -n "$existing_by_resource" ]; then
          tmp2=$(mktemp)
          jq --arg env "$e" --arg res "svc/$svc" --arg ts "$(date -u +%FT%TZ)" \
            '(.entries[] | select(.env==$env and .resource==$res) | .verified_at) |= $ts' "$tmp_catalog" > "$tmp2"
          mv "$tmp2" "$tmp_catalog"
          verified=$((verified+1))
          continue
        fi

        if [ "$role" != "app" ]; then
          continue # datastores/observability outside the curated set need a human, not auto-add
        fi

        local h off lp used
        h=$(cksum <<<"$tname" | awk '{print $1}')
        off=$(( h % 900 ))
        lp=$(( base + off ))
        used=$(jq -r --argjson lp "$lp" '[.entries[].ports[].local] | any(. == $lp)' "$tmp_catalog")
        while [ "$used" = "true" ]; do
          lp=$((lp+1))
          used=$(jq -r --argjson lp "$lp" '[.entries[].ports[].local] | any(. == $lp)' "$tmp_catalog")
        done

        tmp2=$(mktemp)
        jq --arg env "$e" --arg t "$tname" --arg ctx "$ctx" --arg ns "$ns" --arg svc "$svc" \
           --argjson port "$port" --argjson lp "$lp" --arg ts "$(date -u +%FT%TZ)" \
           '.entries += [{
              id: ($env + "-" + $t), env: $env, target: $t, kind: "discovered",
              ns_role: "app", namespace: $ns, context: $ctx, resource: ("svc/" + $svc),
              ports: [{name:"default", remote:$port, local:$lp}],
              risk: (.environments[$env].risk), secret_ref: null,
              source: "discovered", discovered_at: $ts, verified_at: $ts
            }]' "$tmp_catalog" > "$tmp2"
        mv "$tmp2" "$tmp_catalog"
        added=$((added+1))
        echo "+ $e/$tname  svc/$svc  $lp:$port  (new, auto-discovered)"
      done < "$items_file"
      rm -f "$items_file"

      # Verify (never auto-add) curated StatefulSet-backed targets in this
      # namespace — datastores like sandbox/mysql use `resource:
      # statefulset/housi-dev-mysql`, which the svc scan above can't match.
      local raw_sts errfile2; errfile2=$(mktemp)
      if raw_sts=$(kubectl --context "$ctx" -n "$ns" get statefulset -o json 2>"$errfile2"); then
        local sts_names_file; sts_names_file=$(mktemp)
        jq -r '.items[].metadata.name' <<<"$raw_sts" > "$sts_names_file"
        local stsname
        while IFS= read -r stsname; do
          [ -z "$stsname" ] && continue
          if [ -n "$(jq -c --arg env "$e" --arg res "statefulset/$stsname" '.entries[] | select(.env==$env and .resource==$res)' "$tmp_catalog")" ]; then
            tmp2=$(mktemp)
            jq --arg env "$e" --arg res "statefulset/$stsname" --arg ts "$(date -u +%FT%TZ)" \
              '(.entries[] | select(.env==$env and .resource==$res) | .verified_at) |= $ts' "$tmp_catalog" > "$tmp2"
            mv "$tmp2" "$tmp_catalog"
            verified=$((verified+1))
          fi
        done < "$sts_names_file"
        rm -f "$sts_names_file"
      fi
      rm -f "$errfile2"
    done
  done

  echo "sync: +$added new, $verified verified, $warned warnings"

  if [ "$dry" = true ]; then
    rm -f "$tmp_catalog"
    echo "(dry-run — catalog not written)"
    return 0
  fi

  jq --arg ts "$(date -u +%FT%TZ)" '.generated_at = $ts' "$tmp_catalog" > "$tmp_catalog.out"
  mv "$tmp_catalog.out" "$CATALOG"
  rm -f "$tmp_catalog"
}

# ---- doctor ---------------------------------------------------------------------
cmd_doctor() {
  echo "== pf.sh doctor =="
  if command -v kubectl >/dev/null 2>&1; then
    echo "kubectl: $(kubectl version --client 2>/dev/null | head -1)"
  else
    echo "kubectl: MISSING"
  fi
  command -v jq >/dev/null 2>&1 && echo "jq: present" || echo "jq: MISSING (required)"
  command -v yq >/dev/null 2>&1 && echo "yq: present (only needed to recompile registry.yaml)" || echo "yq: missing (only needed if you edit registry.yaml)"

  if [ -f "$CATALOG" ]; then
    echo "catalog: $CATALOG (generated_at=$(jq -r '.generated_at' "$CATALOG"), entries=$(jq '.entries|length' "$CATALOG"))"
  else
    echo "catalog: MISSING — run 'pf.sh compile' (needs yq) or restore data/catalog.json from git"
  fi
  catalog_age_notice

  echo ""
  echo "gcloud auth:"
  if command -v gcloud >/dev/null 2>&1; then
    gcloud auth list --format="value(account)" --filter=status:ACTIVE 2>/dev/null | sed 's/^/  /' || echo "  none active — run: gcloud auth login"
  else
    echo "  gcloud not found"
  fi

  echo ""
  echo "open forwards:"
  local any=0 d id state pid alive
  for d in "$FORWARDS_DIR"/*/; do
    [ -d "$d" ] || continue
    any=1
    id=$(basename "$d")
    state=$(cat "$d/state" 2>/dev/null || echo unknown)
    pid=$(cat "$d/supervisor.pid" 2>/dev/null || echo "")
    alive="no"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive="yes"
    echo "  $id  state=$state  alive=$alive"
    if [ "$alive" = "no" ] && [ -n "$pid" ] && [ "$state" != "stopped" ] && [ "$state" != "failed" ]; then
      echo "    orphaned pidfile (pid $pid is dead) — run 'pf.sh down $id' to clean up"
    fi
  done
  [ "$any" -eq 0 ] && echo "  (none)"
}

# ---- dispatch ---------------------------------------------------------------------
main() {
  local sub=${1:-}
  [ $# -gt 0 ] && shift
  case "$sub" in
    compile) cmd_compile "$@" ;;
    plan) cmd_plan "$@" ;;
    up) cmd_up "$@" ;;
    status) cmd_status "$@" ;;
    list) cmd_list "$@" ;;
    down) cmd_down "$@" ;;
    logs) cmd_logs "$@" ;;
    sync) cmd_sync "$@" ;;
    doctor) cmd_doctor "$@" ;;
    _tick) cmd__tick "$@" ;;
    -h|--help|"") grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown subcommand: $sub (try -h)" >&2; exit 2 ;;
  esac
}

main "$@"
