# Architecture

## Components

- **vLLM server**: single runtime process launched by `scripts/manage.sh`.
- **Ops automation**: process lifecycle + logs + systemd unit management.

## Data path

```text
Client -> vLLM OpenAI-compatible API
```

## Operational controls

Use `scripts/manage.sh` (or `make`) for:

- dependency install/bootstrap
- start/stop/restart
- service status checks
- logs tailing
- systemd user unit install/remove

No proxy layer, no event translation layer.
