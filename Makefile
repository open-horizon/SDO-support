SHELL ?= /bin/bash -e
#BINARY ?= cmd/server/mendel-web-ui
BINARY ?= mendel-web-ui
# Set this before building the ocs-api binary
export VERSION ?= 1.1.8

default: run-ocs-api

ocs-api/ocs-api: ocs-api/*.go ocs-api/*/*.go Makefile
	echo 'package main; const OCS_API_VERSION = "$(VERSION)"' > ocs-api/version.go
	glide --quiet install
	(cd ocs-api && go build -o ocs-api)

run-ocs-api: ocs-api/ocs-api
	tools/stop-ocs-api.sh || true
	tools/start-ocs-api.sh

clean:
	go clean

.PHONY: default run-ocs-api clean
