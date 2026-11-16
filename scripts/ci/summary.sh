#!/usr/bin/env bash
# Print the ci.yml run summary as Markdown: one row per stage, with links to every report.
#
# Reads:
#   NEEDS       the summary job's needs context, as JSON: ${{ toJSON(needs) }}
#   PR_NUMBER   the pull request number; empty on main
#   GITHUB_*    the default Actions variables
#
# Usage: scripts/ci/summary.sh >> "$GITHUB_STEP_SUMMARY"
set -euo pipefail

result() { jq -r --arg j "$1" '.[$j].result // "skipped"' <<<"$NEEDS"; }
out() { jq -r --arg j "$1" --arg k "$2" '.[$j].outputs[$k] // ""' <<<"$NEEDS"; }
icon() {
  case $(result "$1") in
    success) echo "✅" ;;
    failure) echo "❌" ;;
    cancelled) echo "⏹️" ;;
    *) echo "⏭️" ;;
  esac
}
link() { if [[ -n $2 ]]; then printf ' · [%s](%s)' "$1" "$2"; fi; }

security="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:?}/security/code-scanning"
if [[ -n ${PR_NUMBER:-} ]]; then
  security+="?query=is%3Aopen+pr%3A$PR_NUMBER"
fi

# Unit tests
tests=$(out test tests)
test_details="${tests:-–}"
if [[ -n $tests ]]; then
  test_details+=" · line coverage $(out test coverage)"
fi

# SonarQube Cloud
case $(out sonar gate) in
  passed | failed)
    sonar_details="quality gate $(out sonar gate) in $(out sonar seconds) s (target under 300 s)"
    sonar_details+=$(link dashboard "$(out sonar url)")
    ;;
  skipped) sonar_details="not analysed: SONAR_TOKEN is not available" ;;
  *) sonar_details="–" ;;
esac

# Image: Trivy, then where it went
if [[ $(result image) == skipped ]]; then
  image_details="not built: the unit tests did not pass"
else
  image_details="Trivy: $(out image critical) critical ($(out image fixable) fixable), $(out image high) high"
  image_details+=" · gate $(out image gate)$(link report "$(out image report)")"
  digest=$(out image digest)
  if [[ -n $digest ]]; then
    image_details+="<br>pushed \`$digest\`"
  else
    if [[ ${GITHUB_EVENT_NAME:-} == pull_request ]]; then
      why="pull request images stay on the runner"
    elif [[ ${GITHUB_REF:-} != refs/heads/main ]]; then
      why="only main is pushed"
    elif [[ $(out image gate) == failed ]]; then
      why="the Trivy gate failed"
    elif [[ $(out sonar gate) != passed ]]; then
      why="the quality gate did not pass"
    elif [[ $(out image registry_missing) == true ]]; then
      why="the registry does not exist yet: run the wake-up workflow"
    else
      why="the push did not complete"
    fi
    image_details+="<br>not pushed: $why"
  fi
fi

iac=$(out iac-scan findings)
version=$(out image version)

cat <<EOF
## CI${version:+ · v$version}

| Stage | Result | Details |
|---|---|---|
| Lint | $(icon lint) | ruff check and format |
| Unit tests | $(icon test) | $test_details |
| SonarQube Cloud | $(icon sonar) | $sonar_details |
| CodeQL | $(icon codeql) | Python and the workflows$(link "Security tab" "$security") |
| Trivy, Terraform | $(icon iac-scan) | ${iac:-–} HIGH/CRITICAL misconfigurations, report only$(link "Security tab" "$security") |
| Image | $(icon image) | $image_details |
EOF
