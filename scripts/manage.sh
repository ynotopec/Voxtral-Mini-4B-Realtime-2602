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
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
SYSTEMD_UNIT_FILE="${SYSTEMD_SYSTEM_DIR}/${PROJECT_NAME}.service"
SYSTEMD_USER_NAME="${USER:-$(id -un)}"

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

  if ! "${VENV_DIR}/bin/python" -m pip --version >/dev/null 2>&1; then
    "${VENV_DIR}/bin/python" -m ensurepip --upgrade
  fi
}

ensure_env_example() {
  if [[ ! -f "${ENV_EXAMPLE_FILE}" ]]; then
    cat > "${ENV_EXAMPLE_FILE}" <<'EOT'
HOST=0.0.0.0
PORT=8000
MODEL_ID=mistralai/Voxtral-Mini-4B-Realtime-2602
DEVICE=cuda:0
VLLM_API_KEY=
SYSTEMD_USER=
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

ensure_pyairports_module() {
  if "${VENV_DIR}/bin/python" -c "import pyairports.airports" >/dev/null 2>&1; then
    return
  fi

  echo "pyairports import still missing; installing a compatibility stub in venv..."
  "${VENV_DIR}/bin/python" - <<'PY'
from pathlib import Path
import sysconfig

purelib = Path(sysconfig.get_paths()["purelib"])
pkg_dir = purelib / "pyairports"
pkg_dir.mkdir(parents=True, exist_ok=True)

(pkg_dir / "__init__.py").write_text(
    "from .airports import AIRPORT_LIST\n",
    encoding="utf-8",
)
(pkg_dir / "airports.py").write_text(
    "AIRPORT_LIST = []\n",
    encoding="utf-8",
)
PY
}

ensure_runtime_deps() {
  if ! "${VENV_DIR}/bin/python" -c "import vllm" >/dev/null 2>&1; then
    echo "Missing runtime dependencies; installing from requirements.txt..."
    install_deps
  fi

  ensure_pyairports_module
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
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" >/dev/null 2>&1 || return 1

  # Ensure the pid belongs to a vLLM serve process, not an unrelated reused pid.
  is_vllm_server_pid "${pid}"
}

is_vllm_server_pid() {
  local pid="$1"
  local cmdline
  cmdline="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"

  # Started via CLI: "vllm serve <model>"
  if [[ "${cmdline}" == *"vllm"* && "${cmdline}" == *" serve "* ]]; then
    return 0
  fi

  # Some launches re-exec as a python module.
  if [[ "${cmdline}" == *"vllm.entrypoints.openai.api_server"* ]]; then
    return 0
  fi

  return 1
}

find_vllm_descendant_pid() {
  local parent_pid="$1"
  local child
  local children_file="/proc/${parent_pid}/task/${parent_pid}/children"
  [[ -r "${children_file}" ]] || return 1

  # shellcheck disable=SC2207
  local children=($(cat "${children_file}"))
  for child in "${children[@]}"; do
    [[ -n "${child}" ]] || continue
    if is_vllm_server_pid "${child}"; then
      echo "${child}"
      return 0
    fi
    if find_vllm_descendant_pid "${child}" >/dev/null 2>&1; then
      find_vllm_descendant_pid "${child}"
      return 0
    fi
  done

  return 1
}

find_running_vllm_pid() {
  local pid
  for pid in /proc/[0-9]*; do
    pid="${pid#/proc/}"
    if is_vllm_server_pid "${pid}"; then
      echo "${pid}"
      return 0
    fi
  done
  return 1
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
  local host="${HOST:-0.0.0.0}"
  local port="${PORT:-8000}"
  local model_id="${MODEL_ID:-mistralai/Voxtral-Mini-4B-Realtime-2602}"
  local device="${DEVICE:-cuda:0}"
  local api_key="${VLLM_API_KEY:-}"

  [[ -n "${UP_IP}" ]] && host="${UP_IP}"
  [[ -n "${UP_PORT}" ]] && port="${UP_PORT}"

  local cmd=("${VENV_DIR}/bin/vllm" serve "${model_id}" --host "${host}" --port "${port}" --device "${device}")
  if [[ -n "${api_key}" ]]; then
    cmd+=(--api-key "${api_key}")
  fi

  start_process "vLLM" "${VLLM_PID_FILE}" "${PID_DIR}/vllm.log" "${cmd[@]}"

  # Validate that the process survives initial startup before claiming availability.
  local pid
  pid="$(cat "${VLLM_PID_FILE}")"
  local resolved_pid="${pid}"
  local tries=0
  while (( tries < 10 )); do
    if find_vllm_descendant_pid "${pid}" >/dev/null 2>&1; then
      resolved_pid="$(find_vllm_descendant_pid "${pid}")"
      if [[ "${resolved_pid}" != "$(cat "${VLLM_PID_FILE}")" ]]; then
        echo "${resolved_pid}" > "${VLLM_PID_FILE}"
      fi
    fi

    if is_running "${VLLM_PID_FILE}"; then
      echo "vLLM available on ${host}:${port}"
      return 0
    fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
    tries=$((tries + 1))
  done

  echo "vLLM failed to stay running during startup. Check ${PID_DIR}/vllm.log for details." >&2
  [[ -f "${PID_DIR}/vllm.log" ]] && tail -n 40 "${PID_DIR}/vllm.log" >&2 || true
  rm -f "${VLLM_PID_FILE}"
  return 1
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

status() {
  if is_running "${VLLM_PID_FILE}"; then
    echo "vllm: running (pid $(cat "${VLLM_PID_FILE}"))"
  elif find_running_vllm_pid >/dev/null 2>&1; then
    local detected_pid
    detected_pid="$(find_running_vllm_pid)"
    echo "vllm: running (pid ${detected_pid}, discovered from process table; pid file missing or stale)"
  elif [[ -f "${VLLM_PID_FILE}" ]]; then
    echo "vllm: stale pid file ($(cat "${VLLM_PID_FILE}"))"
  else
    echo "vllm: stopped"
  fi

  if [[ -f "${PID_DIR}/vllm.log" ]]; then
    echo "  log: ${PID_DIR}/vllm.log"
  fi
}

logs() {
  tail -n 80 "${PID_DIR}/vllm.log"
}

usage() {
  cat <<'EOT'
Usage: scripts/manage.sh <action> [project_name] [ip] [port]

Actions:
  install   Create venv, bootstrap .env, and install dependencies
  uninstall Stop services and remove local runtime artifacts (venv, pid/logs, systemd unit)
  up        Start vLLM OpenAI-compatible server
  down      Stop vLLM
  restart   Restart vLLM
  upgrade   Upgrade dependencies
  status    Show vLLM process and log status
  logs      Show vLLM logs
  systemd-install   Install and start a systemd service in /etc/systemd/system (uses [ip] [port] if provided)
  systemd-remove    Stop and remove the systemd service from /etc/systemd/system
  help      Show this help
EOT
}

uninstall_all() {
  stop_from_pid_file "vllm" "${VLLM_PID_FILE}" || true

  # Remove systemd user unit if present (best effort).
  if command -v systemctl >/dev/null 2>&1; then
    remove_systemd_user_service || true
  fi

  rm -rf "${PID_DIR}" "${VENV_DIR}"
  echo "Removed runtime directory: ${PID_DIR}"
  echo "Removed virtual environment: ${VENV_DIR}"
}

ensure_systemd_user_ready() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is required but not found on this machine." >&2
    exit 1
  fi
}

resolve_systemd_paths() {
  local target_user="${SYSTEMD_USER:-}"
  if [[ -z "${target_user}" ]]; then
    target_user="${USER:-$(id -un)}"
  fi

  if ! id -u "${target_user}" >/dev/null 2>&1; then
    echo "Could not resolve SYSTEMD_USER=${target_user}" >&2
    exit 1
  fi

  SYSTEMD_USER_NAME="${target_user}"
  SYSTEMD_UNIT_FILE="${SYSTEMD_SYSTEM_DIR}/${PROJECT_NAME}.service"
}

systemctl_user_cmd() {
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl "$@"
    return
  fi

  echo "sudo is required to manage systemd services in ${SYSTEMD_SYSTEM_DIR}." >&2
  exit 1
}

install_systemd_user_service() {
  ensure_systemd_user_ready
  create_venv
  read_env
  resolve_systemd_paths

  local host="${HOST:-0.0.0.0}"
  local port="${PORT:-8000}"

  [[ -n "${UP_IP}" ]] && host="${UP_IP}"
  [[ -n "${UP_PORT}" ]] && port="${UP_PORT}"

  mkdir -p "${PID_DIR}"

  local tmp_unit_file
  tmp_unit_file="$(mktemp)"

  cat > "${tmp_unit_file}" <<EOT
[Unit]
Description=${PROJECT_NAME} vLLM OpenAI-compatible server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SYSTEMD_USER_NAME}
WorkingDirectory=${PWD}
ExecStart=${PWD}/scripts/manage.sh up ${PROJECT_NAME} ${host} ${port}
ExecStop=${PWD}/scripts/manage.sh down ${PROJECT_NAME}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT

  if command -v sudo >/dev/null 2>&1; then
    sudo install -m 0644 "${tmp_unit_file}" "${SYSTEMD_UNIT_FILE}"
  else
    rm -f "${tmp_unit_file}"
    echo "sudo is required to install ${SYSTEMD_UNIT_FILE}" >&2
    exit 1
  fi
  rm -f "${tmp_unit_file}"

  systemctl_user_cmd daemon-reload
  systemctl_user_cmd enable --now "${PROJECT_NAME}.service"

  echo "Installed and started systemd service: ${PROJECT_NAME}.service (runs as user: ${SYSTEMD_USER_NAME})"
  echo "Host/port configured: ${host}:${port}"
  echo "Unit file: ${SYSTEMD_UNIT_FILE}"
}

