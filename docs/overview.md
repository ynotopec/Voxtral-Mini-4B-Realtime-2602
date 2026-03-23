# Overview

This repository provides a small FastAPI gateway that exposes OpenAI-compatible realtime endpoints and forwards websocket traffic to a local vLLM Voxtral backend.

## What is included

- `main.py`: FastAPI + websocket bridge.
- `scripts/manage.sh`: lifecycle automation (`install`, `up`, `down`, `restart`, `status`, `logs`).
- `Makefile`: ergonomic command aliases.
- `client_example.py`: local websocket client examples.

## Runtime flow

1. Client connects to `WS /v1/realtime`.
2. Gateway creates a local session id.
3. Audio/text events are forwarded to vLLM (`ws://localhost:${REALTIME_PORT}`).
4. Gateway relays realtime events back to the client.

## Why this repo is intentionally small

The project favors operational simplicity over framework complexity:

- one app process (`main.py`)
- one management script (`scripts/manage.sh`)
- one command entrypoint (`make ...`)

Use `make help` to discover all supported operations.
