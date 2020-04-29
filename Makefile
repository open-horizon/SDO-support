SHELL ?= /bin/bash -e
# Set this before building the ocs-api binary and sdo-owner-services (for now they use the samme version number)
export VERSION ?= 0.9.0

export DOCKER_REGISTRY ?= openhorizon
export SDO_DOCKER_IMAGE ?= sdo-owner-services
SDO_IMAGE_LABELS ?= --label "vendor=IBM" --label "name=$(SDO_DOCKER_IMAGE)" --label "version=$(VERSION)" --label "release=$(shell git rev-parse --short HEAD)" --label "summary=Open Horizon SDO support image" --label "description=The SDO owner services run in the context of the open-horizon management hub"

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
	docker build -t $(DOCKER_REGISTRY)/$@:$(VERSION) $(SDO_IMAGE_LABELS) $(DOCKER_OPTS) -f docker/Dockerfile .

# Run the SDO services docker container
# If you want to run the image w/o rebuilding: make -W sdo-owner-services -W ocs-api/linux/ocs-api run-sdo-owner-services
#todo: remove HZN_EXCHANGE_USER_AUTH from these rules
run-$(SDO_DOCKER_IMAGE): $(SDO_DOCKER_IMAGE)
	: $${HZN_EXCHANGE_URL:?} $${HZN_FSS_CSSURL:?} $${HZN_ORG_ID:?} $${HZN_MGMT_HUB_CERT:?} $${HZN_EXCHANGE_USER_AUTH:?}
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	docker/run-sdo-owner-services.sh $(VERSION)

# Push the SDO services docker image to the registry
publish-$(SDO_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION) $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest

pull-$(SDO_DOCKER_IMAGE):
	docker pull $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)

clean:
	go clean
	rm -f ocs-api/ocs-api ocs-api/linux/ocs-api
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):{$(VERSION),latest} 2> /dev/null || :

.PHONY: default run-ocs-api clean
