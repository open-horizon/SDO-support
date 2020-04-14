#!/bin/bash

# Used inside the sdo-owner-services container to start all of the SDO services the Horizon management hub (IoT platform/owner) needs.

# These can be passed in via CLI args or env vars
ocsDbDir="${1:-$SDO_OCS_DB_PATH}"
ocsApiPort="${2:-$OCS_API_PORT}"

if [[ "$1" == "-h" || "$1" == "--help" || -z "$SDO_OCS_DB_PATH" || -z "$OCS_API_PORT" ]]; then
    echo "Usage: ${0##*/} [<ocs-db-path>] [<ocs-api-port>]"
    echo "Environment variables that can be used instead of CLI args: SDO_OCS_DB_PATH, OCS_API_PORT"
    echo "Required environment variables: HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_ORG_ID, HZN_MGMT_HUB_CERT"
    exit 1
fi

# These env vars are needed by ocs-api to set up the common config files for ocs
if [[ -z "$HZN_EXCHANGE_URL" || -z "$HZN_FSS_CSSURL" || -z "$HZN_ORG_ID" || -z "$HZN_MGMT_HUB_CERT" || -z "$SDO_OWNER_SVC_HOST" ]]; then
    echo "Error: all of these environment variables must be set: HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_ORG_ID, HZN_MGMT_HUB_CERT, SDO_OWNER_SVC_HOST"
fi

# Define the hostnames the services use to find each other (this must be done here and not in the Dockerfile)
#todo: is OwnerSDO needed?
#todo: change this when it is time to use the real RV
echo "127.0.0.1 RVSDO OwnerSDO" >> /etc/hosts

# So to0scheduler will point RV (and by extension, the device) to the correct OPS host.
sed -i -e "s/^com.intel.sdo.to0.ownersign.to1d.bo.dns1=.*$/com.intel.sdo.to0.ownersign.to1d.bo.dns1=$SDO_OWNER_SVC_HOST/" to0scheduler/config/application.properties

# Need to move this file into the ocs db *after* the docker run mount is done
#todo: how is it really supposed to get here?
mkdir -p $ocsDbDir/v1/creds
mv ocs/config/owner-keystore.p12 $ocsDbDir/v1/creds

# Run all of the services
echo "Starting rendezvous service..."
(cd rv && ./rendezvous) &
echo "Starting to0scheduler service..."
(cd to0scheduler/config && ./run-to0scheduler) &
echo "Starting ocs service..."
(cd ocs/config && ./run-ocs) &
echo "Starting ops service..."
(cd ops/config && ./run-ops) &
echo "Starting ocs-api service..."
${0%/*}/ocs-api $ocsApiPort $ocsDbDir  # run this in the foreground so the start cmd doesn't end
