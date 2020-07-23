SHELL ?= /bin/bash -e
export MFG_VERSION ?= latest

DOCKER_REGISTRY ?= openhorizon
SDO_MFG_DOCKER_IMAGE ?= manufacturer
SDO_MARIADB_DOCKER_IMAGE ?= sct_mariadb
SDO_MFG_USER ?= sdo
SDO_MFG_PW ?= sdo
SDO_SCT_MFG_DIR ?= ../sdo_sdk_binaries_linux_x64/SupplyChainTools/docker_manufacturer

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: $(SDO_MFG_DOCKER_IMAGE)

# Build the sample SDO mfg services docker images. Need to use our own version of docker-compose.yml, and modify settings.xml and tomcat-users.xml, but used the rest of the files from the sdo sdk.
# Note: even though Dockerfile-mariadb copies mt_config.sql into the container and that sets the RV URL in the DB, simulate-mfg.sh updates that table with the correct value specified by the user.
# Note: we use the original docker-compose.yml for building (because it is with the other files needed at build time) and only use our customized copy of docker-compose.yml at run time.
sdo-mfg-services:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	cd $(SDO_SCT_MFG_DIR) \
	  && sed -e 's/<your admin username>/$(SDO_MFG_USER)/' -e 's/<your admin password>/$(SDO_MFG_PW)/' settings.xml > settings.new && mv settings.new settings.xml \
	  && sed -e 's/<your admin username>/$(SDO_MFG_USER)/' -e 's/<your admin password>/$(SDO_MFG_PW)/' tomcat-users.xml > tomcat-users.new && mv tomcat-users.new tomcat-users.xml \
	  && docker-compose build

# Note: we currently use docker-compose up to run the containers.

# Push the SDO mfg docker images to the registry
publish-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)

# Push the SDO mfg docker images to the registry with stable tag
promote-sdo-mfg-services:
	docker tag $(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):stable
	docker push $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):stable
	docker tag $(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):stable
	docker push $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):stable

# Use this if you are on a machine where you did not build the images
pull-sdo-mfg-services:
	docker pull $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) 
	docker pull $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)
	docker tag $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) $(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION)

sdo_device_binaries_1.7_linux_x64.tar.gz: $(shell echo ../sdo_sdk_binaries_linux_x64/{demo/device,NOTICES/CRI,SDOClientIntel/hostapp_linux/*,SDOClientIntel/{sdo_7.dalp,sdo_8.dalp}}) sdo_device_binaries_1.7_linux_x64/cri/device-1.7*.jar
	mkdir -p sdo_device_binaries_1.7_linux_x64/{cri,demo,SDOClientIntel,NOTICES/CRI}
	cp -a ../sdo_sdk_binaries_linux_x64/demo/device sdo_device_binaries_1.7_linux_x64/demo/
	cp -a ../sdo_sdk_binaries_linux_x64/SDOClientIntel/hostapp_linux sdo_device_binaries_1.7_linux_x64/SDOClientIntel/
	cp -a ../sdo_sdk_binaries_linux_x64/SDOClientIntel/{sdo_7.dalp,sdo_8.dalp} sdo_device_binaries_1.7_linux_x64/SDOClientIntel/
	cp -a ../sdo_sdk_binaries_linux_x64/NOTICES/CRI/CRI_LICENSE.txt sdo_device_binaries_1.7_linux_x64/NOTICES/CRI/
	ls -l sdo_device_binaries_1.7_linux_x64/cri/device-1.7*.jar   # confirm they put the rebuilt device jar in the correct place
	tar -zcvf $@ sdo_device_binaries_1.7_linux_x64

clean:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	- docker rmi $(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MFG_DOCKER_IMAGE):$(MFG_VERSION) $(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) $(DOCKER_REGISTRY)/$(SDO_MARIADB_DOCKER_IMAGE):$(MFG_VERSION) 2> /dev/null || :

.PHONY: default clean
