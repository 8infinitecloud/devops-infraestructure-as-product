# Empaquetado de las Lambdas antes de que Terraform las recoja.
#
# Terraform no compila nada por si mismo: el data source archive_file lee lo que
# haya en build/ en tiempo de plan. Por eso `make bin` SIEMPRE va antes de
# `terraform plan/apply`. Es el mismo patron que usa el motor de HashiCorp en la
# Demo 2 para sus Lambdas en Go.

SHELL      := /bin/bash
PYTHON     ?= python3
BUILD_DIR  := build

# Lambdas en Python: se copian las fuentes y se instalan las dependencias dentro
PY_LAMBDAS := provisioning-operations-handler state_machine_lambdas

# Lambda en Go: se compila estaticamente para el runtime provided.al2 (x86_64)
GO_SRC     := terraform_open_source_parameter_parser
GO_OUT     := $(BUILD_DIR)/terraform-parameter-parser

.PHONY: bin python go clean verify

bin: python go
	@echo ""
	@echo "== Artefactos listos en $(BUILD_DIR)/ =="
	@du -sh $(BUILD_DIR)/* 2>/dev/null || true

python:
	@for d in $(PY_LAMBDAS); do \
	  echo "== Empaquetando $$d (python) =="; \
	  rm -rf $(BUILD_DIR)/$$d; \
	  mkdir -p $(BUILD_DIR)/$$d; \
	  rsync -a --exclude='test_*' --exclude='__pycache__' --exclude='*.pyc' \
	        --exclude='requirements.txt' "$$d"/ "$(BUILD_DIR)/$$d"/; \
	  $(PYTHON) -m pip install --quiet --disable-pip-version-check \
	        -r "$$d/requirements.txt" -t "$(BUILD_DIR)/$$d"; \
	  find "$(BUILD_DIR)/$$d" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true; \
	  find "$(BUILD_DIR)/$$d" -name '*.dist-info' -type d -prune -exec rm -rf {} + 2>/dev/null || true; \
	done

go:
	@echo "== Compilando $(GO_SRC) (go) =="
	@mkdir -p $(GO_OUT)
	cd $(GO_SRC) && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
	  go build -trimpath -ldflags="-s -w" -o "../$(GO_OUT)/bootstrap"
	@chmod +x $(GO_OUT)/bootstrap

# Comprueba que el binario Go quedo en la arquitectura que declara Terraform.
# El repo upstream traia 'GOARACH' (typo) y producia un binario ARM en Macs Apple Silicon.
verify:
	@echo "== Arquitectura del binario Go =="
	@file $(GO_OUT)/bootstrap
	@file $(GO_OUT)/bootstrap | grep -q 'x86-64' \
	  && echo "OK: x86-64, coincide con architectures del aws_lambda_function" \
	  || { echo "ERROR: el binario NO es x86-64" >&2; exit 1; }

clean:
	rm -rf $(BUILD_DIR)
