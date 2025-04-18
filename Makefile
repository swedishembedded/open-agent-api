.PHONY: generate

generate:
	openapi-generator-cli generate \
		-i open-agent-api.yaml \
		-g python \
		-o python/client/ \
		--package-name open_agent_api \
  		--additional-properties=packageVersion=0.2.0
	openapi-generator-cli generate \
		-i open-agent-api.yaml \
		-g python-fastapi \
		-o python/fastapi/ \
		--package-name open_agent_api_server

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
