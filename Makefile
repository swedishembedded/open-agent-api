.PHONY: generate

generate:
	openapi-generator-cli generate \
		-i open-agent-api.yaml \
		-g python \
		-o python/client/ \
		--package-name open_agent_api \
  		--additional-properties=packageVersion=0.6.0

.PHONY: install
install:
	pip install --upgrade -r requirements.txt
	if ! command -v java; then \
		sudo apt-get install -qy default-jre; \
	fi

.PHONY: refresh
refresh: generate install
	pip3 install --upgrade python/client

.PHONY: run
run:
	python -m python.fastapi.open_agent_api.api

.PHONY: build
build:
	python -m build python/client

.PHONY: publish
publish:
	python -m twine upload python/client/dist/*

# Documentation targets
.PHONY: docs-redoc
docs-redoc:
	mkdir -p docs/redoc
	npx @redocly/cli bundle open-agent-api.yaml -o docs/redoc/openapi-bundled.yaml
	npx @redocly/cli build-docs docs/redoc/openapi-bundled.yaml -o docs/redoc/index.html

.PHONY: docs-swagger
docs-swagger:
	./generate_swagger_ui.sh

.PHONY: docs
docs: docs-redoc docs-swagger
	@echo "Documentation generated in docs/ directory"

.PHONY: serve-docs
serve-docs:
	npx http-server docs -p 8080
