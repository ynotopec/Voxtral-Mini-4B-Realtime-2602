# Voxtral Realtime API (vLLM)

FastAPI gateway compatible with OpenAI Realtime endpoints for `mistralai/Voxtral-Mini-4B-Realtime-2602`.

## Quick start

```bash
make install
make up
```

`make up` and `make restart` verify that core runtime dependencies are installed in the project venv, and self-heal if needed. If `pyairports` cannot be resolved from package indexes, startup installs a tiny compatibility module so vLLM can import `outlines` successfully.

## Day-2 operations

```bash
make status               # show running/stopped state + pid/log hints
make logs                 # show both logs
make logs api             # api log only
make restart              # restart both services
make down                 # stop services
make systemd-install      # install + start systemd user service
make systemd-install 0.0.0.0 8010  # with host/port override
make systemd-remove       # remove systemd user service
```

## Make targets

```bash
make help                 # concise command list
make install              # create ~/venv/<repo-name> + install deps + bootstrap .env
make up [host] [port]     # start vLLM + API (optional host/port override)
make down                 # stop API + vLLM
make restart              # restart API + vLLM
make upgrade              # upgrade dependency set in existing venv
make status               # service status
make logs [api|vllm|all]  # view logs
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
- `HOST` (API bind host)
- `PORT` (API bind port)
- `REALTIME_PORT` (vLLM serve port)
- `MODEL_ID` (model to serve)
- `DEVICE` (e.g. `cuda:0`)

## Systemd

- `make systemd-install [host] [port]` creates a **systemd user** unit named after the repo directory basename (for example `Voxtral-Mini-4B-Realtime-2602.service`).
- The unit file is written to `~/.config/systemd/user/<basename>.service`.
- Override bind values at install time via positional args, e.g. `make systemd-install 10.0.0.12 8000`.

## API surface

- `GET /`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `WS /v1/realtime`
