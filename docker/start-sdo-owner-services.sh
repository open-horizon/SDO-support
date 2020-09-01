#!/bin/bash

# Used *inside* the sdo-owner-services container to start all of the SDO services the Horizon management hub (IoT platform/owner) needs.

# Defaults/constants
opsPortDefault='8042'
rvPortDefault='8040'
ocsApiPortDefault='9008'
keyPassDefault='MLP3QA!Z'

# These can be passed in via CLI args or env vars
ocsDbDir="${1:-$SDO_OCS_DB_PATH}"
ocsApiPort="${2:-${SDO_OCS_API_PORT:-$ocsApiPortDefault}}"

keyPass="${SDO_KEY_PWD:-$keyPassDefault}"
opsPort=${SDO_OPS_PORT:-$opsPortDefault}
opsExternalPort=${SDO_OPS_EXTERNAL_PORT:-$opsPort}
rvPort=${SDO_RV_PORT:-$rvPortDefault}

if [[ "$1" == "-h" || "$1" == "--help" || -z "$SDO_OCS_DB_PATH" || -z "$SDO_OCS_API_PORT" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [<ocs-db-path>] [<ocs-api-port>]
Environment variables that can be used instead of CLI args: SDO_OCS_DB_PATH, SDO_OCS_API_PORT
Required environment variables: HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_ORG_ID
Recommended environment variables: HZN_MGMT_HUB_CERT (unless the mgmt hub uses http or a CA-trusted certificate), SDO_KEY_PWD (unless using sample key files)
Additional environment variables: SDO_RV_PORT, SDO_OPS_PORT, SDO_OPS_EXTERNAL_PORT, EXCHANGE_INTERNAL_URL
EndOfMessage
    exit 1
fi

# These env vars are needed by ocs-api to set up the common config files for ocs
if [[ -z "$HZN_EXCHANGE_URL" || -z "$HZN_FSS_CSSURL" || -z "$HZN_ORG_ID" || -z "$SDO_OWNER_SVC_HOST" ]]; then
    echo "Error: all of these environment variables must be set: HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_ORG_ID, SDO_OWNER_SVC_HOST"
fi

echo "Using ports: RV: $rvPort, OPS: $opsPort, OPS external: $opsExternalPort, OCS-API: $ocsApiPort"
echo "Using external SDO_OWNER_SVC_HOST: $SDO_OWNER_SVC_HOST (for now only used for external OPS host)"

# So to0scheduler will point RV (and by extension, the device) to the correct OPS host. Can be a hostname or IP address
if [[ $SDO_OWNER_SVC_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # IP address
    #sed -i -e "s/^com.intel.sdo.to0.ownersign.to1d.bo.i1=.*$/com.intel.sdo.to0.ownersign.to1d.bo.i1=$SDO_OWNER_SVC_HOST/" -e "s/^com.intel.sdo.to0.ownersign.to1d.bo.dns1=.*$/com.intel.sdo.to0.ownersign.to1d.bo.dns1=/" to0scheduler/config/application.properties
    sed -i -e "s/^ip=.*$/ip=$SDO_OWNER_SVC_HOST/" -e "s/^dns=.*$/dns=/" to0scheduler/config/redirect.properties
else
    # hostname
    #sed -i -e "s/^com.intel.sdo.to0.ownersign.to1d.bo.dns1=.*$/com.intel.sdo.to0.ownersign.to1d.bo.dns1=$SDO_OWNER_SVC_HOST/" to0scheduler/config/application.properties
    sed -i -e "s/^dns=.*$/dns=$SDO_OWNER_SVC_HOST/" to0scheduler/config/redirect.properties
fi

# If using a non-default port number for OPS, configure both ops and to0scheduler with that value
if [[ "$opsPort" != "$opsPortDefault" ]]; then
    sed -i -e "s/^server.port=.*$/server.port=$opsPort/" ops/config/application.properties
fi
if [[ "$opsExternalPort" != "$opsPortDefault" ]]; then
    #sed -i -e "s/^com.intel.sdo.to0.ownersign.to1d.bo.port1=.*$/com.intel.sdo.to0.ownersign.to1d.bo.port1=$opsExternalPort/" to0scheduler/config/application.properties
    sed -i -e "s/^port=.*$/port=$opsExternalPort/" to0scheduler/config/redirect.properties
fi

# If using a non-default port number for the RV to listen on inside the container, configure RV with that value
if [[ "$rvPort" != "$rvPortDefault" ]]; then
    sed -i -e "s/^server.port=.*$/server.port=$rvPort/" rv/application.properties
fi

# If using a non-default keystore password for a generated key pair, configure OCS with that password
if [[ "$keyPass" != "$keyPassDefault" ]]; then
    sed -i -e "s/^fs.owner.keystore-password=.*$/fs.owner.keystore-password=$keyPass/" ocs/config/application.properties
fi

# This sed is for dev/test/demo and makes the to0scheduler respond to changes more quickly, and let us use the same voucher over again
#todo: should we not do this for production? If so, add an env var that will do this for dev/test
sed -i -e 's/^to0.scheduler.interval=.*$/to0.scheduler.interval=5/' -e 's/^to2.credential-reuse.enabled=.*$/to2.credential-reuse.enabled=true/' ocs/config/application.properties

# Need to move this file into the ocs db *after* the docker run mount is done
# If the user specified their own owner private key, run-sdo-owner-services.sh will mount it at ocs/config/owner-keystore.p12, otherwise use the default
mkdir -p $ocsDbDir/v1/creds
if [[ -f 'ocs/config/owner-keystore.p12' && $(wc -c ocs/config/owner-keystore.p12 | awk '{print $1}') -gt 0 ]]; then
    echo "Your Private Keystore Entry Has Been Found!"
    cp ocs/config/owner-keystore.p12 $ocsDbDir/v1/creds   # need to copy it, because can't move a mounted file
else
    # Use the default key file that Dockerfile stored, ocs/config/sample-owner-keystore.p12, but name it owner-keystore.p12
    echo "Using Sample Owner Private Keystore..."
    mv ocs/config/sample-owner-keystore.p12 $ocsDbDir/v1/creds/owner-keystore.p12
fi

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
