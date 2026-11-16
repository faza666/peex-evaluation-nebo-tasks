#!/usr/bin/env bash
# Scan the Terraform code with Trivy and apply the CI gate.
#
# Writes, in the current directory:
#   trivy-iac.json   the full report
#   trivy-iac.sarif  HIGH and CRITICAL findings, for the Security tab
# prints the HIGH and CRITICAL findings, then fails when there is a finding at a severity
# listed in FAIL_ON (comma-separated, default HIGH,CRITICAL; "none" reports only).
# To accept a finding on purpose, put "#trivy:ignore:<ID>" with the reason above the resource.
# GitHub Actions outputs: findings (HIGH and CRITICAL), gate (passed|failed|off).
#
# Usage: [FAIL_ON=CRITICAL] scripts/ci/trivy-iac.sh [directory, default infra]
set -euo pipefail

dir=${1:-infra}
fail_on=${FAIL_ON:-HIGH,CRITICAL}
fail_on=${fail_on^^}

trivy config --quiet --format json --output trivy-iac.json "$dir"
trivy convert --quiet --format sarif --severity HIGH,CRITICAL --output trivy-iac.sarif trivy-iac.json
trivy convert --quiet --scanners misconfig --format table --severity HIGH,CRITICAL trivy-iac.json

# count <comma-separated severities>
count() {
  jq --arg sev "$1" \
    '[.Results[]?.Misconfigurations[]? | select(.Severity as $s | $sev | split(",") | index($s))] | length' \
    trivy-iac.json
}

findings=$(count HIGH,CRITICAL)
if [[ $fail_on == NONE ]]; then
  gate=off
  blocking=0
else
  blocking=$(count "$fail_on")
  if ((blocking > 0)); then gate=failed; else gate=passed; fi
fi

echo "Trivy, Terraform: $findings HIGH/CRITICAL misconfiguration(s). Gate on $fail_on: $gate."
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'findings=%s\ngate=%s\n' "$findings" "$gate" >>"$GITHUB_OUTPUT"
fi

if [[ $gate == failed ]]; then
  echo "::error title=Trivy IaC gate::$blocking $fail_on misconfiguration(s) in $dir/." \
    "Fix them, or accept one on purpose with a #trivy:ignore:<ID> comment that says why."
  exit 1
fi
