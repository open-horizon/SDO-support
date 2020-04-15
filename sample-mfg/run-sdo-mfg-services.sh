#!/bin/bash

# Run the SDO SCT services (manufacturer and mariadb) on a device so that device initialization can be run.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: ${0##*/} [<image-version>]"
    echo "Required environment variables: "
    echo "Recommended environment variables: "
    exit 1
fi

# These env vars are required
#: ${HZN_EXCHANGE_URL:?} ${HZN_FSS_CSSURL:?} ${HZN_MGMT_HUB_CERT:?} ${HZN_ORG_ID:?} ${HZN_EXCHANGE_USER_AUTH:?}

VERSION="${1:-latest}"

# Manufacturer container values (from SCT docker-compose.yml)
DOCKER_NETWORK=${DOCKER_NETWORK:-sct_default}
DOCKER_REGISTRY=${DOCKER_REGISTRY:-openhorizon}
SDO_MFG_DOCKER_IMAGE=${SDO_MFG_DOCKER_IMAGE:-manufacturer}
SDO_MFG_HOST_PORT=${SDO_MFG_HOST_PORT:-8039}
SDO_MFG_CONTAINER_PORT=${SDO_MFG_CONTAINER_PORT:-8080}
SDO_MFG_KEYS_HOST_DIR=${SDO_MFG_KEYS_HOST_DIR:-$PWD/keys}
SDO_MFG_KEYS_CONTAINER_DIR=${SDO_MFG_KEYS_CONTAINER_DIR:-/keys}

SPRING_DATASOURCE_URL=${SPRING_DATASOURCE_URL:-jdbc:mariadb://mariadb:3306/intel_sdo}
SPRING_DATASOURCE_USERNAME=${SPRING_DATASOURCE_USERNAME:-sdo}
SPRING_DATASOURCE_PASSWORD=${SPRING_DATASOURCE_PASSWORD:-sdo}
SDO_KEYSTORE=${SDO_KEYSTORE:-file://keys/sdo.p12}
SDO_KEYSTORE_PASSWORD=${SDO_KEYSTORE_PASSWORD:-123456}
TZ=${TZ:-America/Los_Angeles}

# Mariadb container values (from SCT docker-compose.yml)
SDO_MARIADB_DOCKER_IMAGE=${SDO_MARIADB_DOCKER_IMAGE:-sct_mariadb}
SDO_MARIADB_DOCKER_CONTAINER=${SDO_MARIADB_DOCKER_IMAGE:-mariadb}
SDO_MARIADB_PORT=${SDO_MARIADB_PORT:-3306}

MYSQL_DATABASE=${MYSQL_DATABASE:-intel_sdo}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}
MYSQL_USER=${MYSQL_USER:-sdo}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-sdo}
TZ=${TZ:-America/Los_Angeles}


# Check the exit code passed in and exit if non-zero
chk() {
    local exitCode=$1
    local task=$2
    local dontExit=$3   # set to 'continue' to not exit for this error
    if [[ $1 == 0 ]]; then return; fi
    echo "Error: exit code $exitCode from: $task"
    if [[ $dontExit != 'continue' ]]; then
        exit $exitCode
    fi
}

# Shut down previous containers, in case they left them running
docker rm -f $SDO_MFG_DOCKER_IMAGE 2> /dev/null
docker rm -f $SDO_MARIADB_DOCKER_IMAGE 2> /dev/null
docker network rm $DOCKER_NETWORK 2> /dev/null

# Create docker network the 2 containers use to communicated
docker network create $DOCKER_NETWORK
chk $? 'creating SCT network'

# Run the sct_mariadb container
docker pull $DOCKER_REGISTRY/$SDO_MARIADB_DOCKER_IMAGE:$VERSION
chk $? 'pulling mariadb image'
docker run --name $SDO_MARIADB_DOCKER_CONTAINER --network $DOCKER_NETWORK -dt -p $SDO_MARIADB_PORT:$SDO_MARIADB_PORT -e "MYSQL_DATABASE=$MYSQL_DATABASE" -e "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" -e "MYSQL_USER=$MYSQL_USER" -e "MYSQL_PASSWORD=$MYSQL_PASSWORD" -e "TZ=$TZ" $DOCKER_REGISTRY/$SDO_MARIADB_DOCKER_IMAGE:$VERSION
chk $? 'running mariadb image'

# Run the manufacturer container
docker pull $DOCKER_REGISTRY/$SDO_MFG_DOCKER_IMAGE:$VERSION
chk $? 'pulling manufacturer image'
docker run --name $SDO_MFG_DOCKER_IMAGE --network $DOCKER_NETWORK -dt -v $SDO_MFG_KEYS_HOST_DIR:$SDO_MFG_KEYS_CONTAINER_DIR:ro -p $SDO_MFG_HOST_PORT:$SDO_MFG_CONTAINER_PORT -e "SPRING_DATASOURCE_URL=$SPRING_DATASOURCE_URL" -e "SPRING_DATASOURCE_USERNAME=$SPRING_DATASOURCE_USERNAME" -e "SPRING_DATASOURCE_PASSWORD=$SPRING_DATASOURCE_PASSWORD" -e "SDO_KEYSTORE=$SDO_KEYSTORE" -e "SDO_KEYSTORE_PASSWORD=$SDO_KEYSTORE_PASSWORD" -e "TZ=$TZ" $DOCKER_REGISTRY/$SDO_MFG_DOCKER_IMAGE:$VERSION
chk $? 'running manufacturer image'
