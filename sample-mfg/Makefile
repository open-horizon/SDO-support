SHELL ?= /bin/bash -e
export MFG_VERSION ?= latest

DOCKER_REGISTRY ?= openhorizon
SDO_MFG_DOCKER_IMAGE ?= manufacturer
SDO_MARIADB_DOCKER_IMAGE ?= sct_mariadb
SDO_MFG_USER ?= sdo
SDO_MFG_PW ?= sdo

# can override this in the environment, e.g. set it to: --no-cache
DOCKER_OPTS ?=

default: $(SDO_MFG_DOCKER_IMAGE)

# Build the sample SDO mfg services docker images. Need to use our own version of docker-compose.yml, and modify settings.xml and tomcat-users.xml.
# Note: even though Dockerfile-mariadb copies mt_config.sql into the container and that sets the RV URL in the DB, simulate-mfg.sh updates that table with the correct value specified by the user
sdo-mfg-services:
	- docker rm -f $(SDO_MFG_DOCKER_IMAGE) $(SDO_MARIADB_DOCKER_IMAGE) 2> /dev/null || :
	cd ../sdo_sdk_binaries_linux_x64/SupplyChainTools/docker_manufacturer \
	  && sed -e 's/<your admin username>/$(SDO_MFG_USER)/' -e 's/<your admin password>/$(SDO_MFG_PW)/' settings.xml > settings.new && mv settings.new settings.xml \
	  && sed -e 's/<your admin username>/$(SDO_MFG_USER)/' -e 's/<your admin password>/$(SDO_MFG_PW)/' tomcat-users.xml > tomcat-users.new && mv tomcat-users.new tomcat-users.xml \
	  && docker-compose -f ../../../sample-mfg/docker-compose.yml build

# Note: we currently use docker-compose up to run the containers.

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
