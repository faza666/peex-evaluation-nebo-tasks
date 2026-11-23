#!/usr/bin/env bash
# Scan a container image with Trivy and apply the CI gate.
#
# Writes, in the current directory:
#   trivy-image.json   the full report
#   trivy-image.sarif  HIGH and CRITICAL findings, for the Security tab
#   trivy-image.txt    a readable table of every finding
# Then fails when the image has a *fixable* finding at a severity listed in FAIL_ON
# (comma-separated, default CRITICAL; "none" reports only). Findings without a fixed version
# never fail the build, because there is nothing to upgrade to yet.
# GitHub Actions outputs: critical, high, fixable (fixable CRITICAL), gate (passed|failed|off).
#
# Usage: [FAIL_ON=CRITICAL,HIGH] core/scripts/ci/trivy-image.sh <image>
set -euo pipefail

image=${1:?Usage: $0 <image>}
fail_on=${FAIL_ON:-CRITICAL}
fail_on=${fail_on^^}

trivy image --quiet --scanners vuln --format json --output trivy-image.json "$image"
trivy convert --quiet --format sarif --severity HIGH,CRITICAL --output trivy-image.sarif trivy-image.json
trivy convert --quiet --scanners vuln --format table --output trivy-image.txt trivy-image.json

# count <jq condition on one vulnerability>
count() { jq "[.Results[]?.Vulnerabilities[]? | select($1)] | length" trivy-image.json; }
fixed='(.FixedVersion // "") != ""'

critical=$(count '.Severity == "CRITICAL"')
high=$(count '.Severity == "HIGH"')
fixable=$(count ".Severity == \"CRITICAL\" and $fixed")

if [[ $fail_on == NONE ]]; then
  gate=off
  blocking=0
else
  blocking=$(jq --arg sev "$fail_on" \
    "[.Results[]?.Vulnerabilities[]? | select((.Severity as \$s | \$sev | split(\",\") | index(\$s)) and $fixed)] | length" \
    trivy-image.json)
  if ((blocking > 0)); then gate=failed; else gate=passed; fi
fi

echo "Trivy: $critical critical ($fixable fixable), $high high. Gate on fixable $fail_on: $gate."
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'critical=%s\nhigh=%s\nfixable=%s\ngate=%s\n' "$critical" "$high" "$fixable" "$gate" >>"$GITHUB_OUTPUT"
fi

if [[ $gate == failed ]]; then
  echo "::error title=Trivy gate::$blocking fixable $fail_on finding(s) in $image." \
    "Upgrade the affected packages or the base image; the full list is in the trivy-image-report artifact."
  trivy convert --quiet --scanners vuln --format table --severity "$fail_on" trivy-image.json
  exit 1
fi
