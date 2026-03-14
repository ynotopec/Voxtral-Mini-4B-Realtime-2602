PYTHON ?= python
PIP ?= pip

.PHONY: setup run dev check example

setup:
	$(PIP) install -r requirements.txt

run:
	$(PYTHON) main.py

dev:
	uvicorn main:app --host 0.0.0.0 --port 8000 --reload

check:
	$(PYTHON) -m compileall main.py client_example.py
	$(PYTHON) -m py_compile main.py client_example.py

example:
	$(PYTHON) client_example.py
