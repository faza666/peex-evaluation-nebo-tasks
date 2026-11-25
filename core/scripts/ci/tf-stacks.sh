#!/usr/bin/env bash
# Which Terraform stacks a terraform.yml run covers, as a JSON matrix.
#
# A stack is core/infra (stack "core") or a stage folder's infra-<name>/ (stack "<name>"), once it holds .tf
# files. Its GitHub environment is "core", or the stage of its folder (stage-a, stage-b, stage-c): every stack of
# a stage shares that stage's resource group and its deployer, whose client ID is the repository variable
# AZURE_CLIENT_ID_<DEPLOYER> (CORE, STAGE_A, ...). core/identities and core/rbac are not stacks here.
#
# Usage:
#   tf-stacks.sh changed <base> <head> [all-on-shared]   stacks with files changed between two commits; with
#                                                        all-on-shared, every stack when a shared file changed
#   tf-stacks.sh one <name>                              one stack, by name
# Prints [{stack, dir, environment, deployer}] and, in Actions, writes the outputs stacks (that JSON) and count.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Files every stack's checks depend on.
SHARED='^(\.tflint\.hcl|core/scripts/ci/(tf-[^/]*|trivy-iac\.sh)|\.github/actions/setup-(tflint|trivy)/.*|\.github/workflows/terraform\.yml)$'

all_stacks() {
  local dirs=() d
  compgen -G "core/infra/*.tf" >/dev/null && dirs+=(core/infra)
  for d in stage-*/*/infra-*/; do
    d=${d%/}
    compgen -G "$d/*.tf" >/dev/null && dirs+=("$d")
  done
  ((${#dirs[@]})) || { echo "[]"; return; }
  printf '%s\n' "${dirs[@]}" | jq -R -s -c '
    split("\n") | map(select(. != "")) | map(
      . as $dir
      | (if $dir == "core/infra" then "core" else ($dir | split("/")[-1] | ltrimstr("infra-")) end) as $stack
      | (if $dir == "core/infra" then "core" else ($dir | capture("^(?<s>stage-[abc])-").s) end) as $env
      | {stack: $stack, dir: $dir, environment: $env, deployer: ($env | ascii_upcase | gsub("-"; "_"))})'
}

stacks=$(all_stacks)
dupes=$(jq -r 'group_by(.stack) | map(select(length > 1) | .[0].stack) | .[]' <<<"$stacks")
if [[ -n $dupes ]]; then
  echo "::error title=Duplicate stack names::Two infra-<name>/ folders share a name: $dupes" >&2
  exit 1
fi

case ${1:-} in
  one)
    name=${2:?usage: tf-stacks.sh one <name>}
    selected=$(jq -c --arg n "$name" 'map(select(.stack == $n))' <<<"$stacks")
    if [[ $selected == "[]" ]]; then
      echo "::error title=No such stack::'$name' is not a stack. Known: $(jq -r 'map(.stack) | join(", ")' <<<"$stacks")." >&2
      exit 1
    fi
    ;;
  changed)
    base=${2:?usage: tf-stacks.sh changed <base> <head> [all-on-shared]}
    head=${3:?usage: tf-stacks.sh changed <base> <head> [all-on-shared]}
    if [[ $base =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
      changed=$(git ls-files) # no usable base (a new branch, or history that was rewritten): treat all as changed
    else
      changed=$(git diff --name-only "$base" "$head")
    fi
    if [[ ${4:-} == all-on-shared ]] && grep -Eq "$SHARED" <<<"$changed"; then
      selected=$stacks
    else
      selected=$(jq -c --arg files "$changed" '
        ($files | split("\n")) as $f
        | map(. as $s | select(any($f[]; startswith($s.dir + "/"))))' <<<"$stacks")
    fi
    ;;
  *)
    sed -n '10,13s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac

jq . <<<"$selected"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'stacks=%s\ncount=%s\n' "$(jq -c . <<<"$selected")" "$(jq length <<<"$selected")" >>"$GITHUB_OUTPUT"
fi
