#!/bin/bash

# Run the sdo-owner-services container on the Horizon management hub (IoT platform/owner.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [<image-version>] [<owner-private-key-file>]

Arguments:
  <image-version>  The image tag to use. Defaults to '1.10'
  <owner-private-key-file>  The p12 private key you have created to use with the sdo-owner-services. Must supply the corresponding public key to sample-mfg/simulate-mfg.sh. If the private key isn't specified here, the default is keys/sample-owner-keystore.p12

Required environment variables:
  HZN_EXCHANGE_URL - the external URL of the exchange (used for authentication delegation and in the configuration of the device)
  HZN_FSS_CSSURL - the external URL of CSS (used in the configuration of the device)
  HZN_ORG_ID - the exchange cluster org id (used for authentication delegation)
  HZN_MGMT_HUB_CERT - the base64 encoded content of the management hub cluster self-signed certificate (can be set to 'N/A' if the mgmt hub does not require a cert)

Recommended environment variables:
  SDO_KEY_PWD - The password for your generated keystore. This password must be passed into the Dockerfile so that start-sdo-owner-services.sh can mount to $containerHome/ocs/config/application.properties/fs.owner.keystore-password
  SDO_OWNER_SVC_HOST - external hostname or IP that the RV should tell the device to reach OPS at. Defaults to the host's hostname but that is only sufficient if it is resolvable and externally accessible.

Additional environment variables (that do not usually need to be set):
  SDO_RV_PORT - port number RV should listen on *inside* the container. Default is 8040.
  SDO_OPS_PORT - port number OPS should listen on *inside* the container. Default is 8042.
  SDO_OPS_EXTERNAL_PORT - external port number that RV should tell the device to reach OPS at. Defaults to the internal OPS port number.
  SDO_OCS_API_PORT - port number OCS-API should listen on *inside* the container. Default is 9008.
  EXCHANGE_INTERNAL_URL - how OCS-API should contact the exchange for authentication. Will default to HZN_EXCHANGE_URL.
  AGENT_INSTALL_URL - where to get agent-install.sh from. Valid values: file:///<path-to-agent-install> (will be mounted into the container), https://raw.githubusercontent.com/open-horizon/anax/master/agent-install/agent-install.sh (get the most recently committed version), https://github.com/open-horizon/anax/releases/latest/download/agent-install.sh (the latest tested patch version - this is the default)
  SDO_GET_PKGS_FROM - where to have the edge devices get the horizon packages from. If set to css:, it will be expanded to css:/api/v1/objects/IBM/agent_files. If set to https://github.com/open-horizon/anax/releases it will be expanded to https://github.com/open-horizon/anax/releases/latest/download (default).
  SDO_RV_VOUCHER_TTL - tell the rendezvous server to persist vouchers for this number of seconds (default 7200).
  VERBOSE - set to 1 or 'true' for more verbose output.
EndOfMessage
    exit 1
fi

# These env vars are required
: ${HZN_EXCHANGE_URL:?} ${HZN_FSS_CSSURL:?} ${HZN_MGMT_HUB_CERT:?} ${HZN_ORG_ID:?}
# If their mgmt hub doesn't need a self-signed cert, we chose to make them set HZN_MGMT_HUB_CERT to 'N/A' to ensure they didn't just forget to specify this env var
if [[ $HZN_MGMT_HUB_CERT == 'N/A' || $HZN_MGMT_HUB_CERT == 'n/a' ]]; then
    unset HZN_MGMT_HUB_CERT
fi

VERSION="${1:-1.10}"
ownerPrivateKey="$2"
if [[ -n "$ownerPrivateKey" && ! -f "$ownerPrivateKey" ]]; then
    echo "Error: specified owner-private-key-file '$ownerPrivateKey' does not exist."
    exit 2
fi


DOCKER_REGISTRY=${DOCKER_REGISTRY:-openhorizon}
SDO_DOCKER_IMAGE=${SDO_DOCKER_IMAGE:-sdo-owner-services}
containerHome=/home/sdouser

#SDO_OCS_DB_HOST_DIR=${SDO_OCS_DB_HOST_DIR:-$PWD/ocs-db}  # we are now using a named volume instead of a host dir
# this is where OCS needs it to be
SDO_OCS_DB_CONTAINER_DIR=${SDO_OCS_DB_CONTAINER_DIR:-$containerHome/ocs/config/db}

export SDO_OCS_API_PORT=${SDO_OCS_API_PORT:-9008}
export SDO_RV_PORT=${SDO_RV_PORT:-8040}   # the port RV should listen on *inside* the container
export SDO_OPS_PORT=${SDO_OPS_PORT:-8042}   # the port OPS should listen on *inside* the container
export SDO_OPS_EXTERNAL_PORT=${SDO_OPS_EXTERNAL_PORT:-$SDO_OPS_PORT}   # the external port the device should use to contact OPS
#SDO_TO0_PORT=${SDO_TO0_PORT:-8049}  # the to0scheduler traffic is all internal to our container, so doesn't need to be overridden

# Define the OPS hostname the to0scheduler tells RV to direct the booting device to
SDO_OWNER_SVC_HOST=${SDO_OWNER_SVC_HOST:-$(hostname)}   # currently only used for OPS

