#!/usr/bin/env bash
# Read-only static scanner for /security-audit. Reports REVIEW CANDIDATES, not
# vulnerabilities — every hit still needs the manual boundary audit (Phase 3) and
# adversarial verification (Phase 5) before it becomes a finding.
#
# Usage: security-surface.sh <path>
set -euo pipefail

TARGET="${1:-.}"
if [ ! -e "$TARGET" ]; then
  echo "error: path not found: $TARGET" >&2
  exit 1
fi

EXCLUDES=(--glob '!.git/**' --glob '!node_modules/**' --glob '!vendor/**' --glob '!dist/**'
          --glob '!build/**' --glob '!.next/**' --glob '!coverage/**')

# Always go through `command` to bypass any shell alias/function named grep/rg that a
# user's interactive shell profile may define — this script needs real POSIX ERE semantics.
if command -v rg >/dev/null 2>&1; then
  SEARCH() { command rg -n -i --no-heading "${EXCLUDES[@]}" -e "$1" "$TARGET" 2>/dev/null || true; }
  SEARCH_GLOB() { command rg -n -i --no-heading "${EXCLUDES[@]}" --glob "$2" -e "$1" "$TARGET" 2>/dev/null || true; }
else
  echo "note: ripgrep (rg) not found, falling back to grep (slower, less accurate excludes)" >&2
  SEARCH() {
    command grep -rniE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
      --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=coverage \
      -e "$1" "$TARGET" 2>/dev/null || true
  }
  SEARCH_GLOB() {
    command grep -rniE --include="$2" --exclude-dir=.git --exclude-dir=node_modules \
      --exclude-dir=vendor --exclude-dir=dist --exclude-dir=build --exclude-dir=.next \
      --exclude-dir=coverage -e "$1" "$TARGET" 2>/dev/null || true
  }
fi

report() {
  local title="$1"
  local hits="$2"
  echo "### $title"
  if [ -z "$hits" ]; then
    echo "  (none)"
  else
    echo "$hits" | sed 's/^/  /'
  fi
  echo
}

# Every pattern is assigned to its own variable first, then referenced as "$VAR" below.
# Do not inline a literal {n,m}/{n,} interval directly inside a "$(SEARCH "...")" call: the
# default macOS /bin/bash (3.2, GNU-licensing-frozen) corrupts brace intervals written that
# way — it silently drops the braces and splits the argument in two. A plain variable
# assignment on its own line does not trigger it. Verified with
# skills/security-audit/scripts/test-security-surface.sh.
P_SECRET="(api[_-]?key|secret|password|passwd|token|credential)[[:space:]]*[:=][[:space:]]*[\"'][A-Za-z0-9_\-]{10,}[\"']"
P_SHELL_EXEC="\.(exec|execsync)\(|spawn\([^)]*shell[[:space:]]*:[[:space:]]*true|exec\.command\("
P_SQL_CONCAT="(select|insert|update|delete)[^;]{0,80}(\+|%s|\\\$\{)|sprintf\([^)]*select"
P_EVAL="\beval\(|new[[:space:]]+function\("
P_DESERIALIZE="pickle\.loads|yaml\.load\(|unserialize\(|marshal\.loads"
P_TLS_DISABLED="rejectunauthorized[[:space:]]*:[[:space:]]*false|insecureskipverify[[:space:]]*:?[[:space:]]*true|verify[[:space:]]*=[[:space:]]*false"
P_CORS="access-control-allow-origin.{0,20}\*|origin[[:space:]]*:[[:space:]]*[\"']\*[\"']"
P_JWT_BYPASS="alg(orithm)?s?[[:space:]]*:?[[:space:]]*\[?[\"']?none[\"']?|verify[[:space:]]*=[[:space:]]*false.{0,20}jwt|jwt.{0,20}verify[[:space:]]*=[[:space:]]*false"
P_PR_TARGET="pull_request_target"
P_UNPINNED_ACTION="uses:[[:space:]]*[^@[:space:]]+@(main|master|v[0-9]+)[[:space:]]*\$"
P_K8S_PRIVILEGED="privileged[[:space:]]*:[[:space:]]*true|hostpath|hostnetwork[[:space:]]*:[[:space:]]*true|hostpid[[:space:]]*:[[:space:]]*true|allowprivilegeescalation[[:space:]]*:[[:space:]]*true|runasuser[[:space:]]*:[[:space:]]*0"
P_RBAC_WILDCARD="resources:[[:space:]]*\[?[[:space:]]*[\"']\*[\"']|verbs:[[:space:]]*\[?[[:space:]]*[\"']\*[\"']"
G_YAML="*.y*ml"

echo "# Security surface scan: $TARGET"
echo "# Candidates for review — not vulnerabilities. Verify each in context."
echo

report "Hardcoded secret-shaped literals" "$(SEARCH "$P_SECRET")"
report "Shell/subprocess execution with a raw shell string" "$(SEARCH "$P_SHELL_EXEC")"
report "SQL built by string concatenation" "$(SEARCH "$P_SQL_CONCAT")"
report "eval / dynamic code execution" "$(SEARCH "$P_EVAL")"
report "Unsafe deserialization" "$(SEARCH "$P_DESERIALIZE")"
report "TLS/certificate verification disabled" "$(SEARCH "$P_TLS_DISABLED")"
report "Permissive CORS" "$(SEARCH "$P_CORS")"
report "JWT verification bypass" "$(SEARCH "$P_JWT_BYPASS")"
report "GitHub Actions: pull_request_target" "$(SEARCH_GLOB "$P_PR_TARGET" "$G_YAML")"
report "GitHub Actions: unpinned third-party action (mutable ref)" "$(SEARCH_GLOB "$P_UNPINNED_ACTION" "$G_YAML")"
report "Kubernetes/Helm: privileged or host-breaking settings" "$(SEARCH "$P_K8S_PRIVILEGED")"
report "Kubernetes RBAC: wildcard resources/verbs" "$(SEARCH "$P_RBAC_WILDCARD")"

# Two-line pairing check: a `value:` line immediately preceded by a secret-shaped `name:` line
# in a K8s manifest (literal secret instead of valueFrom.secretKeyRef).
LITERAL_ENV_HITS=""
while IFS= read -r -d '' f; do
  # NOTE: don't rely on awk's IGNORECASE — it's a gawk-only extension. Stock macOS ships the
  # "one true awk" (BWK), where IGNORECASE is silently ignored and the match becomes
  # case-sensitive with no error. Lowercase the line ourselves before matching instead.
  hit="$(awk '
    { lower = tolower($0) }
    lower ~ /name:[[:space:]]*.*(password|secret|token|key|credential)/{prev=$0; prevline=NR; next}
    lower ~ /value:[[:space:]]*[^[:space:]]/{ if (prevline==NR-1) print FILENAME":"NR": "prev" / "$0 }
  ' "$f" 2>/dev/null || true)"
  if [ -n "$hit" ]; then
    LITERAL_ENV_HITS="${LITERAL_ENV_HITS}${LITERAL_ENV_HITS:+$'\n'}${hit}"
  fi
done < <(find "$TARGET" \( -name '*.yml' -o -name '*.yaml' \) -not -path '*/.git/*' -print0 2>/dev/null)
report "Kubernetes: secret-shaped env var with literal value (not valueFrom)" "$LITERAL_ENV_HITS"

echo "# End of scan. Every hit above needs Phase 3 (manual boundary audit) before it's a finding."
