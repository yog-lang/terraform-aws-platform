#!/usr/bin/env bash
###############################################################################
# drift-check.sh - detect drift in one environment.
#
# Usage (from repo root):
#   ./scripts/drift-check.sh dev
#   ./scripts/drift-check.sh prod
#
# How it works:
#   terraform plan -refresh-only asks AWS "what does it look like right now?"
#   and compares that to the state file. It does NOT look at code changes,
#   only at changes made OUTSIDE Terraform (console clicks, scripts, etc.).
#
#   -detailed-exitcode gives us a machine-readable answer:
#       0 = no drift
#       1 = error
#       2 = drift found
###############################################################################
set -uo pipefail

ENVIRONMENT="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_DIR="$ROOT_DIR/envs/$ENVIRONMENT"
REPORT="$ROOT_DIR/drift-report.txt"

if [[ ! -d "$ENV_DIR" ]]; then
  echo "No such environment: $ENVIRONMENT" >&2
  exit 1
fi

cd "$ENV_DIR"

echo ">> Checking drift in '$ENVIRONMENT'..."
terraform plan -refresh-only -detailed-exitcode -input=false -no-color -lock=false > "$REPORT" 2>&1
CODE=$?

case "$CODE" in
  0)
    echo "OK: no drift in $ENVIRONMENT."
    ;;
  2)
    echo "DRIFT DETECTED in $ENVIRONMENT. Details:"
    echo "--------------------------------------------------------------"
    cat "$REPORT"
    echo "--------------------------------------------------------------"
    echo "Full report: $REPORT"
    echo
    echo "Your options:"
    echo "  a) Code is right, revert AWS:       cd envs/$ENVIRONMENT && terraform apply"
    echo "  b) AWS is right, accept into state: cd envs/$ENVIRONMENT && terraform apply -refresh-only"
    echo "     (then update the .tf code to match, or the next apply will undo it)"
    ;;
  *)
    echo "ERROR running terraform plan (exit $CODE). See $REPORT" >&2
    ;;
esac

exit "$CODE"
