#!/usr/bin/env bash
# Send a test email through Azure Communication Services to the notification address.
#
# Usage: core/scripts/ops/send-test-email.sh
#
# The address comes from $NOTIFY_EMAIL or, if that is unset, from the git-ignored
# core/infra/notify.auto.tfvars. It is never printed. The connection string is read at run
# time and passed through the environment, so it never appears on a command line or on disk.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RG=rg-nebo-core
TFVARS="$REPO_ROOT/core/infra/notify.auto.tfvars"

to=${NOTIFY_EMAIL:-}
if [[ -z $to && -f $TFVARS ]]; then
  to=$(sed -n 's/^[[:space:]]*notify_email[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$TFVARS")
fi
if [[ -z $to ]]; then
  echo "No address: set NOTIFY_EMAIL or create core/infra/notify.auto.tfvars" >&2
  exit 1
fi

acs=$(az communication list -g "$RG" --query "[0].name" -o tsv)
sender=$(terraform -chdir="$REPO_ROOT/core/infra" output -raw acs_sender)
AZURE_COMMUNICATION_CONNECTION_STRING=$(az communication list-key -n "$acs" -g "$RG" \
  --query primaryConnectionString -o tsv)
export AZURE_COMMUNICATION_CONNECTION_STRING

az communication email send --sender "$sender" --to "$to" \
  --subject "[NEBo][test] Email from Azure Communication Services" \
  --text "This is a test message from the NEBo core stack. If it reached your spam folder, add a filter that keeps messages whose subject starts with [NEBo]." \
  --only-show-errors -o none

echo "Sent from $sender to the notification address. Check the inbox and the spam folder."
