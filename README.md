# Voxtral Realtime API (vLLM)

FastAPI gateway compatible with OpenAI Realtime endpoints for `mistralai/Voxtral-Mini-4B-Realtime-2602`.

## Quick start

```bash
make install
make up
```

## Day-2 operations

```bash
make status               # show running/stopped state + pid/log hints
make logs                 # show both logs
make logs api             # api log only
make restart              # restart both services
make down                 # stop services
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

## API surface

- `GET /`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `WS /v1/realtime`
