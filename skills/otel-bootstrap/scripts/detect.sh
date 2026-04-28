#!/usr/bin/env bash
# detect.sh — Detects language and components of the service in TARGET_DIR (default: pwd).
# Prints key=value pairs, one per line. Source this script to set variables.
#
# Output example:
#   language=node
#   has_http=true
#   has_pubsub=true
#   has_cron=false
#
# Usage:
#   eval "$(bash detect.sh)"
#   echo "$language"   # node
#   echo "$has_http"   # true

set -euo pipefail

TARGET_DIR="${TARGET_DIR:-$(pwd)}"

language="unknown"
has_http="false"
has_pubsub="false"
has_cron="false"

# ── Language detection ──────────────────────────────────────────────────────
if [ -f "${TARGET_DIR}/package.json" ]; then
    language="node"
elif [ -f "${TARGET_DIR}/go.mod" ]; then
    language="go"
fi

# ── Component detection (Node) ───────────────────────────────────────────────
if [ "$language" = "node" ]; then
    pkg="${TARGET_DIR}/package.json"
    if python3 -c "
import json, sys
d = json.load(open('${pkg}'))
deps = {**d.get('dependencies',{}), **d.get('devDependencies',{})}
found = any(k in deps for k in ['express','fastify','@nestjs/core','@fastify/core'])
sys.exit(0 if found else 1)
" 2>/dev/null; then
        has_http="true"
    fi

    if python3 -c "
import json, sys
d = json.load(open('${pkg}'))
deps = {**d.get('dependencies',{}), **d.get('devDependencies',{})}
sys.exit(0 if '@google-cloud/pubsub' in deps else 1)
" 2>/dev/null; then
        has_pubsub="true"
    fi

    if [ -d "${TARGET_DIR}/src/crons" ] || python3 -c "
import json, sys
d = json.load(open('${pkg}'))
deps = {**d.get('dependencies',{}), **d.get('devDependencies',{})}
sys.exit(0 if 'node-cron' in deps else 1)
" 2>/dev/null; then
        has_cron="true"
    fi
fi

# ── Component detection (Go) ─────────────────────────────────────────────────
if [ "$language" = "go" ]; then
    gomod="${TARGET_DIR}/go.mod"

    if grep -qE 'github.com/(gin-gonic/gin|labstack/echo|go-chi/chi|gofiber/fiber)' "$gomod" 2>/dev/null \
       || find "${TARGET_DIR}" -name "*.go" -exec grep -l '"net/http"' {} \; 2>/dev/null | grep -q .; then
        has_http="true"
    fi

    if grep -q 'cloud.google.com/go/pubsub' "$gomod" 2>/dev/null; then
        has_pubsub="true"
    fi

    if grep -q 'github.com/robfig/cron' "$gomod" 2>/dev/null \
       || [ -d "${TARGET_DIR}/cmd/cron" ] \
       || [ -d "${TARGET_DIR}/internal/cron" ]; then
        has_cron="true"
    fi
fi

echo "language=${language}"
echo "has_http=${has_http}"
echo "has_pubsub=${has_pubsub}"
echo "has_cron=${has_cron}"
