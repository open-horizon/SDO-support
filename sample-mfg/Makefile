SHELL ?= /bin/bash -e

# These 2 variables use VERSION and STABLE_VERSION from the top-level Makefile as the default. MFG_VERSION is not currently being used.
export MFG_VERSION ?= $(shell grep -m 1 -E '^export VERSION \?=' ../Makefile | awk '{print$$4}')
STABLE_VERSION ?= $(shell grep -m 1 -E '^STABLE_VERSION \?=' ../Makefile | awk '{print$$3}')

DOCKER_REGISTRY ?= openhorizon
SDO_MFG_DOCKER_IMAGE ?= manufacturer
SDO_MARIADB_DOCKER_IMAGE ?= manufacturer-mariadb
#SDO_MFG_USER ?= admin
#SDO_MFG_PW ?= admin
SDO_SCT_MFG_DIR ?= ../sdo/supply-chain-tools-v1.9.0/docker_manufacturer

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: sdo-mfg-services

# Build the sample SDO mfg services docker images. The SDO docker-compose.yml will build images: manufacturer:$(STABLE_VERSION) and manufacturer-mariadb:$(STABLE_VERSION)
# Note: even though Dockerfile-mariadb copies mt_config.sql into the container and that sets the RV URL in the DB, simulate-mfg.sh updates that table with the correct value specified by the user.
sdo-mfg-services:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	# Note we use the docker-compose.yml from SDO_SCT_MFG_DIR
	cd $(SDO_SCT_MFG_DIR) && docker-compose build

# Note: we currently use docker-compose up to run the containers.

# Push the SDO mfg docker images to the registry with the testing tag
push-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION)
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION)
	docker tag $(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):testing
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):testing
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):testing
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):testing

# Push the SDO mfg docker images to the registry with the latest tag
publish-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):latest
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):latest

# Push the SDO mfg docker images to the registry with $(STABLE_VERSION) tag
promote-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION)
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION)

# Use this if you are on a machine where you did not build the images
pull-sdo-mfg-services:
	docker pull $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) $(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) 
	docker pull $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION) $(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION)

sdo_device_binaries_1.9_linux_x64.tar.gz:
	mkdir -p sdo_device_binaries_1.9_linux_x64/NOTICES
	cp -a ../sdo/pri-v1.9.1/device sdo_device_binaries_1.9_linux_x64/
	cp -a ../sdo/supply-chain-tools-v1.9.0/docker_manufacturer/docker-compose.yml sdo_device_binaries_1.9_linux_x64/
	cp -a ../sdo/supply-chain-tools-v1.9.0/docker_manufacturer/*.env sdo_device_binaries_1.9_linux_x64/
	cp -a ../sdo/supply-chain-tools-v1.9.0/docker_manufacturer/keys sdo_device_binaries_1.9_linux_x64/
	cp -a ../keys/sample-owner-key.pub sdo_device_binaries_1.9_linux_x64/keys/
	cp -a ../sdo/NOTICES-v1.9.1/pri/NOTICE sdo_device_binaries_1.9_linux_x64/NOTICES/
	tar -zcvf $@ sdo_device_binaries_1.9_linux_x64

clean:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(STABLE_VERSION) $(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(STABLE_VERSION) 2> /dev/null || :

.PHONY: default clean
