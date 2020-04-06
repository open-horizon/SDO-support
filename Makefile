SHELL ?= /bin/bash -e
# Set this before building the ocs-api binary
export VERSION ?= 0.2.0

DOCKER_REGISTRY ?= openhorizon
SDO_DOCKER_IMAGE ?= sdo-owner-services
SDO_OCS_DB_HOST_DIR ?= $(PWD)/ocs-db
# this is where OCS needs it to be
SDO_OCS_DB_CONTAINER_DIR ?= /ocs/config/db
OCS_API_PORT ?= 9008

SDO_RV_PORT = 8040
SDO_TO0_PORT = 8049
SDO_OPS_PORT = 8042

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: run-ocs-api

ocs-api/ocs-api: ocs-api/*.go ocs-api/*/*.go Makefile
	echo 'package main; const OCS_API_VERSION = "$(VERSION)"' > ocs-api/version.go
	glide --quiet install
	(cd ocs-api && go build -o ocs-api)

ocs-api/linux/ocs-api: ocs-api/*.go ocs-api/*/*.go Makefile
	echo 'package main; const OCS_API_VERSION = "$(VERSION)"' > ocs-api/version.go
	glide --quiet install
	mkdir -p ocs-api/linux
	(cd ocs-api && GOOS=linux go build -o linux/ocs-api)

run-ocs-api: ocs-api/ocs-api
	tools/stop-ocs-api.sh || true
	tools/start-ocs-api.sh

# Build the SDO services docker image - see the build environment requirements listed in docker/Dockerfile
$(SDO_DOCKER_IMAGE): ocs-api/linux/ocs-api
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	docker build -t $(DOCKER_REGISTRY)/$@:$(VERSION) $(DOCKER_OPTS) -f docker/Dockerfile .

# Run the SDO services docker container
run-$(SDO_DOCKER_IMAGE): $(SDO_DOCKER_IMAGE)
	: $${HZN_EXCHANGE_URL:?} $${HZN_FSS_CSSURL:?} $${HZN_ORG_ID:?} $${HZN_MGMT_HUB_CERT:?}
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	docker run --name $(SDO_DOCKER_IMAGE) -dt -v $(SDO_OCS_DB_HOST_DIR):$(SDO_OCS_DB_CONTAINER_DIR) -p $(OCS_API_PORT):$(OCS_API_PORT) -p $(SDO_RV_PORT):$(SDO_RV_PORT) -p $(SDO_TO0_PORT):$(SDO_TO0_PORT) -p $(SDO_OPS_PORT):$(SDO_OPS_PORT) -e "SDO_OCS_DB_PATH=$(SDO_OCS_DB_CONTAINER_DIR)" -e "OCS_API_PORT=$(OCS_API_PORT)" -e "HZN_EXCHANGE_URL=$${HZN_EXCHANGE_URL}" -e "HZN_FSS_CSSURL=$${HZN_FSS_CSSURL}" -e "HZN_ORG_ID=$${HZN_ORG_ID}" -e "HZN_MGMT_HUB_CERT=$${HZN_MGMT_HUB_CERT}" $(DOCKER_REGISTRY)/$<:$(VERSION)

# Push the SDO services docker image to the registry
publish-$(SDO_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION) $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest

clean:
	go clean
	rm -f ocs-api/ocs-api ocs-api/linux/ocs-api
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):{$(VERSION),latest} 2> /dev/null || :

.PHONY: default run-ocs-api clean
