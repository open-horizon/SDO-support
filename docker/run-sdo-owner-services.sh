#!/bin/bash

# Run the sdo-owner-services container on the Horizon management hub (IoT platform/owner.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: ${0##*/} [<image-version>]"
    echo "Required environment variables: HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_ORG_ID, HZN_MGMT_HUB_CERT, HZN_EXCHANGE_USER_AUTH"
    echo "Recommended environment variables: DOCKER_REGISTRY, SDO_DOCKER_IMAGE"
    exit 1
fi

# These env vars are required
: ${HZN_EXCHANGE_URL:?} ${HZN_FSS_CSSURL:?} ${HZN_MGMT_HUB_CERT:?} ${HZN_ORG_ID:?} ${HZN_EXCHANGE_USER_AUTH:?}

VERSION="${1:-latest}"

DOCKER_REGISTRY=${DOCKER_REGISTRY:-openhorizon}
SDO_DOCKER_IMAGE=${SDO_DOCKER_IMAGE:-sdo-owner-services}

SDO_OCS_DB_HOST_DIR=${SDO_OCS_DB_HOST_DIR:-$PWD/ocs-db}
# this is where OCS needs it to be
SDO_OCS_DB_CONTAINER_DIR=${SDO_OCS_DB_CONTAINER_DIR:-/root/ocs/config/db}
OCS_API_PORT=${OCS_API_PORT:-9008}
# These can't be overridden easily
SDO_RV_PORT=${SDO_RV_PORT:-8040}
SDO_TO0_PORT=${SDO_TO0_PORT:-8049}
SDO_OPS_PORT=${SDO_OPS_PORT:-8042}

# Define the OPS hostname the to0scheduler tells RV to direct the booting device to
SDO_OWNER_SVC_HOST=${SDO_OWNER_SVC_HOST:-$(hostname)}

# Run the service container
docker run --name $SDO_DOCKER_IMAGE -dt -v $SDO_OCS_DB_HOST_DIR:$SDO_OCS_DB_CONTAINER_DIR -p $OCS_API_PORT:$OCS_API_PORT -p $SDO_RV_PORT:$SDO_RV_PORT -p $SDO_TO0_PORT:$SDO_TO0_PORT -p $SDO_OPS_PORT:$SDO_OPS_PORT -e "SDO_OWNER_SVC_HOST=$SDO_OWNER_SVC_HOST" -e "SDO_OCS_DB_PATH=$SDO_OCS_DB_CONTAINER_DIR" -e "OCS_API_PORT=$OCS_API_PORT" -e "HZN_EXCHANGE_URL=$HZN_EXCHANGE_URL" -e "HZN_FSS_CSSURL=$HZN_FSS_CSSURL" -e "HZN_ORG_ID=$HZN_ORG_ID" -e "HZN_MGMT_HUB_CERT=$HZN_MGMT_HUB_CERT" -e "HZN_EXCHANGE_USER_AUTH=$HZN_EXCHANGE_USER_AUTH" $DOCKER_REGISTRY/$SDO_DOCKER_IMAGE:$VERSION
