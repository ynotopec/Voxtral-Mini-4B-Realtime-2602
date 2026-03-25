#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-$(basename "$PWD")}"
MANAGE_SCRIPT="${PWD}/scripts/manage.sh"

if [[ ! -x "${MANAGE_SCRIPT}" ]]; then
  echo "Missing executable manage script: ${MANAGE_SCRIPT}" >&2
  exit 1
fi

"${MANAGE_SCRIPT}" uninstall "${PROJECT_NAME}"
