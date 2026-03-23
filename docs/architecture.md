# Architecture

## Components

- **Gateway API** (`main.py`): Handles REST and websocket interfaces.
- **Session manager** (`WebsocketConnectionManager`): Tracks active client sessions.
- **Realtime backend** (vLLM): Receives forwarded websocket events and produces streaming responses.

## Minimal data path

```text
Client WS -> FastAPI /v1/realtime -> vLLM WS backend -> FastAPI -> Client WS
```

## Message handling highlights

- Accepts and routes `input_audio_buffer.append` and `response.create`.
- Forwards session/control events listed in `FORWARD_MESSAGE_TYPES`.
- Returns structured error messages for unsupported message types.

## Operational controls

Use `scripts/manage.sh` (or `make`) for:

- dependency install/bootstrap
- start/stop/restart
- service status checks
- logs tailing

This keeps runtime orchestration out of application code.
