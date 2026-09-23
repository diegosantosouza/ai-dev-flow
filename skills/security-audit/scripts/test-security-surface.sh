#!/usr/bin/env bash
# Smoke test for security-surface.sh: every category must fire on its fixture,
# and the clean fixture must not trigger any category.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/security-surface.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

FAIL=0

check() {
  local desc="$1"
  local expect_hit="$2" # "yes" or "no"
  local output="$3"
  local section="$4"

  local block
  block="$(awk -v s="### $section" 'index($0,s)==1{f=1;next} /^### /{f=0} f' <<<"$output")"

  if [ "$expect_hit" = "yes" ]; then
    if echo "$block" | grep -qv '(none)' && [ -n "$(echo "$block" | tr -d '[:space:]')" ]; then
      echo "  OK    $desc: detected"
    else
      echo "  FAIL  $desc: expected a hit in '$section', found none"
      FAIL=$((FAIL + 1))
    fi
  else
    if echo "$block" | grep -q '(none)'; then
      echo "  OK    $desc: no false positive"
    else
      echo "  FAIL  $desc: unexpected hit in '$section'"
      echo "$block" | sed 's/^/          /'
      FAIL=$((FAIL + 1))
    fi
  fi
}

mkdir -p "$TMPDIR/dirty" "$TMPDIR/clean" "$TMPDIR/dirty/.github/workflows"

cat > "$TMPDIR/dirty/app.js" <<'EOF'
const apiKey = "sk_live_ABCDEFGHIJ1234567890";
child_process.exec("rm -rf " + userInput);
db.query("SELECT * FROM users WHERE id = " + userId);
eval(userInput);
const agent = new https.Agent({ rejectUnauthorized: false });
app.use(cors({ origin: "*" }));
jwt.verify(token, secret, { algorithms: ["none"] });
EOF

cat > "$TMPDIR/dirty/.github/workflows/ci.yml" <<'EOF'
on: pull_request_target
jobs:
  build:
    steps:
      - uses: some-org/some-action@main
EOF

cat > "$TMPDIR/dirty/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          securityContext:
            privileged: true
            runAsUser: 0
          env:
            - name: DB_PASSWORD
              value: "hunter2"
            - name: apiKey
              value: "lowercase-name-should-still-be-caught"
EOF

cat > "$TMPDIR/dirty/role.yaml" <<'EOF'
kind: Role
rules:
  - resources: ["*"]
    verbs: ["*"]
EOF

cat > "$TMPDIR/clean/app.js" <<'EOF'
const config = loadConfig();
db.query("SELECT * FROM users WHERE id = $1", [userId]);
child_process.execFile("rm", ["-rf", safePath]);
const agent = new https.Agent({ rejectUnauthorized: true });
app.use(cors({ origin: allowedOrigins }));
jwt.verify(token, secret, { algorithms: ["RS256"] });
EOF

cat > "$TMPDIR/clean/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          securityContext:
            runAsNonRoot: true
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: password
EOF

echo "== Running scanner against dirty fixture =="
DIRTY_OUT="$("$SCANNER" "$TMPDIR/dirty")"

check "hardcoded secret"        yes "$DIRTY_OUT" "Hardcoded secret-shaped literals"
check "shell exec"              yes "$DIRTY_OUT" "Shell/subprocess execution"
check "SQL concatenation"       yes "$DIRTY_OUT" "SQL built by string concatenation"
check "eval"                    yes "$DIRTY_OUT" "eval / dynamic code execution"
check "TLS disabled"            yes "$DIRTY_OUT" "TLS/certificate verification disabled"
check "permissive CORS"         yes "$DIRTY_OUT" "Permissive CORS"
check "JWT alg none"            yes "$DIRTY_OUT" "JWT verification bypass"
check "pull_request_target"     yes "$DIRTY_OUT" "GitHub Actions: pull_request_target"
check "unpinned action"         yes "$DIRTY_OUT" "GitHub Actions: unpinned third-party action (mutable ref)"
check "privileged k8s"          yes "$DIRTY_OUT" "Kubernetes/Helm: privileged or host-breaking settings"
check "RBAC wildcard"           yes "$DIRTY_OUT" "Kubernetes RBAC: wildcard resources/verbs"
check "literal secret env"      yes "$DIRTY_OUT" "Kubernetes: secret-shaped env var with literal value (not valueFrom)"

# Dedicated check: the literal-env awk match must not depend on awk's IGNORECASE (a gawk-only
# extension that stock macOS awk silently ignores). Both the uppercase and lowercase env names
# in the dirty fixture must be caught, or this would regress silently.
if command grep -q "apiKey" <<<"$DIRTY_OUT"; then
  echo "  OK    literal secret env (lowercase name): detected"
else
  echo "  FAIL  literal secret env (lowercase name): expected 'apiKey' to be flagged, was not — check awk case-handling, not IGNORECASE"
  FAIL=$((FAIL + 1))
fi

echo
echo "== Running scanner against clean fixture (expect no hits) =="
CLEAN_OUT="$("$SCANNER" "$TMPDIR/clean")"

check "clean: no secret"        no "$CLEAN_OUT" "Hardcoded secret-shaped literals"
check "clean: no shell exec"    no "$CLEAN_OUT" "Shell/subprocess execution"
check "clean: no SQL concat"    no "$CLEAN_OUT" "SQL built by string concatenation"
check "clean: no eval"          no "$CLEAN_OUT" "eval / dynamic code execution"
check "clean: TLS ok"           no "$CLEAN_OUT" "TLS/certificate verification disabled"
check "clean: CORS ok"          no "$CLEAN_OUT" "Permissive CORS"
check "clean: JWT ok"           no "$CLEAN_OUT" "JWT verification bypass"
check "clean: no privileged"    no "$CLEAN_OUT" "Kubernetes/Helm: privileged or host-breaking settings"
check "clean: no literal env"   no "$CLEAN_OUT" "Kubernetes: secret-shaped env var with literal value (not valueFrom)"

echo
if [ "$FAIL" -gt 0 ]; then
  echo "FAILED: $FAIL check(s) did not match expectations."
  exit 1
fi
echo "OK: all scanner categories behave as expected."
