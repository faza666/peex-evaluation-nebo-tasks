#!/usr/bin/env bash
# Check that the tools a NEBo stage needs are installed, and print their versions.
#
# Usage: core/scripts/ops/check-tools.sh A|B|C
#
# Stages are cumulative: B also checks the Stage A tools, because later stages reuse
# them (for example, the Ansible role runs again in Stage B).
# Exit code: 0 when every required tool is present, 1 otherwise. Optional tools only warn.
set -uo pipefail

usage() {
  echo "Usage: $0 A|B|C" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
stage=$(tr '[:lower:]' '[:upper:]' <<<"$1")
[[ $stage =~ ^[ABC]$ ]] || usage

missing=0
warnings=0

# check <required|optional> <name> <command printing the version>
check() {
  local level=$1 name=$2 cmd=$3 out
  if out=$(timeout 30 bash -c "$cmd" 2>&1) && [[ -n $out ]]; then
    printf '  %-8s %-34s %s\n' "OK" "$name" "$(head -n1 <<<"$out" | cut -c1-70)"
  elif [[ $level == required ]]; then
    printf '  %-8s %-34s %s\n' "MISSING" "$name" "($cmd)"
    missing=$((missing + 1))
  else
    printf '  %-8s %-34s %s\n' "WARN" "$name" "optional, not found"
    warnings=$((warnings + 1))
  fi
}

# condition <required|optional> <name> <command that must succeed> <description shown when OK>
condition() {
  local level=$1 name=$2 cmd=$3 ok_text=$4
  if timeout 30 bash -c "$cmd" >/dev/null 2>&1; then
    printf '  %-8s %-34s %s\n' "OK" "$name" "$ok_text"
  elif [[ $level == required ]]; then
    printf '  %-8s %-34s %s\n' "MISSING" "$name" "($cmd)"
    missing=$((missing + 1))
  else
    printf '  %-8s %-34s %s\n' "WARN" "$name" "optional, not met"
    warnings=$((warnings + 1))
  fi
}

echo "Base toolchain"
check required "git" "git --version"
check required "gh" "gh --version"
check required "az" "az version --query '\"azure-cli\"' -o tsv"
check required "terraform" "terraform version | head -n1"
check optional "tflint" "tflint --version"
check required "jq" "jq --version"
check required "curl" "curl --version"
check required "openssl" "openssl version"
check required "ssh" "ssh -V"
check required "dig" "dig -v"
check required "python3" "python3 --version"
condition required "python3 venv module" "python3 -c 'import venv'" "available"
check required "pipx" "pipx --version"
check required "docker" "docker version --format 'server {{.Server.Version}}'"
check required "docker buildx" "docker buildx version"
check required "shellcheck" "shellcheck --version | sed -n 2p"
check required "script (util-linux)" "script --version"

if [[ $stage =~ [ABC] ]]; then
  echo "Stage A: delivery and configuration"
  check required "trivy" "trivy --version"
  check required "actionlint" "actionlint --version"
  check required "ansible" "ansible --version"
  check required "ansible-lint" "ansible-lint --version"
  check required "yamllint" "yamllint --version"
  check required "molecule" "molecule --version"
  check required "collection community.docker" \
    "ansible-galaxy collection list community.docker 2>/dev/null | grep -E '^community\.docker'"
  check optional "collection azure.azcollection" \
    "ansible-galaxy collection list azure.azcollection 2>/dev/null | grep -E '^azure\.azcollection'"
  for ext in resource-graph communication containerapp; do
    check required "az extension $ext" "az extension show -n $ext --query version -o tsv"
  done
  condition required "gh token has 'project' scope" "gh auth status 2>&1 | grep -q \"'project'\"" \
    "gh project commands work"
  condition required "gh supports sub-issues" "gh issue create --help | grep -q -- '--parent'" \
    "gh issue create --parent"
fi

if [[ $stage =~ [BC] ]]; then
  echo "Stage B: container operations on AKS"
  check required "kubectl" "kubectl version --client -o json | jq -r .clientVersion.gitVersion"
  check required "kubelogin" "kubelogin --version | grep -m1 -oE 'v[0-9]+\.[0-9]+\.[0-9]+'"
  check required "helm" "helm version --short"
  check required "kubeconform" "kubeconform -v"
  check optional "k9s" "k9s version --short | awk '/Version/ {print \$2}'"
  check required "psql" "psql --version"
  check optional "pwsh" "pwsh --version"
fi

if [[ $stage == C ]]; then
  echo "Stage C: container networking"
  check required "istioctl" "istioctl version --remote=false"
  check required "k6" "k6 version"
  check required "certbot" "certbot --version"
  condition required "certbot dns-cloudflare plugin" "python3 -c 'import certbot_dns_cloudflare'" "installed"
fi

echo
if ((missing > 0)); then
  echo "Stage $stage: $missing required tool(s) missing, $warnings warning(s)."
  exit 1
fi
echo "Stage $stage: all required tools present ($warnings warning(s))."
