# Overview

This repository provides lightweight operational automation for running Voxtral on the **native vLLM OpenAI-compatible server**.

## What is included

- `scripts/manage.sh`: lifecycle automation (`install`, `up`, `down`, `restart`, `status`, `logs`, `systemd-install`).
- `Makefile`: ergonomic command aliases.
- `run.sh`: foreground watchdog that ensures the vLLM process stays alive.
- `client_example.py`: local websocket client examples.

## Runtime flow

1. `scripts/manage.sh up` reads `.env`.
2. It starts `vllm serve` directly with model/device/host/port.
3. Clients connect straight to vLLM OpenAI-compatible endpoints.

## Design goal

Keep the repository small and automatable by avoiding custom gateway logic.
