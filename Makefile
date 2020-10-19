SHELL ?= /bin/bash -e
# Set this before building the ocs-api binary and sdo-owner-services (for now they use the samme version number)
export VERSION ?= 1.8.6

export DOCKER_REGISTRY ?= openhorizon
export SDO_DOCKER_IMAGE ?= sdo-owner-services
SDO_IMAGE_LABELS ?= --label "vendor=IBM" --label "name=$(SDO_DOCKER_IMAGE)" --label "version=$(VERSION)" --label "release=$(shell git rev-parse --short HEAD)" --label "summary=Open Horizon SDO support image" --label "description=The SDO owner services run in the context of the open-horizon management hub"
# This doesn't work. According to https://docs.docker.com/engine/reference/builder/#label it is not necessary to put all of the labels in a single image layer
#SDO_IMAGE_LABELS ?= --label 'vendor=IBM name=$(SDO_DOCKER_IMAGE) version=$(VERSION) release=$(shell git rev-parse --short HEAD) summary="Open Horizon SDO support image" description="The SDO owner services run in the context of the open-horizon management hub"'

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: $(SDO_DOCKER_IMAGE)

# Build the ocs rest api for linux for the sdo-owner-services container
ocs-api/linux/ocs-api: ocs-api/*.go ocs-api/*/*.go Makefile
	echo 'package main; const OCS_API_VERSION = "$(VERSION)"' > ocs-api/version.go
	mkdir -p ocs-api/linux
	(cd ocs-api && GOOS=linux go build -o linux/ocs-api)

# For building and running the ocs rest api on mac for debugging
ocs-api/ocs-api: ocs-api/*.go ocs-api/*/*.go Makefile
	echo 'package main; const OCS_API_VERSION = "$(VERSION)"' > ocs-api/version.go
	(cd ocs-api && go build -o ocs-api)

run-ocs-api: ocs-api/ocs-api
	- tools/stop-ocs-api.sh || :
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

# Push the SDO services docker image that you are still working on to the registry. This is necessary if you are testing on a different machine than you are building on.
dev-push-$(SDO_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)

# Push the SDO services docker image to the registry and tag as testing
push-$(SDO_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION) $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):testing
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):testing

# Push the SDO services docker image to the registry and tag as latest
publish-$(SDO_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION) $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):latest

# Push the SDO services docker image to the registry and tag as stable
promote-$(SDO_DOCKER_IMAGE):
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION) $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):stable
	docker push $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):stable

# Use this if you are on a machine where you did not build the image
pull-$(SDO_DOCKER_IMAGE):
	docker pull $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):$(VERSION)

# Adjust the 'stable' tag to point to the current fully tested level of the repo
# Note: only do this after pushing/merging all code changes into master in the canonical repo, and updating your local repo with that
change-stable-tag:
	git checkout master
	git push origin :refs/tags/stable   # remove remote tag
	git push canonical :refs/tags/stable   # remove remote tag
	git tag -fa stable -m 'stable level of code'   # create/change the tag locally
	git push origin --tags
	git push canonical --tags

clean:
	go clean
	rm -f ocs-api/ocs-api ocs-api/linux/ocs-api
	- docker rm -f $(SDO_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(DOCKER_REGISTRY)/$(SDO_DOCKER_IMAGE):{$(VERSION),latest,stable} 2> /dev/null || :

.PHONY: default run-ocs-api run-$(SDO_DOCKER_IMAGE) push-$(SDO_DOCKER_IMAGE) publish-$(SDO_DOCKER_IMAGE) promote-$(SDO_DOCKER_IMAGE) pull-$(SDO_DOCKER_IMAGE) change-stable-tag clean
