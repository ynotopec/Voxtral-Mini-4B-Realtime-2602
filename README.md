# Voxtral Realtime API

FastAPI gateway compatible with OpenAI Realtime endpoints for `mistralai/Voxtral-Mini-4B-Realtime-2602`.

## Quick start

```bash
make setup
make run
```

By default, the API starts on `http://0.0.0.0:8000` and proxies realtime traffic to `ws://localhost:9000`.

## Automated commands

```bash
make setup      # install dependencies
make run        # start API server
make dev        # start API server with auto-reload
make check      # run syntax and import checks
make example    # run sample client
```

## Typical runtime

1. Start vLLM realtime backend (port `9000`):

```bash
vllm serve mistralai/Voxtral-Mini-4B-Realtime-2602 --port 9000 --device cuda:0
```

2. Start this gateway:

```bash
make run
```

## API surface

- `GET /`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `WS /v1/realtime`

## Notes

- CORS is open (`*`) by default.
- Configure host/port/realtime target via environment variables (`HOST`, `PORT`, `REALTIME_PORT`).