remove_systemd_user_service() {
  ensure_systemd_user_ready
  read_env
  resolve_systemd_paths

  if systemctl_user_cmd list-unit-files | awk '{print $1}' | grep -qx "${PROJECT_NAME}.service"; then
    systemctl_user_cmd disable --now "${PROJECT_NAME}.service" || true
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo rm -f "${SYSTEMD_UNIT_FILE}"
  else
    echo "sudo is required to remove ${SYSTEMD_UNIT_FILE}" >&2
    exit 1
  fi
  systemctl_user_cmd daemon-reload
  systemctl_user_cmd reset-failed
  echo "Removed systemd service: ${PROJECT_NAME}.service"
}

case "${ACTION}" in
  install)
    create_venv
    ensure_env_file
    install_deps
    ;;
  uninstall)
    uninstall_all
    ;;
  up)
    create_venv
    read_env
    ensure_runtime_deps
    start_vllm
    ;;
  down)
    stop_from_pid_file "vllm" "${VLLM_PID_FILE}"
    ;;
  restart)
    stop_from_pid_file "vllm" "${VLLM_PID_FILE}"
    create_venv
    read_env
    ensure_runtime_deps
    start_vllm
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
    logs
    ;;
  systemd-install)
    install_systemd_user_service
    ;;
  systemd-remove)
    remove_systemd_user_service
    ;;
  help|*)
    usage
    [[ "${ACTION}" == "help" ]] || exit 1
    ;;
esac
