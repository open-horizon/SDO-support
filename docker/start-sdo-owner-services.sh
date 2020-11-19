#!/bin/bash

# Used *inside* the sdo-owner-services container to start all of the SDO services the Horizon management hub (IoT platform/owner) needs.

# Defaults/constants
opsPortDefault='8042'
rvPortDefault='8040'
ocsApiPortDefault='9008'
keyPassDefault='MLP3QA!Z'
rvVoucherTtlDefault='7200'

# These can be passed in via CLI args or env vars
ocsDbDir="${1:-$SDO_OCS_DB_PATH}"
ocsApiPort="${2:-${SDO_OCS_API_PORT:-$ocsApiPortDefault}}"

keyPass="${SDO_KEY_PWD:-$keyPassDefault}"
opsPort=${SDO_OPS_PORT:-$opsPortDefault}
opsExternalPort=${SDO_OPS_EXTERNAL_PORT:-$opsPort}
rvPort=${SDO_RV_PORT:-$rvPortDefault}
#VERBOSE='true'   # let it be set by the container provisioner

if [[ "$1" == "-h" || "$1" == "--help" || -z "$SDO_OCS_DB_PATH" || -z "$SDO_OCS_API_PORT" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [<ocs-db-path>] [<ocs-api-port>]

Environment variables that can be used instead of CLI args: SDO_OCS_DB_PATH, SDO_OCS_API_PORT
Required environment variables: HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_ORG_ID
Recommended environment variables: HZN_MGMT_HUB_CERT (unless the mgmt hub uses http or a CA-trusted certificate), SDO_KEY_PWD (unless using sample key files)
Additional environment variables: SDO_RV_PORT, SDO_OPS_PORT, SDO_OPS_EXTERNAL_PORT, EXCHANGE_INTERNAL_URL, VERBOSE
EndOfMessage
    exit 1
fi

# Only echo this if VERBOSE is 1 or true
verbose() {
    if [[ "$VERBOSE" == '1' || "$VERBOSE" == 'true' ]]; then
        echo 'Verbose:' "$*"
    fi
}

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

# These env vars are needed by ocs-api to set up the common config files for ocs
if [[ -z "$HZN_EXCHANGE_URL" || -z "$HZN_FSS_CSSURL" || -z "$HZN_ORG_ID" || -z "$SDO_OWNER_SVC_HOST" ]]; then
    echo "Error: all of these environment variables must be set: HZN_EXCHANGE_URL, HZN_FSS_CSSURL, HZN_ORG_ID, SDO_OWNER_SVC_HOST"
fi

echo "Using ports: RV: $rvPort, OPS: $opsPort, OPS external: $opsExternalPort, OCS-API: $ocsApiPort"
echo "Using external SDO_OWNER_SVC_HOST: $SDO_OWNER_SVC_HOST (for now only used for external OPS host)"

# So to0scheduler will point RV (and by extension, the device) to the correct OPS host. Can be a hostname or IP address
if [[ $SDO_OWNER_SVC_HOST =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # IP address
    sed -i -e "s|^ip=.*|ip=${SDO_OWNER_SVC_HOST}|" -e "s|^dns=.*|dns=|" to0scheduler/config/redirect.properties
    chk $? 'sed ip in to0scheduler/config/redirect.properties'
else
    # hostname
    sed -i -e "s|^dns=.*|dns=${SDO_OWNER_SVC_HOST}|" to0scheduler/config/redirect.properties
    chk $? 'sed dns in to0scheduler/config/redirect.properties'
fi

# If using a non-default port number for OPS, configure both ops and to0scheduler with that value
if [[ "$opsPort" != "$opsPortDefault" ]]; then
    #sed -i -e "s|^server.port=.*|server.port=${opsPort}|" ops/config/application.properties
    #chk $? 'sed port in ops/config/application.properties'
    sed -i -e "s|^SERVER_PORT=.*|SERVER_PORT=${opsPort}|" ops/ops.env
    chk $? 'sed port in ops/ops.env'
fi
if [[ "$opsExternalPort" != "$opsPortDefault" ]]; then
    sed -i -e "s|^port=.*|port=${opsExternalPort}|" to0scheduler/config/redirect.properties
    chk $? 'sed port in to0scheduler/config/redirect.properties'
fi

# If using a non-default port number for the RV to listen on inside the container, configure RV with that value
if [[ "$rvPort" != "$rvPortDefault" ]]; then
    sed -i -e "s|^server.port=.*|server.port=${rvPort}|" rv/application.properties
    chk $? 'sed port in rv/application.properties'
fi

# This sed is for dev/test/demo and makes the to0scheduler respond to changes more quickly, and let us use the same voucher over again
#todo: should we not do this for production? If so, add an env var that will do this for dev/test
#sed -i -e 's|^to0.scheduler.interval=.*|to0.scheduler.interval=5|' -e 's|^to2.credential-reuse.enabled=.*|to2.credential-reuse.enabled=true|' ocs/config/application.properties
#chk $? 'sed ocs/config/application.properties'
sed -i -e 's|^TO0_SCHEDULER_INTERVAL=.*|TO0_SCHEDULER_INTERVAL=5|' -e 's|^TO2_CREDENTIAL_REUSE_ENABLED=.*|TO2_CREDENTIAL_REUSE_ENABLED=true|' ocs/ocs.env
chk $? 'sed ocs/ocs.env'

# Sometimes during dev/test, it is useful for the vouchers to persist in RV longer than the default 2 hours
if [[ -n $SDO_RV_VOUCHER_TTL && $SDO_RV_VOUCHER_TTL != $rvVoucherTtlDefault ]]; then
    echo "Setting RV voucher TTL (to0.waitseconds) to $SDO_RV_VOUCHER_TTL ..."
    #sed -i -e "s|^to0.waitseconds=.*|to0.waitseconds=${SDO_RV_VOUCHER_TTL}|" ocs/config/application.properties
    #chk $? 'sed to0.waitseconds ocs/config/application.properties'
    sed -i -e "s|^TO0_WAITSECONDS=.*|TO0_WAITSECONDS=${SDO_RV_VOUCHER_TTL}|" ocs/ocs.env
    chk $? 'sed to0.waitseconds ocs/ocs.env'
fi

# Need to move this file into the ocs db *after* the docker run mount is done
# If the user specified their own owner private key, run-sdo-owner-services.sh will mount it at ocs/config/owner-keystore.p12, otherwise use the default
mkdir -p $ocsDbDir/v1/creds
# first check pw for length and disallowed chars (that cause the sed cmds below to fail)
# Note: keyPass is always set, because it is set to the default pw if SDO_KEY_PWD not set
if [[ ${#keyPass} -lt 6 || $keyPass == *$'\n'* || $keyPass == *'|'* ]]; then
    # newlines and vertical bars aren't allowed in the pw, because they cause the sed cmds below to fail
    echo "Error: SDO_KEY_PWD must be at least 6 characters and not contain newlines or '|'"
    exit 1
fi
# Note: ocs/config/application.properties is NOT in the volume, so the keystore-password setting is the default every time our container starts
if [[ -s 'ocs/config/owner-keystore.p12' ]]; then
    echo "Using your owner keystore"
    echo "Verifying SDO_KEY_PWD or default is correct for your owner keystore..."
    echo "$keyPass" | /usr/lib/jvm/openjre-11-manual-installation/bin/keytool -list -v -keystore "$ownerPrivateKey" >/dev/null 2>&1
    chk $? 'Checking if SDO_KEY_PWD is correct'
    if [[ "$keyPass" != "$keyPassDefault" ]]; then
        #echo "Updating fs.owner.keystore-password value in ocs/config/application.properties ..."
        #verbose sed -i -e "s|^fs.owner.keystore-password=.*|fs.owner.keystore-password=${keyPass}|" ocs/config/application.properties
        #sed -i -e "s|^fs.owner.keystore-password=.*|fs.owner.keystore-password=${keyPass}|" ocs/config/application.properties
        #chk $? 'sed password in ocs/config/application.properties'
        echo "Updating FS_OWNER_KEYSTORE_PASSWORD value in ocs/ocs.env ..."
        verbose sed -i -e "s|^FS_OWNER_KEYSTORE_PASSWORD=.*|FS_OWNER_KEYSTORE_PASSWORD=${keyPass}|" ocs/ocs.env
        sed -i -e "s|^fs.FS_OWNER_KEYSTORE_PASSWORD=.*|FS_OWNER_KEYSTORE_PASSWORD=${keyPass}|" ocs/ocs.env
        chk $? 'sed password in ocs/ocs.env'
    fi
    cp ocs/config/owner-keystore.p12 $ocsDbDir/v1/creds   # need to copy it, because can't move a mounted file
elif [[ -s "$ocsDbDir/v1/creds/owner-keystore.p12" ]]; then
    echo "Existing owner keystore found..."
    echo "Verifying SDO_KEY_PWD or default is correct for existing owner keystore..."
    echo "$keyPass" | /usr/lib/jvm/openjre-11-manual-installation/bin/keytool -list -v -keystore "$ocsDbDir/v1/creds/owner-keystore.p12" >/dev/null 2>&1
    chk $? 'Checking if SDO_KEY_PWD is correct'
    if [[ "$keyPass" != "$keyPassDefault" ]]; then
        #echo "Updating fs.owner.keystore-password value in ocs/config/application.properties ..."
        #verbose sed -i -e "s|^fs.owner.keystore-password=.*|fs.owner.keystore-password=${keyPass}|" ocs/config/application.properties
        #sed -i -e "s|^fs.owner.keystore-password=.*|fs.owner.keystore-password=${keyPass}|" ocs/config/application.properties
        #chk $? 'sed password in ocs/config/application.properties'
        echo "Updating FS_OWNER_KEYSTORE_PASSWORD value in ocs/ocs.env ..."
        verbose sed -i -e "s|^FS_OWNER_KEYSTORE_PASSWORD=.*|FS_OWNER_KEYSTORE_PASSWORD=${keyPass}|" ocs/ocs.env
        sed -i -e "s|^FS_OWNER_KEYSTORE_PASSWORD=.*|FS_OWNER_KEYSTORE_PASSWORD=${keyPass}|" ocs/ocs.env
        chk $? 'sed password in ocs/ocs.env'
    fi
else
    # Use the default key file that Dockerfile stored, ocs/config/sample-owner-keystore.p12, but name it owner-keystore.p12
    echo "Using sample owner keystore..."
    if [[ "$keyPass" != "$keyPassDefault" ]]; then
        echo "Changing sample owner keystore password from default to SDO_KEY_PWD ..."
        /usr/lib/jvm/openjre-11-manual-installation/bin/keytool -storepasswd -keystore ocs/config/sample-owner-keystore.p12 -storepass $keyPassDefault -new $keyPass
        chk $? 'Changing Sample Owner Keystore password'
        #echo "Updating fs.owner.keystore-password value in ocs/config/application.properties ..."
        #verbose sed -i -e "s|^fs.owner.keystore-password=.*|fs.owner.keystore-password=${keyPass}|" ocs/config/application.properties
        #sed -i -e "s|^fs.owner.keystore-password=.*|fs.owner.keystore-password=${keyPass}|" ocs/config/application.properties
        #chk $? 'sed password in ocs/config/application.properties'
        echo "Updating FS_OWNER_KEYSTORE_PASSWORD value in ocs/ocs.env ..."
        verbose sed -i -e "s|^FS_OWNER_KEYSTORE_PASSWORD=.*|FS_OWNER_KEYSTORE_PASSWORD=${keyPass}|" ocs/ocs.env
        sed -i -e "s|^FS_OWNER_KEYSTORE_PASSWORD=.*|FS_OWNER_KEYSTORE_PASSWORD=${keyPass}|" ocs/ocs.env
        chk $? 'sed password in ocs/ocs.env'
    fi
    mv ocs/config/sample-owner-keystore.p12 $ocsDbDir/v1/creds/owner-keystore.p12
fi

# Run all of the services
echo "Starting rendezvous service..."
(cd rv && ./rendezvous) &   #todo: convert to sdo/rendezvous-service-v1.9.0 (with redis)
#todo: remove the env cmds below
echo "Starting to0scheduler service..."
(cd to0scheduler/config && eval export $(sed -e '/^ *#/d' -e '/^$/d' -e "s/=\(.*\)$/='\1'/" ../to0scheduler.env) && echo '===== TO0SCHEDULER =====' && env && ./run-to0scheduler) &
echo "Starting ocs service..."
(cd ocs/config && eval export $(sed -e '/^ *#/d' -e '/^$/d' -e "s/=\(.*\)$/='\1'/" ../ocs.env) && echo '===== OCS =====' && env && ./run-ocs) &
echo "Starting ops service..."
(cd ops/config && eval export $(sed -e '/^ *#/d' -e '/^$/d' -e "s/=\(.*\)$/='\1'/" ../ops.env) && echo '===== OPS =====' && env && ./run-ops) &
echo "Starting ocs-api service..."
${0%/*}/ocs-api $ocsApiPort $ocsDbDir  # run this in the foreground so the start cmd doesn't end
