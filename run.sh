#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BASENAME="$(basename "$SCRIPT_DIR")"
VENV_DIR="${HOME}/venv/${PROJECT_BASENAME}"
ENV_FILE="${SCRIPT_DIR}/.env"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

venv_python() { echo "${VENV_DIR}/bin/python"; }
venv_uv() { echo "${VENV_DIR}/bin/uv"; }
venv_vllm() { echo "${VENV_DIR}/bin/vllm"; }
venv_hf() { echo "${VENV_DIR}/bin/huggingface-cli"; }

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Missing ${ENV_FILE}"

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  : "${HF_TOKEN:?HF_TOKEN is required in .env}"

  : "${MODEL_ID:=mistralai/Voxtral-Mini-4B-Realtime-2602}"
  : "${HOST:=0.0.0.0}"
  : "${PORT:=8000}"
  : "${VLLM_API_KEY:=token-voxtral-local}"
  : "${CUDA_VISIBLE_DEVICES:=0}"
  : "${HF_HOME:=${HOME}/.cache/huggingface}"
  : "${MAX_MODEL_LEN:=131072}"
  : "${MAX_NUM_BATCHED_TOKENS:=4096}"
  : "${GPU_MEMORY_UTILIZATION:=0.90}"
  : "${CPU_OFFLOAD_GB:=0}"

  export HF_TOKEN MODEL_ID HOST PORT VLLM_API_KEY CUDA_VISIBLE_DEVICES HF_HOME
  export MAX_MODEL_LEN MAX_NUM_BATCHED_TOKENS GPU_MEMORY_UTILIZATION CPU_OFFLOAD_GB
}

apply_cli_overrides() {
  if [[ $# -gt 2 ]]; then
    die "Usage: ./run.sh [HOST] [PORT]"
  fi

  if [[ $# -ge 1 && -n "${1:-}" ]]; then
    HOST="$1"
  fi

  if [[ $# -ge 2 && -n "${2:-}" ]]; then
    PORT="$2"
  fi

  [[ "$PORT" =~ ^[0-9]+$ ]] || die "PORT must be an integer"
  (( PORT >= 1 && PORT <= 65535 )) || die "PORT must be between 1 and 65535"
}

create_venv() {
  need_cmd python3
  if [[ ! -x "$(venv_python)" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
}

install_deps() {
  create_venv
  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"

  python -m pip install --upgrade pip setuptools wheel
  python -m pip install --upgrade uv

  # Respect model documentation: install vLLM from nightly package
  uv pip install -p "$(venv_python)" -U vllm --pre --extra-index-url https://wheels.vllm.ai/nightly

  # Audio/runtime deps from model doc
  uv pip install -p "$(venv_python)" -U soxr librosa soundfile websockets numpy "huggingface_hub[cli]"

  # Recommended by model doc
  uv pip install -p "$(venv_python)" --upgrade transformers
}

login_hf() {
  mkdir -p "${HF_HOME}"
  if [[ ! -f "${HF_HOME}/token" ]]; then
    "$(venv_hf)" login --token "${HF_TOKEN}" --add-to-git-credential >/dev/null 2>&1 || true
  fi
}

run_server() {
  export CUDA_VISIBLE_DEVICES HF_HOME HF_TOKEN

  echo "Starting vLLM"
  echo "MODEL_ID=${MODEL_ID}"
  echo "HOST=${HOST}"
  echo "PORT=${PORT}"
  echo "VENV_DIR=${VENV_DIR}"

  exec "$(venv_vllm)" serve "${MODEL_ID}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --api-key "${VLLM_API_KEY}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}" \
    --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
    --cpu-offload-gb "${CPU_OFFLOAD_GB}" \
    --compilation_config '{"cudagraph_mode": "PIECEWISE"}'
}

main() {
  load_env
  apply_cli_overrides "$@"
  install_deps
  login_hf
  run_server
}

main "$@"
