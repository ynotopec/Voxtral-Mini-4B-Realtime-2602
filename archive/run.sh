#!/usr/bin/env bash
set -euo pipefail

HOST_OVERRIDE="${1:-}"
PORT_OVERRIDE="${2:-}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PWD")}" 
MANAGE_SCRIPT="${PWD}/scripts/manage.sh"

if [[ ! -x "${MANAGE_SCRIPT}" ]]; then
  echo "Missing executable manage script: ${MANAGE_SCRIPT}" >&2
  exit 1
fi

cleanup() {
  "${MANAGE_SCRIPT}" down "${PROJECT_NAME}" || true
}

trap cleanup EXIT INT TERM

"${MANAGE_SCRIPT}" up "${PROJECT_NAME}" "${HOST_OVERRIDE}" "${PORT_OVERRIDE}"

VLLM_PID_FILE="${PWD}/.run/vllm.pid"

while true; do
  if [[ ! -f "${VLLM_PID_FILE}" ]]; then
    echo "Missing pid file; expected ${VLLM_PID_FILE}" >&2
    exit 1
  fi

  vllm_pid="$(cat "${VLLM_PID_FILE}")"

  if ! kill -0 "${vllm_pid}" >/dev/null 2>&1; then
    echo "vLLM process ${vllm_pid} is no longer running" >&2
    exit 1
  fi

  sleep 5
done
