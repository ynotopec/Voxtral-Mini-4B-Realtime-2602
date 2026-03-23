#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
PROJECT_NAME="${2:-$(basename "$PWD")}"
UP_IP="${3:-}"
UP_PORT="${4:-}"

VENV_DIR="${HOME}/venv/${PROJECT_NAME}"
UV_BIN="${UV_BIN:-uv}"
ENV_FILE=".env"
ENV_EXAMPLE_FILE=".env.example"
PID_DIR=".run"
VLLM_PID_FILE="${PID_DIR}/vllm.pid"
API_PID_FILE="${PID_DIR}/api.pid"

ensure_uv() {
  if ! command -v "${UV_BIN}" >/dev/null 2>&1; then
    echo "uv is required but not found. Install from https://docs.astral.sh/uv/" >&2
    exit 1
  fi
}

create_venv() {
  ensure_uv
  if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    "${UV_BIN}" venv "${VENV_DIR}"
  fi
}

ensure_env_example() {
  if [[ ! -f "${ENV_EXAMPLE_FILE}" ]]; then
    cat > "${ENV_EXAMPLE_FILE}" <<'EOT'
HOST=0.0.0.0
PORT=8000
REALTIME_PORT=9000
MODEL_ID=mistralai/Voxtral-Mini-4B-Realtime-2602
DEVICE=cuda:0
EOT
  fi
}

ensure_env_file() {
  ensure_env_example
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
  fi
}

install_deps() {
  "${VENV_DIR}/bin/python" -m pip install --upgrade pip
  "${UV_BIN}" pip install --python "${VENV_DIR}/bin/python" -r requirements.txt
}

read_env() {
  ensure_env_file
  set -a
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
  set +a
}

is_running() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] || return 1
  local pid
  pid="$(cat "${pid_file}")"
  kill -0 "${pid}" >/dev/null 2>&1
}

start_vllm() {
  local realtime_port="${REALTIME_PORT:-9000}"
  local model_id="${MODEL_ID:-mistralai/Voxtral-Mini-4B-Realtime-2602}"
  local device="${DEVICE:-cuda:0}"

  mkdir -p "${PID_DIR}"
  if is_running "${VLLM_PID_FILE}"; then
    echo "vLLM already running (pid $(cat "${VLLM_PID_FILE}"))"
    return
  fi

  nohup "${VENV_DIR}/bin/vllm" serve "${model_id}" --port "${realtime_port}" --device "${device}" > "${PID_DIR}/vllm.log" 2>&1 &
  echo $! > "${VLLM_PID_FILE}"
  echo "Started vLLM pid $(cat "${VLLM_PID_FILE}")"
}

start_api() {
  local host="${HOST:-0.0.0.0}"
  local port="${PORT:-8000}"

  if [[ -n "${UP_IP}" ]]; then
    host="${UP_IP}"
  fi
  if [[ -n "${UP_PORT}" ]]; then
    port="${UP_PORT}"
  fi

  mkdir -p "${PID_DIR}"
  if is_running "${API_PID_FILE}"; then
    echo "API already running (pid $(cat "${API_PID_FILE}"))"
    return
  fi

  nohup env HOST="${host}" PORT="${port}" REALTIME_PORT="${REALTIME_PORT:-9000}" "${VENV_DIR}/bin/python" main.py > "${PID_DIR}/api.log" 2>&1 &
  echo $! > "${API_PID_FILE}"
  echo "Started API pid $(cat "${API_PID_FILE}") on ${host}:${port}"
}

stop_from_pid_file() {
  local name="$1"
  local pid_file="$2"

  if ! [[ -f "${pid_file}" ]]; then
    echo "${name} is not running (no pid file)"
    return
  fi

  local pid
  pid="$(cat "${pid_file}")"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}"
    echo "Stopped ${name} pid ${pid}"
  else
    echo "${name} pid ${pid} is stale"
  fi
  rm -f "${pid_file}"
}

case "${ACTION}" in
  install)
    create_venv
    ensure_env_file
    install_deps
    ;;
  up)
    create_venv
    read_env
    start_vllm
    start_api
    ;;
  down)
    stop_from_pid_file "api" "${API_PID_FILE}"
    stop_from_pid_file "vllm" "${VLLM_PID_FILE}"
    ;;
  upgrade)
    create_venv
    ensure_env_file
    "${UV_BIN}" pip install --python "${VENV_DIR}/bin/python" --upgrade -r requirements.txt
    ;;
  *)
    echo "Usage: $0 {install|up|down|upgrade} [project_name] [ip] [port]" >&2
    exit 1
    ;;
esac
