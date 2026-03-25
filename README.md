# Voxtral Mini 4B Realtime (Direct vLLM)

Lean automation around `vllm serve` for `mistralai/Voxtral-Mini-4B-Realtime-2602`.

This repository now runs **direct vLLM only** (no FastAPI proxy layer).

## Quick start

```bash
make install
make up
```

`make up` and `make restart` auto-verify runtime dependencies and self-heal the `pyairports` compatibility shim when needed.

## Day-2 operations

```bash
make status
make logs
make restart
make down
make systemd-install
make systemd-install 0.0.0.0 8010
make systemd-remove
```

## Make targets

```bash
make help                 # concise command list
make install              # create ~/venv/<repo-name> + install deps + bootstrap .env
make up [host] [port]     # start vLLM OpenAI-compatible server
make down                 # stop vLLM
make restart              # restart vLLM
make upgrade              # upgrade dependency set in existing venv
make status               # service status
make logs                 # view vLLM logs
make systemd-install [host] [port] # install/start systemd user service
make systemd-remove       # uninstall/stop systemd user service
make check                # compile + syntax checks
make clean                # remove runtime artifacts
```

## Environment

Create `.env` from `.env.example` if needed:

```bash
cp .env.example .env
```

Variables:
- `HOST` (vLLM bind host)
- `PORT` (vLLM bind port)
- `MODEL_ID` (model to serve)
- `DEVICE` (e.g. `cuda:0`)
- `VLLM_API_KEY` (optional API key passed to `vllm serve --api-key`)

## API surface

Served directly by vLLM:
- `GET /v1/models`
- `POST /v1/chat/completions`
- `WS /v1/realtime` (for supported realtime models)

## Systemd

- `make systemd-install [host] [port]` creates a **systemd user** unit named after the repo directory basename (for example `Voxtral-Mini-4B-Realtime-2602.service`).
- The unit file is written to `~/.config/systemd/user/<basename>.service`.
- Override bind values at install time via positional args, e.g. `make systemd-install 10.0.0.12 8000`.
