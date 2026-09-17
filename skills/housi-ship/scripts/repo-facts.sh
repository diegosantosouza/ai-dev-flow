#!/usr/bin/env bash
# repo-facts.sh — detecta, para o repo git no cwd, as convenções que /housi-ship precisa
# antes de criar branch/cherry-pick/PR:
#   - mapa ambiente -> branch-base (via on.push.branches dos workflows de deploy)
#   - deleteBranchOnMerge / defaultBranchRef (gh repo view)
#   - estilo de head branch: "shared" (uma branch, N PRs) vs "per-environment" (uma por ambiente)
#   - presença de pull_request_template.md
#
# Deliberadamente NÃO hardcoda nomes de branch (develop/homolog/main/dev) nem valores literais
# de STAGE (sandbox/apps-hml/apps) — classifica por palavra-chave para generalizar a qualquer
# repo housi, não só aos usados quando este script foi escrito. Nunca falha se não achar nada:
# devolve environments vazio / branch_style "unknown" e deixa a skill perguntar ao usuário.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

ENVS_JSON=$(python3 <<'PYEOF'
import json, os, re

wf_dir = ".github/workflows"
envs = []


def classify(text):
    t = text.lower()
    if "sandbox" in t:
        return "sandbox"
    if re.search(r"\bdevelop\b", t) or re.search(r"\bdev\b", t):
        return "sandbox"
    if "hml" in t or "homolog" in t:
        return "homolog"
    if "prod" in t:
        return "production"
    if re.search(r"\bmain\b", t) or re.search(r"\bmaster\b", t):
        return "production"
    return None


def extract_branches(text):
    branches = []
    in_branches = False
    branches_indent = None
    for line in text.splitlines():
        stripped = line.strip()
        m_key = re.match(r"^branches\s*:\s*(.*)$", stripped)
        if m_key:
            rest = m_key.group(1).strip()
            if rest.startswith("["):
                inline = rest.strip("[]")
                for part in inline.split(","):
                    part = part.strip().strip("'\"")
                    if part:
                        branches.append(part)
                in_branches = False
            elif rest == "":
                in_branches = True
                branches_indent = len(line) - len(line.lstrip())
            else:
                branches.append(rest.strip("'\""))
                in_branches = False
            continue
        if in_branches:
            m_item = re.match(r"^(\s*)-\s*(.+)$", line)
            if m_item and (branches_indent is None or len(m_item.group(1)) > branches_indent):
                branches.append(m_item.group(2).strip().strip("'\""))
                continue
            if stripped == "":
                continue
            in_branches = False
    return branches


# Workflows de CI puro (lint/test/typecheck/...) às vezes também disparam em push para
# main/master e não têm nada a ver com "para onde este repo faz deploy". Palavras-chave de
# ferramenta de deploy variam demais entre repos (gcloud/gke/kubectl num, um CLI interno
# próprio noutro) para servir de sinal positivo confiável — por isso a exclusão é por uma
# lista de bloqueio no `name:` do workflow, não por tentar reconhecer "isso parece deploy".
CI_NAME_SUBSTRINGS = (
    "lint", "test", "typecheck", "type check", "type-check",
    "format", "coverage", "e2e",
)


def looks_like_ci(name):
    n = name.lower()
    if any(s in n for s in CI_NAME_SUBSTRINGS):
        return True
    return bool(re.search(r"\bci\b", n))

if os.path.isdir(wf_dir):
    for fname in sorted(os.listdir(wf_dir)):
        if not (fname.endswith(".yml") or fname.endswith(".yaml")):
            continue
        path = os.path.join(wf_dir, fname)
        try:
            text = open(path, encoding="utf-8").read()
        except OSError:
            continue
        if "push:" not in text or "branches:" not in text:
            continue

        m_name = re.search(r"^name\s*:\s*(.+)$", text, re.MULTILINE)
        workflow_name = m_name.group(1).strip().strip("'\"") if m_name else fname
        if looks_like_ci(workflow_name):
            continue

        branches = extract_branches(text)

        stage_val = None
        m = re.search(r"^\s*(STAGE|ENVIRONMENT|ENV)\s*:\s*(\S+)", text, re.MULTILINE)
        if m:
            stage_val = m.group(2).strip("'\"")

        for b in branches:
            source = f"{fname} {stage_val or ''} {b}"
            kind = classify(source)
            envs.append({
                "workflow_file": fname,
                "branch": b,
                "stage_value": stage_val,
                "environment": kind or f"unknown:{fname}",
            })

print(json.dumps(envs))
PYEOF
)

REPO_INFO=$(gh repo view --json deleteBranchOnMerge,defaultBranchRef,nameWithOwner 2>/dev/null || echo '{}')
MERGED_PRS=$(gh pr list --state merged --limit 40 --json headRefName,baseRefName 2>/dev/null || echo '[]')

TEMPLATE_PATH=""
for candidate in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE/default.md; do
  if [ -f "$candidate" ]; then
    TEMPLATE_PATH="$candidate"
    break
  fi
done

python3 - "$ENVS_JSON" "$REPO_INFO" "$MERGED_PRS" "$TEMPLATE_PATH" "$REPO_ROOT" <<'PYEOF'
import json
import sys
from collections import defaultdict

envs = json.loads(sys.argv[1])
repo_info = json.loads(sys.argv[2]) if sys.argv[2] else {}
merged_prs = json.loads(sys.argv[3]) if sys.argv[3] else []
template_path = sys.argv[4] or None
repo_root = sys.argv[5]

env_words = set()
for e in envs:
    kind = e.get("environment", "")
    if not kind.startswith("unknown"):
        env_words.add(kind)
        env_words.add(e.get("branch", "").lower())
# Deliberadamente só palavras vindas dos ambientes DETECTADOS NESTE repo (não uma lista
# genérica fixa) — uma branch tipo "chore/decommission-gke-sandbox" não vira evidência de
# "per-environment" só por conter a palavra "sandbox" se este repo nem tem deploy de sandbox.

# Um head reaproveitado em bases diferentes é evidência de "shared" (uma branch, N PRs).
head_to_bases = defaultdict(set)
for pr in merged_prs:
    head = pr.get("headRefName")
    base = pr.get("baseRefName")
    if head and base:
        head_to_bases[head].add(base)
shared_examples = {h: sorted(b) for h, b in head_to_bases.items() if len(b) > 1}

# Um head cujo nome termina em -<palavra-de-ambiente> e que NUNCA foi reaproveitado
# noutra base é evidência de "per-environment" (branch nova por ambiente).
per_env_examples = {}
for head, bases in head_to_bases.items():
    if len(bases) > 1:
        continue
    suffix = head.rsplit("-", 1)[-1].lower() if "-" in head else ""
    if suffix in env_words:
        per_env_examples[head] = sorted(bases)

has_shared = bool(shared_examples)
has_per_env = bool(per_env_examples)

if not merged_prs:
    branch_style = "unknown"
elif has_shared and has_per_env:
    branch_style = "mixed"
elif has_shared:
    branch_style = "shared"
elif has_per_env:
    branch_style = "per-environment"
else:
    branch_style = "unknown"

result = {
    "repo_root": repo_root,
    "repo": repo_info.get("nameWithOwner"),
    "default_branch": (repo_info.get("defaultBranchRef") or {}).get("name"),
    "delete_branch_on_merge": repo_info.get("deleteBranchOnMerge"),
    "environments": envs,
    "branch_style": branch_style,
    "branch_style_evidence": {
        "shared": shared_examples or None,
        "per_environment": per_env_examples or None,
    },
    "pr_template": template_path,
}

print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF
