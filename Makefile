SHELL ?= /bin/bash -e
# Set this before building the ocs-api binary and sdo-owner-services (for now they use the samme version number)
export VERSION ?= 0.5.0

DOCKER_REGISTRY ?= openhorizon
SDO_DOCKER_IMAGE ?= sdo-owner-services
SDO_OCS_DB_HOST_DIR ?= $(PWD)/ocs-db
# this is where OCS needs it to be
SDO_OCS_DB_CONTAINER_DIR ?= /root/ocs/config/db
OCS_API_PORT ?= 9008

export MFG_VERSION ?= 0.5.0
SDO_MFG_DOCKER_IMAGE ?= sdo-mfg-services

# These can't be overridden easily
SDO_RV_PORT = 8040
SDO_TO0_PORT = 8049
SDO_OPS_PORT = 8042

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: $(SDO_DOCKER_IMAGE)

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
# If you want to run the image w/o rebuilding: make -W sdo-owner-services -W ocs-api/linux/ocs-api run-sdo-owner-services
#todo: remove HZN_EXCHANGE_USER_AUTH from these rules
run-$(SDO_DOCKER_IMAGE): $(SDO_DOCKER_IMAGE)
	: $${HZN_EXCHANGE_URL:?} $${HZN_FSS_CSSURL:?} $${HZN_ORG_ID:?} $${HZN_MGMT_HUB_CERT:?} $${HZN_EXCHANGE_USER_AUTH:?}
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	docker run --name $(SDO_DOCKER_IMAGE) -dt -v $(SDO_OCS_DB_HOST_DIR):$(SDO_OCS_DB_CONTAINER_DIR) -p $(OCS_API_PORT):$(OCS_API_PORT) -p $(SDO_RV_PORT):$(SDO_RV_PORT) -p $(SDO_TO0_PORT):$(SDO_TO0_PORT) -p $(SDO_OPS_PORT):$(SDO_OPS_PORT) -e "SDO_OCS_DB_PATH=$(SDO_OCS_DB_CONTAINER_DIR)" -e "OCS_API_PORT=$(OCS_API_PORT)" -e "HZN_EXCHANGE_URL=$${HZN_EXCHANGE_URL}" -e "HZN_FSS_CSSURL=$${HZN_FSS_CSSURL}" -e "HZN_ORG_ID=$${HZN_ORG_ID}" -e "HZN_MGMT_HUB_CERT=$${HZN_MGMT_HUB_CERT}" -e "HZN_EXCHANGE_USER_AUTH=$${HZN_EXCHANGE_USER_AUTH}" $(DOCKER_REGISTRY)/$<:$(VERSION)

# Push the SDO services docker image to the registry
publish-$(SDO_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION) $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest

pull-$(SDO_DOCKER_IMAGE):
	docker pull $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)


# Build the sample SDO mfg services docker image - see the build environment requirements listed in sample-mfg/Dockerfile
$(SDO_MFG_DOCKER_IMAGE):
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) 2> /dev/null || :
	docker build -t $(DOCKER_REGISTRY)/$@:$(MFG_VERSION) $(DOCKER_OPTS) -f sample-mfg/Dockerfile .

# Run the SDO services docker container
# If you want to run the image w/o rebuilding: make -W sdo-mfg-services run-sdo-mfg-services
run-$(SDO_MFG_DOCKER_IMAGE): $(SDO_MFG_DOCKER_IMAGE)
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) 2> /dev/null || :
	docker run --name $(SDO_MFG_DOCKER_IMAGE) -dt -p $(SDO_RV_PORT):$(SDO_RV_PORT) -e "SDO_OCS_DB_PATH=$(SDO_OCS_DB_CONTAINER_DIR)" -e "OCS_API_PORT=$(OCS_API_PORT)" $(DOCKER_REGISTRY)/$<:$(MFG_VERSION)

# Push the SDO services docker image to the registry
publish-$(SDO_MFG_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):latest

pull-$(SDO_MFG_DOCKER_IMAGE):
	docker pull $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)

clean:
	go clean
	rm -f ocs-api/ocs-api ocs-api/linux/ocs-api
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):{$(VERSION),latest} 2> /dev/null || :
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):{$(MFG_VERSION),latest} 2> /dev/null || :

.PHONY: default run-ocs-api clean
