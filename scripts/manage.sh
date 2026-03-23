#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-help}"
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

start_process() {
  local name="$1"
  local pid_file="$2"
  local log_file="$3"
  shift 3

  mkdir -p "${PID_DIR}"
  if is_running "${pid_file}"; then
    echo "${name} already running (pid $(cat "${pid_file}"))"
    return
  fi

  nohup "$@" > "${log_file}" 2>&1 &
  echo $! > "${pid_file}"
  echo "Started ${name} pid $(cat "${pid_file}")"
}

start_vllm() {
  local realtime_port="${REALTIME_PORT:-9000}"
  local model_id="${MODEL_ID:-mistralai/Voxtral-Mini-4B-Realtime-2602}"
  local device="${DEVICE:-cuda:0}"

  start_process "vLLM" "${VLLM_PID_FILE}" "${PID_DIR}/vllm.log" \
    "${VENV_DIR}/bin/vllm" serve "${model_id}" --port "${realtime_port}" --device "${device}"
}

start_api() {
  local host="${HOST:-0.0.0.0}"
  local port="${PORT:-8000}"

  [[ -n "${UP_IP}" ]] && host="${UP_IP}"
  [[ -n "${UP_PORT}" ]] && port="${UP_PORT}"

  start_process "API" "${API_PID_FILE}" "${PID_DIR}/api.log" \
    env HOST="${host}" PORT="${port}" REALTIME_PORT="${REALTIME_PORT:-9000}" \
    "${VENV_DIR}/bin/python" main.py

  echo "API available on ${host}:${port}"
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

print_service_status() {
  local name="$1"
  local pid_file="$2"
  local log_file="$3"

  if is_running "${pid_file}"; then
    echo "${name}: running (pid $(cat "${pid_file}"))"
  elif [[ -f "${pid_file}" ]]; then
    echo "${name}: stale pid file ($(cat "${pid_file}"))"
  else
    echo "${name}: stopped"
  fi

  if [[ -f "${log_file}" ]]; then
    echo "  log: ${log_file}"
  fi
}

status() {
  print_service_status "api" "${API_PID_FILE}" "${PID_DIR}/api.log"
  print_service_status "vllm" "${VLLM_PID_FILE}" "${PID_DIR}/vllm.log"
}

logs() {
  local service="${1:-all}"
  case "${service}" in
    api)
      tail -n 80 "${PID_DIR}/api.log"
      ;;
    vllm)
      tail -n 80 "${PID_DIR}/vllm.log"
      ;;
    all)
      echo "=== api.log ==="
      [[ -f "${PID_DIR}/api.log" ]] && tail -n 40 "${PID_DIR}/api.log" || echo "(missing)"
      echo
      echo "=== vllm.log ==="
      [[ -f "${PID_DIR}/vllm.log" ]] && tail -n 40 "${PID_DIR}/vllm.log" || echo "(missing)"
      ;;
    *)
      echo "Unknown service '${service}'. Use: api|vllm|all" >&2
      exit 1
      ;;
  esac
}

usage() {
  cat <<'EOT'
Usage: scripts/manage.sh <action> [project_name] [ip] [port]

Actions:
  install   Create venv, bootstrap .env, and install dependencies
  up        Start vLLM + API
  down      Stop API + vLLM
  restart   Restart API + vLLM
  upgrade   Upgrade dependencies
  status    Show process and log status
  logs      Show logs (pass api|vllm|all as arg #3)
  help      Show this help
EOT
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
  restart)
    stop_from_pid_file "api" "${API_PID_FILE}"
    stop_from_pid_file "vllm" "${VLLM_PID_FILE}"
    create_venv
    read_env
    start_vllm
    start_api
    ;;
  upgrade)
    create_venv
    ensure_env_file
    "${UV_BIN}" pip install --python "${VENV_DIR}/bin/python" --upgrade -r requirements.txt
    ;;
  status)
    status
    ;;
  logs)
    logs "${3:-all}"
    ;;
  help|*)
    usage
    [[ "${ACTION}" == "help" ]] || exit 1
    ;;
esac
