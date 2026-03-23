PROJECT_NAME := $(notdir $(CURDIR))
VENV_DIR ?= $(HOME)/venv/$(PROJECT_NAME)
UV ?= uv
PYTHON ?= $(VENV_DIR)/bin/python
PIP ?= $(VENV_DIR)/bin/pip
MODEL ?= mistralai/Voxtral-Mini-4B-Realtime-2602
DEVICE ?= cuda:0
REALTIME_PORT ?= 9000
API_PORT ?= 8000
API_HOST ?= 0.0.0.0

# Support positional usage: make up [IP] [PORT]
UP_IP := $(word 2,$(MAKECMDGOALS))
UP_PORT := $(word 3,$(MAKECMDGOALS))

.PHONY: install up down upgrade check

install:
	./scripts/manage.sh install "$(PROJECT_NAME)"

up:
	./scripts/manage.sh up "$(PROJECT_NAME)" "$(UP_IP)" "$(UP_PORT)"

# absorb positional arguments as no-op targets
%:
	@:

down:
	./scripts/manage.sh down "$(PROJECT_NAME)"

upgrade:
	./scripts/manage.sh upgrade "$(PROJECT_NAME)"

check:
	$(PYTHON) -m compileall main.py client_example.py
	$(PYTHON) -m py_compile main.py client_example.py
