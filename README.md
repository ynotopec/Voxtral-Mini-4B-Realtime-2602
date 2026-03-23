# Voxtral Realtime API (vLLM)

FastAPI gateway compatible with OpenAI Realtime endpoints for `mistralai/Voxtral-Mini-4B-Realtime-2602`.

## Requirements

- Python 3.10+
- [`uv`](https://docs.astral.sh/uv/)
- CUDA-capable environment for vLLM runtime

## Quick start

```bash
make install
make up
```

The stack launches:
- vLLM realtime backend (`REALTIME_PORT`, default `9000`)
- FastAPI gateway (`HOST`/`PORT`, defaults `0.0.0.0:8000`)

## Make targets

```bash
make install            # create ~/venv/<repo-name>, install deps, bootstrap .env
make up                 # start vLLM + API using .env
make up 0.0.0.0 8100    # positional override for API host/port
make down               # stop API + vLLM
make upgrade            # upgrade dependency set in existing venv
make check              # compile + syntax checks
```

The workflow is idempotent:
- existing venv is reused
- existing `.env` is preserved
- `make up` avoids duplicate process launches if pid files are still alive

## Environment configuration

Copy/edit `.env` from `.env.example`:

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