AGENT_INSTALL_URL=${AGENT_INSTALL_URL:-https://github.com/open-horizon/anax/releases/latest/download/agent-install.sh}
SDO_GET_PKGS_FROM=${SDO_GET_PKGS_FROM:-https://github.com/open-horizon/anax/releases/latest/download}

# Check the exit code passed in and exit if non-zero
chk() {
    local exitCode=$1
    local task=$2
    local dontExit=$3   # set to 'continue' to not exit for this error
    if [[ $exitCode == 0 ]]; then return; fi
    echo "Error: exit code $exitCode from: $task"
    if [[ $dontExit != 'continue' ]]; then
        exit $exitCode
    fi
}

# If docker isn't installed, do that
if ! command -v docker >/dev/null 2>&1; then
    if [[ $(whoami) != 'root' ]]; then
        echo "Error: docker is not installed, but we are not root, so can not install it for you. Exiting"
        exit 2
    fi
    echo "Docker is required, installing it..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    chk $? 'adding docker repository key'
    add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    chk $? 'adding docker repository'
    apt-get install -y docker-ce docker-ce-cli containerd.io
    chk $? 'installing docker'
fi

# Make sure SDO_KEY_PWD is set and Mount the owner private key into the container, if they provided one
if [[ -n "$ownerPrivateKey" ]]; then
  if [[ -z "$SDO_KEY_PWD" ]]; then
    echo "SDO_KEY_PWD is not set"
    exit 1
  elif [[ -n "$SDO_KEY_PWD" ]] && [[ ${#SDO_KEY_PWD} -lt 6 ]]; then
    while [[ ${#SDO_KEY_PWD} -lt 6 ]];
      do
        echo "SDO_KEY_PWD not long enough. Needs at least 6 characters"
        exit 1
      done
  elif [[ -n "$SDO_KEY_PWD" ]]; then
    echo "$SDO_KEY_PWD" | keytool -list -v -keystore "$ownerPrivateKey" >/dev/null 2>&1
    chk $? 'Checking if SDO_KEY_PWD is correct'
  fi
  privateKeyMount="-v $PWD/$ownerPrivateKey:$containerHome/ocs/config/owner-keystore.p12:ro"
fi

# else inside the container start-sdo-owner-services.sh will use the default key file that Dockerfile set up

if [[ ${AGENT_INSTALL_URL:0:8} == 'file:///' ]]; then
    agentInstallFlag="-v ${AGENT_INSTALL_URL#file:///}:$containerHome/agent-install.sh:ro"
elif [[ ${AGENT_INSTALL_URL:0:4} == 'http' ]]; then
    agentInstallFlag="-e AGENT_INSTALL_URL=$AGENT_INSTALL_URL"
else
    echo "Error: invalid AGENT_INSTALL_URL value: $AGENT_INSTALL_URL"
    exit 1
fi

#For testing purposes
if [[ "$DOCKER_DONTPULL" == '1' || "$DOCKER_DONTPULL" == 'true' ]]; then
    echo "Using local Dockerfile, because DOCKER_DONTPULL=$DOCKER_DONTPULL"
else
# If VERSION is a generic tag like latest, 1.10, or testing we have to make sure we pull the most recent
    docker pull $DOCKER_REGISTRY/$SDO_DOCKER_IMAGE:$VERSION
    chk $? 'Pulling from Docker Hub...'
fi
# Run the service container
docker run --name $SDO_DOCKER_IMAGE -dt --mount "type=volume,src=sdo-ocs-db,dst=$SDO_OCS_DB_CONTAINER_DIR" $privateKeyMount $agentInstallFlag -p $SDO_OCS_API_PORT:$SDO_OCS_API_PORT -p $SDO_RV_PORT:$SDO_RV_PORT -p $SDO_OPS_PORT:$SDO_OPS_PORT -e "SDO_KEY_PWD=$SDO_KEY_PWD" -e "SDO_OWNER_SVC_HOST=$SDO_OWNER_SVC_HOST" -e "SDO_OCS_DB_PATH=$SDO_OCS_DB_CONTAINER_DIR" -e "SDO_OCS_API_PORT=$SDO_OCS_API_PORT" -e "SDO_RV_PORT=$SDO_RV_PORT" -e "SDO_OPS_PORT=$SDO_OPS_PORT" -e "SDO_OPS_EXTERNAL_PORT=$SDO_OPS_EXTERNAL_PORT" -e "HZN_EXCHANGE_URL=$HZN_EXCHANGE_URL" -e "EXCHANGE_INTERNAL_URL=$EXCHANGE_INTERNAL_URL" -e "HZN_FSS_CSSURL=$HZN_FSS_CSSURL" -e "HZN_ORG_ID=$HZN_ORG_ID" -e "HZN_MGMT_HUB_CERT=$HZN_MGMT_HUB_CERT" -e "SDO_GET_PKGS_FROM=$SDO_GET_PKGS_FROM" -e "SDO_RV_VOUCHER_TTL=$SDO_RV_VOUCHER_TTL" -e "VERBOSE=$VERBOSE" $DOCKER_REGISTRY/$SDO_DOCKER_IMAGE:$VERSION
