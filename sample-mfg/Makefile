SHELL ?= /bin/bash -e
export MFG_VERSION ?= latest

DOCKER_REGISTRY ?= openhorizon
SDO_MFG_DOCKER_IMAGE ?= manufacturer
SDO_MARIADB_DOCKER_IMAGE ?= sct_mariadb

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: $(SDO_MFG_DOCKER_IMAGE)

# Build the sample SDO mfg services docker image - see the build environment requirements listed in sample-mfg/Dockerfile
sdo-mfg-services:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	cd Services/SCT && docker-compose build

# Run the SDO services docker container
# If you want to run the image w/o rebuilding: make -W sdo-mfg-services run-sdo-mfg-services
run-sdo-mfg-services: sdo-mfg-services
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	docker run --name $(SDO_MFG_DOCKER_IMAGE) -dt -p $(SDO_RV_PORT):$(SDO_RV_PORT) -e "SDO_OCS_DB_PATH=$(SDO_OCS_DB_CONTAINER_DIR)" -e "OCS_API_PORT=$(OCS_API_PORT)" $(DOCKER_REGISTRY)/$<:$(MFG_VERSION)

# Push the SDO services docker image to the registry
publish-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)

pull-sdo-mfg-services:
	docker pull $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker pull $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)

clean:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) 2> /dev/null || :

.PHONY: default clean
