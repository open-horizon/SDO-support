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
  HZN_MGMT_HUB_CERT - the base64 encoded content of the management hub cluster ingress self-signed certificate (can be set to 'N/A' if the mgmt hub does not require a cert). If set, this certificate is given to the edge nodes in the HZN_MGMT_HUB_CERT_PATH variable.

Recommended environment variables:
  SDO_KEY_PWD - The password for your generated keystore. This password must be passed into the Dockerfile so that start-sdo-owner-services.sh can mount to $containerHome/ocs/config/application.properties/fs.owner.keystore-password
  SDO_OWNER_SVC_HOST - external hostname or IP that the RV should tell the device to reach OPS at. Defaults to the host's hostname but that is only sufficient if it is resolvable and externally accessible.

Additional environment variables (that do not usually need to be set):
  SDO_RV_PORT - port number RV should listen on *inside* the container. Default is 8040.
  SDO_OPS_PORT - port number OPS should listen on *inside* the container. Default is 8042.
  SDO_OPS_EXTERNAL_PORT - external port number that RV should tell the device to reach OPS at. Defaults to the internal OPS port number.
  SDO_OCS_API_PORT - port number OCS-API should listen on for HTTP. Default is 9008.
  SDO_OCS_API_TLS_PORT - port number OCS-API should listen on for TLS. Default is the value of SDO_OCS_API_PORT. (OCS API does not support TLS and non-TLS simultaneously.) Note: you can not set this to 9009, because OCS listens on that port internally.
  SDO_API_CERT_HOST_PATH - path on this host of the directory holding the certificate and key files named sdoapi.crt and sdoapi.key, respectively. Default is for the OCS-API to not support TLS.
  SDO_API_CERT_PATH - path that the directory holding the certificate and key files is mounted to within the container. Default is /home/sdouser/ocs-api-dir/keys .
  EXCHANGE_INTERNAL_URL - how OCS-API should contact the exchange for authentication. Will default to HZN_EXCHANGE_URL.
  EXCHANGE_INTERNAL_CERT - the base64 encoded certificate that OCS-API should use when contacting the exchange for authentication. Will default to the sdoapi.crt file in the directory specified by SDO_API_CERT_HOST_PATH.
  EXCHANGE_INTERNAL_RETRIES - the maximum number of times to try connecting to the exchange during startup to verify the connection info.
  EXCHANGE_INTERNAL_INTERVAL - the number of seconds to wait between attempts to connect to the exchange during startup
  SDO_GET_PKGS_FROM - where to have the edge devices get the horizon packages from. If set to css:, it will be expanded to css:/api/v1/objects/IBM/agent_files. Or it can be set to something like https://github.com/open-horizon/anax/releases/latest/download (which is the default).
  SDO_GET_CFG_FILE_FROM - where to have the edge devices get the agent-install.cfg file from. If set to css: (the default), it will be expanded to css:/api/v1/objects/IBM/agent_files/agent-install.cfg. Or it can set to agent-install.cfg, which means using the file that the SDO owner services creates.
  SDO_RV_VOUCHER_TTL - tell the rendezvous server to persist vouchers for this number of seconds (default 7200).
  VERBOSE - set to 1 or 'true' for more verbose output.
EndOfMessage
    exit 1
fi

# These env vars are required
: ${HZN_EXCHANGE_URL:?} ${HZN_FSS_CSSURL:?} ${HZN_MGMT_HUB_CERT:?}
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
export SDO_OCS_API_TLS_PORT=${SDO_OCS_API_TLS_PORT:-$SDO_OCS_API_PORT}
export SDO_API_CERT_PATH=${SDO_API_CERT_PATH:-/home/sdouser/ocs-api-dir/keys}   # this is the path *within* the container. Export SDO_API_CERT_HOST_PATH to use a cert/key.
export SDO_RV_PORT=${SDO_RV_PORT:-8040}   # the port RV should listen on *inside* the container
export SDO_OPS_PORT=${SDO_OPS_PORT:-8042}   # the port OPS should listen on *inside* the container
export SDO_OPS_EXTERNAL_PORT=${SDO_OPS_EXTERNAL_PORT:-$SDO_OPS_PORT}   # the external port the device should use to contact OPS
#SDO_TO0_PORT=${SDO_TO0_PORT:-8049}  # the to0scheduler traffic is all internal to our container, so doesn't need to be overridden

# Define the OPS hostname the to0scheduler tells RV to direct the booting device to
SDO_OWNER_SVC_HOST=${SDO_OWNER_SVC_HOST:-$(hostname)}   # currently only used for OPS

SDO_GET_PKGS_FROM=${SDO_GET_PKGS_FROM:-https://github.com/open-horizon/anax/releases/latest/download}
SDO_GET_CFG_FILE_FROM=${SDO_GET_CFG_FILE_FROM:-css:}

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

# Set the ocs-api port appropriately (the TLS port takes precedence, if set)
portNum=${SDO_OCS_API_TLS_PORT:-$SDO_OCS_API_PORT}

# Set the mount of the cert/key files, if specified
if [[ -n $SDO_API_CERT_HOST_PATH ]]; then
    fullHostPath=$SDO_API_CERT_HOST_PATH
    if [[ ${fullHostPath:0:1} != '/' ]]; then
        fullHostPath="$PWD/$fullHostPath"
    fi
    certKeyMount="-v $fullHostPath:$SDO_API_CERT_PATH"
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
docker run --name $SDO_DOCKER_IMAGE -dt --mount "type=volume,src=sdo-ocs-db,dst=$SDO_OCS_DB_CONTAINER_DIR" $privateKeyMount $certKeyMount -p $portNum:$portNum -p $SDO_RV_PORT:$SDO_RV_PORT -p $SDO_OPS_PORT:$SDO_OPS_PORT -e "SDO_KEY_PWD=$SDO_KEY_PWD" -e "SDO_OWNER_SVC_HOST=$SDO_OWNER_SVC_HOST" -e "SDO_OCS_DB_PATH=$SDO_OCS_DB_CONTAINER_DIR" -e "SDO_OCS_API_PORT=$SDO_OCS_API_PORT" -e "SDO_OCS_API_TLS_PORT=$SDO_OCS_API_TLS_PORT" -e "SDO_API_CERT_PATH=$SDO_API_CERT_PATH" -e "SDO_RV_PORT=$SDO_RV_PORT" -e "SDO_OPS_PORT=$SDO_OPS_PORT" -e "SDO_OPS_EXTERNAL_PORT=$SDO_OPS_EXTERNAL_PORT" -e "HZN_EXCHANGE_URL=$HZN_EXCHANGE_URL" -e "EXCHANGE_INTERNAL_URL=$EXCHANGE_INTERNAL_URL" -e "EXCHANGE_INTERNAL_CERT=$EXCHANGE_INTERNAL_CERT" -e "EXCHANGE_INTERNAL_RETRIES=$EXCHANGE_INTERNAL_RETRIES" -e "EXCHANGE_INTERNAL_INTERVAL=$EXCHANGE_INTERNAL_INTERVAL" -e "HZN_FSS_CSSURL=$HZN_FSS_CSSURL" -e "HZN_MGMT_HUB_CERT=$HZN_MGMT_HUB_CERT" -e "SDO_GET_PKGS_FROM=$SDO_GET_PKGS_FROM" -e "SDO_GET_CFG_FILE_FROM=$SDO_GET_CFG_FILE_FROM" -e "SDO_RV_VOUCHER_TTL=$SDO_RV_VOUCHER_TTL" -e "VERBOSE=$VERBOSE" $DOCKER_REGISTRY/$SDO_DOCKER_IMAGE:$VERSION
