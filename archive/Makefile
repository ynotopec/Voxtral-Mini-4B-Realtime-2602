PROJECT_NAME := $(notdir $(CURDIR))
MANAGE := ./scripts/manage.sh
PYTHON ?= $(HOME)/venv/$(PROJECT_NAME)/bin/python

# Support positional usage: make up [IP] [PORT]
UP_IP := $(word 2,$(MAKECMDGOALS))
UP_PORT := $(word 3,$(MAKECMDGOALS))

.PHONY: help install uninstall up down restart upgrade status logs systemd-install systemd-remove check clean

help:
	@echo "Targets:"
	@echo "  make install            # create venv + install deps"
	@echo "  make uninstall          # stop service + remove venv/.run/systemd unit"
	@echo "  make up [IP] [PORT]     # start vLLM OpenAI-compatible server"
	@echo "  make down               # stop vLLM"
	@echo "  make restart            # restart vLLM"
	@echo "  make status             # service status"
	@echo "  make logs               # tail vLLM logs"
	@echo "  make systemd-install [IP] [PORT]  # install/start sudo system service"
	@echo "  make systemd-remove     # uninstall/stop sudo system service"
	@echo "  make check              # compile/syntax check"
	@echo "  make clean              # remove runtime artifacts"

install:
	$(MANAGE) install "$(PROJECT_NAME)"

uninstall:
	$(MANAGE) uninstall "$(PROJECT_NAME)"

up:
	$(MANAGE) up "$(PROJECT_NAME)" "$(UP_IP)" "$(UP_PORT)"

down:
	$(MANAGE) down "$(PROJECT_NAME)"

restart:
	$(MANAGE) restart "$(PROJECT_NAME)" "$(UP_IP)" "$(UP_PORT)"

upgrade:
	$(MANAGE) upgrade "$(PROJECT_NAME)"

status:
	$(MANAGE) status "$(PROJECT_NAME)"

logs:
	$(MANAGE) logs "$(PROJECT_NAME)"

systemd-install:
	$(MANAGE) systemd-install "$(PROJECT_NAME)" "$(UP_IP)" "$(UP_PORT)"

systemd-remove:
	$(MANAGE) systemd-remove "$(PROJECT_NAME)"

check:
	$(PYTHON) -m compileall client_example.py
	$(PYTHON) -m py_compile client_example.py

clean:
	rm -rf .run __pycache__ .pytest_cache

# absorb positional arguments as no-op targets
%:
	@:
