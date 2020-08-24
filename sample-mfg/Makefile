SHELL ?= /bin/bash -e

# Use VERSION from the top-level Makefile as the default
export MFG_VERSION ?= $(shell grep -m 1 -E '^export VERSION \?=' ../Makefile | awk '{print$$4}')

DOCKER_REGISTRY ?= openhorizon
SDO_MFG_DOCKER_IMAGE ?= manufacturer
SDO_MARIADB_DOCKER_IMAGE ?= manufacturer-mariadb
#SDO_MFG_USER ?= admin
#SDO_MFG_PW ?= admin
SDO_SCT_MFG_DIR ?= ../sdo/supply-chain-tools-v1.8.0/docker_manufacturer

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: sdo-mfg-services

# Build the sample SDO mfg services docker images. The SDO docker-compose.yml will build images: manufacturer:1.8 and manufacturer-mariadb:1.8
# Note: even though Dockerfile-mariadb copies mt_config.sql into the container and that sets the RV URL in the DB, simulate-mfg.sh updates that table with the correct value specified by the user.
sdo-mfg-services:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	cp -a ../sdo/supply-chain-tools-v1.8.0/docker_manufacturer/docker-compose.yml .   #todo: i do not think this is necessary anymore
	cd $(SDO_SCT_MFG_DIR) && docker-compose build

# Note: we currently use docker-compose up to run the containers.

# Push the SDO mfg docker images to the registry with the testing tag
push-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(SDO_MFG_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):testing
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):testing
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):testing
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):testing

# Push the SDO mfg docker images to the registry with the latest tag
publish-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):latest
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):latest

# Push the SDO mfg docker images to the registry with stable tag
promote-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):stable
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):stable
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):stable
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):stable

# Use this if you are on a machine where you did not build the images
pull-sdo-mfg-services:
	docker pull $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(SDO_MFG_DOCKER_IMAGE):1.8 
	docker pull $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) $(SDO_MARIADB_DOCKER_IMAGE):1.8

#sdo_device_binaries_1.8_linux_x64.tar.gz: $(shell echo ../sdo_sdk_binaries_linux_x64/{demo/device,NOTICES/CRI,SDOClientIntel/hostapp_linux/*,SDOClientIntel/{sdo_7.dalp,sdo_8.dalp}}) sdo_device_binaries_1.8_linux_x64/cri/device-1.8*.jar
sdo_device_binaries_1.8_linux_x64.tar.gz:
	mkdir -p sdo_device_binaries_1.8_linux_x64/NOTICES
	cp -a ../sdo/pri-v1.8.0/device sdo_device_binaries_1.8_linux_x64/
	cp -a ../sdo/supply-chain-tools-v1.8.0/docker_manufacturer/docker-compose.yml sdo_device_binaries_1.8_linux_x64/
	cp -a ../sdo/supply-chain-tools-v1.8.0/docker_manufacturer/keys sdo_device_binaries_1.8_linux_x64/
	cp -a ../keys/sample-owner-key.pub sdo_device_binaries_1.8_linux_x64/keys/
	#cp -a ../sdo_sdk_binaries_linux_x64/SDOClientIntel/hostapp_linux sdo_device_binaries_1.8_linux_x64/SDOClientIntel/
	#cp -a ../sdo_sdk_binaries_linux_x64/SDOClientIntel/{sdo_7.dalp,sdo_8.dalp} sdo_device_binaries_1.8_linux_x64/SDOClientIntel/
	cp -a ../sdo/NOTICES/pri/NOTICE sdo_device_binaries_1.8_linux_x64/NOTICES/
	tar -zcvf $@ sdo_device_binaries_1.8_linux_x64

clean:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(SDO_MFG_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(SDO_MARIADB_DOCKER_IMAGE):1.8 $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) 2> /dev/null || :

.PHONY: default clean
