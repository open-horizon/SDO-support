#!/bin/bash

# On a linux VM, simulate the steps a device manufacturer would do:
#   - DI (device initialization)
#   - create the mfg voucher
#   - extend the voucher to the owner (buyer)
#   - switch the device into owner mode

# This script starts/uses the SCT (Supply Chain Tool) services. See the Intel SDO SCT Manufacturer Enablement Guide

usage() {
    exitCode=${1:-0}
    cat << EndOfMessage
Usage: ${0##*/} [<mfg-priv-key-file>] [<owner-pub-key-file>]

Arguments:
  <mfg-priv-key-file>  Device manufacturer private key. If not specified, it will use SDO-support/sample-mfg/keys/sample-mfg-key.p12 (only valid for dev/test/demo)
  <owner-pub-key-file>  Device customer/owner public key. This is needed to extend the voucher to the owner. If not specified, it will use SDO-support/keys/sample-owner-key.pub (only valid for dev/test/demo)

Required Environment Variables:
  SDO_RV_URL: usually the dev RV running in the sdo-owner-services. To use the real Intel RV service, set to http://sdo-sbx.trustedservices.intel.com or http://sdo.trustedservices.intel.com and register your public key with Intel.

Optional Environment Variables:
  SDO_MFG_IMAGE_TAG - version of the manufacturer and sct_mariadb docker images that should be used. Defaults to 'stable'.
  HZN_MGMT_HUB_CERT - the base64 encoded content of the SDO owner services self-signed certificate (if it requires that). This is normally not necessary, because the SDO protocols are secure over HTTP.
  SDO_SAMPLE_MFG_KEEP_SVCS: set to 'true' to skip shutting down the mfg docker containers. This is faster if running this script repeatedly.

${0##*/} must be run in a directory where it has access to create a few files and directories.
EndOfMessage
    exit $exitCode
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage 0
fi
: ${SDO_RV_URL:?}

SDO_MFG_IMAGE_TAG=${SDO_MFG_IMAGE_TAG:-stable}

sampleMfgRepo=${SDO_SUPPORT_REPO:-https://raw.githubusercontent.com/open-horizon/SDO-support/stable}
privateKeyFile=${1:-$sampleMfgRepo/sample-mfg/keys/sample-mfg-key.p12}
ownerPubKeyFile=${2:-$sampleMfgRepo/keys/sample-owner-key.pub}
rvUrl="$SDO_RV_URL"   # the external rv url that the device should reach it at
useNativeClient=${SDO_DEVICE_USE_NATIVE_CLIENT:-false}   # future: add cmd line flag for this too

dbUser='sdo_admin'
dbPw='sdo'

# Only echo this if VERBOSE is 1 or true
verbose() {
    if [[ "$VERBOSE" == "1" || "$VERBOSE" == "true" ]]; then
        echo 'verbose:' $*
    fi
}

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

# Check both the exit code and http code passed in and exit if non-zero
chkHttp() {
    local exitCode=$1
    local httpCode=$2
    local task=$3
    local dontExit=$4   # set to 'continue' to not exit for this error
    chk $exitCode $task
    if [[ $httpCode == 200 ]]; then return; fi
    echo "Error: http code $httpCode from: $task"
    if [[ $dontExit != 'continue' ]]; then
        exit $httpCode
    fi
}

# Verify that the prereq commands we need are installed
confirmcmds() {
    for c in $*; do
        #echo "checking $c..."
        if ! which $c >/dev/null; then
            echo "Error: $c is not installed but required, exiting"
            exit 2
        fi
    done
}

ensureWeAreRoot() {
    if [[ $(whoami) != 'root' ]]; then
        echo "Error: must be root to run ${0##*/} with these options."
        exit 2
    fi
}

# Parses the voucher to get the UUID of the device (which will be our node id)
parseVoucher() {
    local voucherFile=$1
    local uuid=$(jq -r .oh.g $voucherFile | base64 -d | hexdump -v -e '/1 "%02x" ')
    chk $? 'parse voucher'
    echo "${uuid:0:8}-${uuid:8:4}-${uuid:12:4}-${uuid:16:4}-${uuid:20}"
}

confirmcmds grep curl ping docker docker-compose java

# Initial checking of input
# The mfg private key is either a URL we retrieve, or a file we use as-is
mkdir -p keys
if [[ ${privateKeyFile:0:4} == 'http' ]]; then
    echo "Getting $privateKeyFile ..."
    httpCode=$(curl -w "%{http_code}" --progress-bar -L -o keys/sdo.p12 $privateKeyFile)
    chkHttp $? $httpCode 'getting mfg private key'
    privateKeyFile='keys/sdo.p12'
elif [[ ! -f $privateKeyFile ]]; then
    echo "Error: $privateKeyFile does not exist"
    exit 1
fi

# The owner public key is either a URL we retrieve, or a file we use as-is
if [[ ${ownerPubKeyFile:0:4} == 'http' ]]; then
    echo "Getting $ownerPubKeyFile ..."
    httpCode=$(curl -w "%{http_code}" --progress-bar -L -o keys/owner-key.pub $ownerPubKeyFile)
    chkHttp $? $httpCode 'getting owner public key'
    ownerPubKeyFile='keys/owner-key.pub'
elif [[ ! -f $ownerPubKeyFile ]]; then
    echo "Error: $ownerPubKeyFile does not exist"
    exit 1
fi

# Ensure RV hostname is resolvable and pingable
rvHost=${rvUrl#http*://}   # strip protocol
rvHost=${rvHost%:*}   # strip optional port
if ! ping -c 1 -w 5 $rvHost > /dev/null 2>&1 ; then
    echo "Error: host $rvHost is not resolvable or pingable"
    exit 1
fi

# If they specified a self-signed cert, ensure we are root, then trust the cert.
# Note: this is a concession for some dev/test environments that may require it. Normally the device manufacturer won't initialize the device with a self-signed cert.
#       If the sdo owner service requires a self-signed cert for https, it should also listen on http, which is secure for the sdo protocol.
if [[ -n $HZN_MGMT_HUB_CERT ]]; then
    ensureWeAreRoot
    confirmcmds update-ca-certificates
    echo "Trusting HZN_MGMT_HUB_CERT ..."
    echo "$HZN_MGMT_HUB_CERT" | base64 --decode > /usr/local/share/ca-certificates/sdo-mgmt-hub.crt
    update-ca-certificates
    chk $? 'trusting HZN_MGMT_HUB_CERT'
fi

# If node is registered (if you have run this script before), then unregister it
if which hzn >/dev/null; then
    if [[ $(hzn node list 2>&1 | jq -r '.configstate.state' 2>&1) == 'configured' ]]; then
        hzn unregister -f
    fi
fi

# Get the other files we need from our git repo
deviceBinaryDir='sdo_device_binaries_1.7_linux_x64'
if [[ ! -d $deviceBinaryDir ]]; then
    deviceBinaryTar="$deviceBinaryDir.tar.gz"
    deviceBinaryUrl="https://github.com/open-horizon/SDO-support/releases/download/sdo_device_binaries_1.7/$deviceBinaryTar"
    echo "Getting and unpacking $deviceBinaryDir ..."
    httpCode=$(curl -w "%{http_code}" --progress-bar -L -O $deviceBinaryUrl)
    chkHttp $? $httpCode "getting $deviceBinaryTar"
    tar -zxvf $deviceBinaryTar
fi

echo "Getting $sampleMfgRepo/sample-mfg/docker-compose.yml ..."
#set -x
httpCode=$(curl -w "%{http_code}" --progress-bar -L -O $sampleMfgRepo/sample-mfg/docker-compose.yml)
chkHttp $? $httpCode 'getting sample-mfg/docker-compose.yml'
# { set +x; } 2>/dev/null

# Copy the mfg private key to the place docker-compose looks for it (keys/sdo.p12), unless it is already there
if [[ $privateKeyFile != 'keys/sdo.p12' && $privateKeyFile != './keys/sdo.p12' ]]; then
    cp $privateKeyFile keys/sdo.p12
fi

# Start mfg services (originally done by SCT/startup-docker.sh)
echo "Pulling and tagging the SDO SCT services..."
docker pull openhorizon/manufacturer:$SDO_MFG_IMAGE_TAG
docker tag openhorizon/manufacturer:$SDO_MFG_IMAGE_TAG manufacturer:latest
docker pull openhorizon/sct_mariadb:$SDO_MFG_IMAGE_TAG
docker tag openhorizon/sct_mariadb:$SDO_MFG_IMAGE_TAG sct_mariadb:latest

echo "starting the SDO SCT services (will take about 75 seconds)..."
# need to explicitly set the project name, because it was built with that project name (see Makefile)
docker-compose --project-name SCT up -d --no-build
chk $? 'starting SDO SCT services'

# sdo_sdk_binaries_linux_x64/SupplyChainTools/docker_manufacturer/mt_config.sql puts http://sdo-sbx.trustedservices.intel.com:80 in the mt_server_settings table
# as the RV URL. Update that to the value the user wants to use.
echo "Updating the RV hostname in the mt_server_settings table..."
docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo -e "update mt_server_settings set rendezvous_info = '$rvUrl' where id = 1"
chk $? 'updating RV hostname in mt_server_settings'

# To enable re-running this script w/o shutting down the docker containers, we have to delete the voucher row from rt_ownership_voucher because it has a
# foreign key to the 1 row in the rt_customer_public_key, which we will be replacing in the next step.
echo "Removing all rows from the rt_ownership_voucher table to enable redo..."
docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo -e "delete from rt_ownership_voucher"
chk $? 'deleting rows from rt_ownership_voucher'

# Add the customer/owner public key to the mariadb
echo "Adding owner public key $ownerPubKeyFile to the SCT services..."
docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo -e "call rt_add_customer_public_key('all','$(cat $ownerPubKeyFile)')"
chk $? 'adding owner public key to SDO SCT services'
# it can be listed with: docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo -e "select customer_descriptor from rt_customer_public_key"
# all of the tables can be listed with: docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo -e "show tables"

# Device initialization (and create the ownership voucher)
echo "Running device initialization..."
if [[ $useNativeClient == 'true' ]]; then
    echo "Using native client"
    ensureWeAreRoot
    cd $deviceBinaryDir/SDOClientIntel/hostapp_linux
    dalp='../sdo_7.dalp'   # or try ../sdo_8.dalp
    miFlag='-mi bp-sdo-intel-nuc'
    #miFlag="-mi <generate-uuid>"
    ./sdo_di –df $dalp –su 127.0.0.1 -sp 8039 $miFlag
    chk $? 'running native DI'
    cd ../../..
else
    echo "Using java client"
    cd $deviceBinaryDir/demo/device
    # comment out this property to put the device in DI mode
    sed -i -e 's/^com.intel.sdo.device.credentials=/#com.intel.sdo.device.credentials=/' application.properties
    chk $? 'modifying device application.properties for DI'
    # this property is already set how we want it: com.intel.sdo.di.uri=http://localhost:8039

    # this creates an ownership voucher and puts it in the mariadb rt_ownership_voucher table
    ./device
    chk $? 'running java DI'
    cd creds/saved
    deviceOcFile=$(ls -t *.oc | head -1)   # get the most recently created credentials
    cd ../..
    deviceOcFileUuid=${deviceOcFile%.oc}
    echo "Device UUID: $deviceOcFileUuid"
    cd ../../..
fi

# At this point, the mariadb has content in these tables:
#   mt_server_settings: 1 row with RV URL
#   rt_customer_public_key: 1 row with all forms of customer/owner public key concatenated
#   rt_ownership_voucher: 1 row with ownership voucher
#   mt_device_state: 1 row of device info

# Extend the voucher to the owner and save it in the current dir (orginally done by SCT/sct-docker.sh)
echo "Extending the voucher to the owner..."
devSerialNum=$(docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo --skip-column-names -s -e "select device_serial_no from rt_ownership_voucher where customer_public_key_id is NULL")
chk $? 'querying device_serial_no'
devSerialNum=${devSerialNum:0:$((${#devSerialNum}-1))}   # the last char seems to be a carriage return control char, so strip it
numSerialNums=$(echo -n "$devSerialNum" | grep -c '^')   # this counts the number of lines
if [[ $numSerialNums -ne 1 ]]; then
    echo "Error: found $numSerialNums device serial numbers in the SCT DB, instead of 1"
    exit 4
fi
# devSerialNum is different from the UUID

# this is what extends the voucher to the owner, because the db already has the owner public key
docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo -e "call rt_assign_device_to_customer('$devSerialNum','all')"
chk $? 'assign voucher to owner'
printf "Device serial and owner in the DB: "
docker exec -t mariadb mysql -u$dbUser -p$dbPw -D intel_sdo --skip-column-names -s -e "select rt_ownership_voucher.device_serial_no, rt_customer_public_key.customer_descriptor from rt_ownership_voucher inner join rt_customer_public_key on rt_customer_public_key.customer_public_key_id=rt_ownership_voucher.customer_public_key_id"

# get the voucher from the db
if [[ -f voucher.json ]]; then
    mkdir -p saved
    mv voucher.json saved
fi
httpCode=$(curl -sS -w "%{http_code}" -X GET -o voucher.json http://localhost:8039/api/v1/vouchers/$devSerialNum)
chk $? 'getting voucher from SCT DB'
if [[ $httpCode -ne 200 ]]; then
    echo "Error: HTTP code $httpCode when trying to get the voucher from the SCT service"
    exit 5
elif [[ ! -f voucher.json ]]; then
    echo "Error: file voucher.json not created"
    exit 5
fi

# Verify that the device UUID in the voucher is the same as what we found above
voucherDevUuid=$(parseVoucher voucher.json)
if [[ -n "$deviceOcFileUuid" && "$deviceOcFileUuid" != "$voucherDevUuid" ]]; then
    echo "Error: the device uuid in creds/saved ($deviceOcFileUuid) does not equal the device uuid in the voucher ($voucherDevUuid)"
    exit 4
fi

# Note: originally to-docker.sh would at this point put the voucher in the ocs db, but our hzn-voucher-import does that later

if [[ $useNativeClient == 'false' ]]; then
    # Switch the device into owner mode
    cd $deviceBinaryDir/demo/device
    echo "Switching the device into owner mode with credential file $deviceOcFile ..."
    mv creds/saved/$deviceOcFile creds
    chk $? 'moving device .oc file'
    sed -i -e "s|^#*com.intel.sdo.device.credentials=.*$|com.intel.sdo.device.credentials=creds/$deviceOcFile|" application.properties
    chk $? 'switching device to owner mode'
    cd ../../..
fi

# Shutdown mfg services
if [[ "$SDO_SAMPLE_MFG_KEEP_SVCS" == '1' || "$SDO_SAMPLE_MFG_KEEP_SVCS" == 'true' ]]; then
    echo "Leaving SCT services running, because SDO_SAMPLE_MFG_KEEP_SVCS=$SDO_SAMPLE_MFG_KEEP_SVCS"
else
    echo "Shutting down SDO SCT services..."
    docker-compose --project-name SCT down
    chk $? 'shutting down SDO SCT services'
fi

echo '-------------------------------------------------'
echo "Device UUID: $voucherDevUuid"
echo '-------------------------------------------------'

echo "The extended ownership voucher is in file: voucher.json"
echo "Device manufacturing initialization complete."
