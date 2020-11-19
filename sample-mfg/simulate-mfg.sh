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
Usage: ${0##*/} [<owner-pub-key-file>]

Arguments:
  <owner-pub-key-file>  Device customer/owner public key. This is needed to extend the voucher to the owner. If not specified, it will use SDO-support/keys/sample-owner-key.pub (only valid for dev/test/demo)

Required Environment Variables:
  SDO_RV_URL: usually the dev RV running in the sdo-owner-services. To use the real Intel RV service, set to http://sdo-sbx.trustedservices.intel.com or http://sdo.trustedservices.intel.com and register your public key with Intel.

Optional Environment Variables:
  SDO_MFG_IMAGE_TAG - version of the manufacturer and manufacturer-mariadb docker images that should be used. Defaults to '1.9'.
  HZN_MGMT_HUB_CERT - the base64 encoded content of the SDO owner services self-signed certificate (if it requires that). This is normally not necessary on the device, because the SDO protocols are secure over HTTP.
  SDO_SAMPLE_MFG_KEEP_SVCS - set to 'true' to skip shutting down the mfg docker containers at the end of this script. This is faster if running this script repeatedly during dev/test.
  SDO_SUPPORT_REPO - if you need to use a more recent version of SDO files from the repo than the 1.9 released files. This takes precedence over SDO_SUPPORT_RELEASE.
  SDO_SUPPORT_RELEASE - if you need to use a specific set of released files.
  SDO_DEVICE_USE_NATIVE_CLIENT - normally detected automatically, but can be overridden explicitly: set to 'true' to use the native SDO device client. (To use this, you need to have the 'sdo' native docker image already loaded on this host.) Set to 'false' to use the reference implementation java device client. 

${0##*/} must be run in a directory where it has access to create a few files and directories.
EndOfMessage
    exit $exitCode
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage 0
fi
: ${SDO_RV_URL:?}

deviceBinaryDir='sdo_device_binaries_1.9_linux_x64'   # the place we will unpack sdo_device_binaries_1.9_linux_x64.tar.gz to
ownerPubKeyFile=${1:-$deviceBinaryDir/keys/sample-owner-key.pub}
rvUrl="$SDO_RV_URL"   # the external rv url that the device should reach it at

#If the passed argument is a file, save the file directory path
if [[ -f "$ownerPubKeyFile" ]]; then
  origDir="$PWD"
  #if you passed an owner public key, it will be retrieved from the original directory
  if [[ -f $origDir/$ownerPubKeyFile ]]; then
    ownerPubKeyFile="$origDir/$ownerPubKeyFile"
  fi
fi

# These environment variables can be overridden
SDO_MFG_IMAGE_TAG=${SDO_MFG_IMAGE_TAG:-1.9}
# default SDO_SUPPORT_REPO to blank, so SDO_SUPPORT_RELEASE will be used
#SDO_SUPPORT_REPO=${SDO_SUPPORT_REPO:-https://raw.githubusercontent.com/open-horizon/SDO-support/master}
SDO_SUPPORT_RELEASE=${SDO_SUPPORT_RELEASE:-https://github.com/open-horizon/SDO-support/releases/download/v1.9}
useNativeClient=$SDO_DEVICE_USE_NATIVE_CLIENT   # if empty (recommended) this script will detect automatically which sdo client to use

workingDir=/var/sdo
privateKeyFile=$deviceBinaryDir/keys/manufacturer-keystore.p12
sdoMfgDockerName='manufacturer'   # both docker image and container
sdoMariaDbDockerName='manufacturer-mariadb'   # both docker image and container
dbUser='sdo'
dbPw='sdo'
sdoNativeDockerImage='sdo:1.9'
IP_REGEX='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'

#====================== Functions ======================

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

runCmdQuietly() {
    # all of the args to this function are the cmd and its args
    if [[  "$VERBOSE" == '1' || "$VERBOSE" == 'true' ]]; then
        $*
        chk $? "running: $*"
    else
        output=$($* 2>&1)
        if [[ $? -ne 0 ]]; then
            echo "Error running $*: $output"
            exit 2
        fi
    fi
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

# Is this deb pkg installed
isDebPkgInstalled() {
    local pkgName="$1"
    dpkg-query -s $pkgName 2>&1 | grep -q -E '^Status: .* installed$'
}

# Checks if docker-compose is installed, and if so, if it is at least this minimum version
isDockerComposeAtLeast() {
    : ${1:?}
    local minVersion=$1
    if ! command -v docker-compose >/dev/null 2>&1; then
        return 1   # it is not even installed
    fi
    # docker-compose is installed, check its version
    lowerVersion=$(echo -e "$(docker-compose version --short)\n$minVersion" | sort -V | head -n1)
    if [[ $lowerVersion == $minVersion ]]; then
        return 0   # the installed version was >= minVersion
    else
        return 1
    fi
}

# Find 1 of the private IPs of the host
getPrivateIp() {
    if isMacOS; then ipCmd=ifconfig
    else ipCmd='ip address'; fi
    $ipCmd | grep -m 1 -o -E "\sinet (172|10|192.168)[^/\s]*" | awk '{ print $2 }'
}

#====================== Main Code ======================

# Our working directory is /var/sdo
ensureWeAreRoot
mkdir -p $workingDir && cd $workingDir
chk $? "creating and switching to $workingDir"

# Determine whether to use native sdo client, or java client
if [[ -z "$useNativeClient" ]]; then
    if [[ "$(systemd-detect-virt 2>/dev/null)" == 'none' ]]; then
        useNativeClient='true'   # A physical server
    else
        useNativeClient='false'   # A VM
    fi
    # Also could use these cmds to determine, but there are more acceptable values to check for
    # lscpu | grep 'Hypervisor vendor:' == non-blank or blank
    # dmidecode -s system-manufacturer | awk '{print $1}' == Intel(R), IBM. QEMU, innotek (virtual box), VMware
fi
# else they explicitly set it

# Make sure the host has the necessary software: java 11, docker-ce, docker-compose >= 1.21.0
confirmcmds grep curl ping   # these should be in the minimal ubuntu

if [[ $useNativeClient == 'true' ]]; then
    if [[ -z $(docker images -q $sdoNativeDockerImage) ]]; then
        echo "Error: docker image $sdoNativeDockerImage does not exist on this host."
        exit 2
    fi
else
    # If java 11 isn't installed, do that
    if java -version 2>&1 | grep version | grep -q 11.; then
        echo "Found java 11"
    else
        echo "Java 11 not found, installing it..."
        apt-get update && apt-get install -y openjdk-11-jre-headless
        chk $? 'installing java 11'
    fi
    # if jq isn't installed, do that
    if command -v jq >/dev/null 2>&1; then
        echo "Found jq"
    else
        echo "Jq not found, installing it..."
        runCmdQuietly apt-get install -y jq
    fi
fi

# If docker isn't installed, do that
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required, installing it..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    chk $? 'adding docker repository key'
    add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    chk $? 'adding docker repository'
    apt-get install -y docker-ce docker-ce-cli containerd.io
    chk $? 'installing docker'
fi

# If docker-compose isn't installed, or isn't at least 1.21.0 (when docker-compose.yml version 2.4 was introduced), then install/upgrade it
# For the dependency on 1.21.0 or greater, see: https://docs.docker.com/compose/release-notes/
minVersion=1.21.0
if ! isDockerComposeAtLeast $minVersion; then
    if [[ -f '/usr/bin/docker-compose' ]]; then
        echo "Error: Need at least docker-compose $minVersion. A down-level version is currently installed, preventing us from installing the latest version. Uninstall docker-compose and rerun this script."
        exit 2
    fi
    echo "docker-compose is not installed or not at least version $minVersion, installing/upgrading it..."
    # Install docker-compose from its github repo, because that is the only way to get a recent enough version
    curl --progress-bar -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chk $? 'downloading docker-compose'
    chmod +x /usr/local/bin/docker-compose
    chk $? 'making docker-compose executable'
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    chk $? 'linking docker-compose to /usr/bin'
fi

# Get the other files we need from our git repo, by way of our device binaries tar file
if [[ ! -d $deviceBinaryDir ]]; then
    deviceBinaryTar="$deviceBinaryDir.tar.gz"
    deviceBinaryUrl="$SDO_SUPPORT_RELEASE/$deviceBinaryTar"
    echo "Getting and unpacking $deviceBinaryDir ..."
    httpCode=$(curl -w "%{http_code}" --progress-bar -L -O $deviceBinaryUrl)
    chkHttp $? $httpCode "getting $deviceBinaryTar"
    tar -zxf $deviceBinaryTar
fi

# The mfg private key is either a URL we retrieve, or a file we use as-is
mkdir -p keys
if [[ ${privateKeyFile:0:4} == 'http' ]]; then
    echo "Getting $privateKeyFile ..."
    httpCode=$(curl -w "%{http_code}" -sSL -o keys/manufacturer-keystore.p12 $privateKeyFile)
    chkHttp $? $httpCode 'getting mfg private key'
    privateKeyFile='keys/manufacturer-keystore.p12'
elif [[ $privateKeyFile == "$deviceBinaryDir/keys/manufacturer-keystore.p12" ]]; then
    :   # we will get if from $deviceBinaryDir later
elif [[ ! -f $privateKeyFile ]]; then
    echo "Error: $privateKeyFile does not exist"
    exit 1
fi

# The owner public key is either a URL we retrieve, or a file we use as-is
if [[ ${ownerPubKeyFile:0:4} == 'http' ]]; then
    echo "Getting $ownerPubKeyFile ..."
    httpCode=$(curl -w "%{http_code}" -sSL -o keys/owner-key.pub $ownerPubKeyFile)
    chkHttp $? $httpCode 'getting owner public key'
    ownerPubKeyFile='keys/owner-key.pub'
elif [[ $ownerPubKeyFile == "$deviceBinaryDir/keys/sample-owner-key.pub" ]]; then
    :   # we will get if from $deviceBinaryDir later
elif [[ ! -f $ownerPubKeyFile ]]; then
    echo "Error: $ownerPubKeyFile does not exist"
    exit 1
fi

# Get the owner-boot-device script and sdo_to.service and leave it here for use when the "customer" is booting the device
echo "Getting owner-boot-device script ..."
mkdir -p /usr/sdo/bin
if [[ -n $SDO_SUPPORT_REPO ]]; then
    httpCode=$(curl -w "%{http_code}" -sSL -o /usr/sdo/bin/owner-boot-device $SDO_SUPPORT_REPO/tools/owner-boot-device)
else
    httpCode=$(curl -w "%{http_code}" -sSL -o /usr/sdo/bin/owner-boot-device $SDO_SUPPORT_RELEASE/owner-boot-device)
fi
chkHttp $? $httpCode 'getting owner-boot-device'
chmod +x /usr/sdo/bin/owner-boot-device
chk $? 'making owner-boot-device executable'

echo "Getting sdo_to.service ..."
if [[ -n $SDO_SUPPORT_REPO ]]; then
    httpCode=$(curl -w "%{http_code}" -sSL -o /usr/sdo/sdo_to.service $SDO_SUPPORT_REPO/sample-mfg/sdo_to.service)
else
    httpCode=$(curl -w "%{http_code}" -sSL -o /usr/sdo/sdo_to.service $SDO_SUPPORT_RELEASE/sdo_to.service)
fi
chkHttp $? $httpCode 'getting sdo_to.service'
# we will install it as a systemd service later

# Ensure RV hostname is resolvable, if it is not an IP address
rvHost=${rvUrl#http*://}   # strip protocol
rvHost=${rvHost%:*}   # strip optional port
#if ! ping -c 1 -W 5 $rvHost > /dev/null 2>&1 ; then  # <- the intel RVs do not support ping
if [[ ! $rvHost =~ $IP_REGEX ]]; then
    echo "Verifying that rendezvous server $rvHost is resolvable..."
    if ! nslookup "$rvHost" > /dev/null 2>&1 ; then
        echo "Error: rendezvous server $rvHost is not resolvable. Booting SDO devices will not be able to reach it."
        exit 1
    fi
fi

# If they specified a self-signed cert, ensure we are root, then trust the cert.
# Note: this is a concession for some dev/test environments that may require it. Normally the device manufacturer won't initialize the device with a self-signed cert.
#       If the sdo owner service requires a self-signed cert for https, it should also listen on http, which is secure for the sdo protocol.
if [[ -n $HZN_MGMT_HUB_CERT ]]; then
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

# Prepare to have docker-compose start the SCT services
cp $deviceBinaryDir/{docker-compose.yml,*.env} .
chk $? 'copying docker-compose.yml and *.env in place'

# Copy the mfg private key and the owner public key to the places docker-compose looks for them (unless they are already there)
if [[ $privateKeyFile != 'keys/manufacturer-keystore.p12' && $privateKeyFile != './keys/manufacturer-keystore.p12' ]]; then
    cp $privateKeyFile keys/manufacturer-keystore.p12   # if they took the default, this is copying from $deviceBinaryDir/keys/manufacturer-keystore.p12
    chk $? 'copying mfg private key in place'
    privateKeyFile='keys/manufacturer-keystore.p12'
fi
if [[ $ownerPubKeyFile != 'keys/owner-key.pub' && $ownerPubKeyFile != './keys/owner-key.pub' ]]; then
    cp $ownerPubKeyFile keys/owner-key.pub   # if they took the default, this is copying from $deviceBinaryDir/keys/sample-owner-key.pub
    chk $? 'copying owner public key in place'
    ownerPubKeyFile='keys/owner-key.pub'
fi

# Start mfg services (originally done by SCT/startup-docker.sh)
echo "Pulling and tagging the SDO SCT services..."
docker pull openhorizon/$sdoMfgDockerName:$SDO_MFG_IMAGE_TAG
docker tag openhorizon/$sdoMfgDockerName:$SDO_MFG_IMAGE_TAG $sdoMfgDockerName:1.9   # this is what the SDO docker-compose.yml file knows it by
docker pull openhorizon/$sdoMariaDbDockerName:$SDO_MFG_IMAGE_TAG
docker tag openhorizon/$sdoMariaDbDockerName:$SDO_MFG_IMAGE_TAG $sdoMariaDbDockerName:1.9   # this is what the SDO docker-compose.yml file knows it by

echo "Starting the SDO SCT services (could take about 75 seconds)..."
# need to explicitly set the project name, because it was built with that project name (see Makefile)
#docker-compose --project-name SCT up -d --no-build
docker-compose up -d --no-build
chk $? 'starting SDO SCT services'

# sdo_sdk_binaries_linux_x64/SupplyChainTools/docker_manufacturer/mt_config.sql puts http://sdo-sbx.trustedservices.intel.com:80 in the mt_server_settings table
# as the RV URL. Update that to the value the user wants to use.
echo "Updating the RV hostname in the mt_server_settings table..."
docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo -e "update mt_server_settings set rendezvous_info = '$rvUrl' where id = 1"
chk $? 'updating RV hostname in mt_server_settings'

# To enable re-running this script w/o shutting down the docker containers, we have to delete the voucher row from rt_ownership_voucher because it has a
# foreign key to the 1 row in the rt_customer_public_key, which we will be replacing in the next step.
echo "Removing all rows from the rt_ownership_voucher table to enable redo..."
docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo -e "delete from rt_ownership_voucher"
chk $? 'deleting rows from rt_ownership_voucher'

# Add the customer/owner public key to the mariadb
echo "Adding owner public key $ownerPubKeyFile to the SCT services..."
docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo -e "call rt_add_customer_public_key('all','$(cat $ownerPubKeyFile)')"
chk $? 'adding owner public key to SDO SCT services'
# it can be listed with: docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo -e "select customer_descriptor from rt_customer_public_key"
# all of the tables can be listed with: docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo -e "show tables"

# Device initialization (and create the ownership voucher)
if [[ $useNativeClient == 'true' ]]; then
    echo "Running device initialization using native client..."
    savePwd="$PWD"
    BOOTFS="$workingDir/sdo-native"
    rm -rf $BOOTFS   # remove any leftovers from a previous native client mfg DI
    mkdir -p $BOOTFS && cd $BOOTFS
    chk $? "creating and cding into $BOOTFS"
    SCT_IP_ADDRESS='manufacturer'   # we are running the DI container on the manufacturer_network, so we can reach the manufactuer container via its internal connection info
    SCT_PORT=8080
    Serial_Number_String="$(dmidecode -t system 2>/dev/null | grep Serial | awk '{print $3}')"
    if [[ -z "$Serial_Number_String" || "$Serial_Number_String" == 'Not' ]]; then
        Serial_Number_String='1234567'
    fi
    docker run -i --rm --privileged --name sdo-di --network manufacturer_network -v /dev:/dev -v /sys/:/sys/ -v $BOOTFS:/target/boot $sdoNativeDockerImage run_dal_sdo.sh ${SCT_IP_ADDRESS} ${SCT_PORT} ${Serial_Number_String}
    chk $? 'running native DI'
    # one of these echoes would say failed, and the above cmd outputs the status anyway
    #echo "DAL_DI_Status=$(cat $BOOTFS/DAL_DI_STATUS)"
	#echo "CSDK_DI_STATUS=$(cat $BOOTFS/CSDK_DI_STATUS)"
    cd $savePwd
else
    echo "Running device initialization using java client..."
    cd $deviceBinaryDir/device
    # comment out this property to put the device in DI mode
    sed -i -e 's/^org.sdo.device.credentials=/#org.sdo.device.credentials=/' application.properties
    chk $? 'modifying device application.properties for DI'
    # this property is already set how we want it: org.sdo.di.uri=http://localhost:8039

    # this creates an ownership voucher and puts it in the mariadb rt_ownership_voucher table
    ./device
    chk $? 'running java DI'
    cd creds
    deviceOcFile=$(ls -t *.oc | head -1)   # get the most recently created credentials
    cd ..
    deviceOcFileUuid=${deviceOcFile%.oc}
    echo "Device UUID: $deviceOcFileUuid"
    cd ../..
    rm -rf $workingDir/sdo-native   # remove any leftovers from a previous native client mfg DI so owner-boot-device knows this was mfg with the java client
fi

# At this point, the mariadb has content in these tables:
#   mt_server_settings: 1 row with RV URL
#   rt_customer_public_key: 1 row with all forms of customer/owner public key concatenated
#   rt_ownership_voucher: 1 row with ownership voucher
#   mt_device_state: 1 row of device info

# Extend the voucher to the owner and save it in the current dir (orginally done by SCT/sct-docker.sh)
echo "Extending the voucher to the owner..."
devSerialNum=$(docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo --skip-column-names -s -e "select device_serial_no from rt_ownership_voucher where customer_public_key_id is NULL")
chk $? 'querying device_serial_no'
devSerialNum=${devSerialNum:0:$((${#devSerialNum}-1))}   # the last char seems to be a carriage return control char, so strip it
numSerialNums=$(echo -n "$devSerialNum" | grep -c '^')   # this counts the number of lines
if [[ $numSerialNums -ne 1 ]]; then
    echo "Error: found $numSerialNums device serial numbers in the SCT DB, instead of 1"
    exit 4
fi
# devSerialNum is different from the UUID

# this is what extends the voucher to the owner, because the db already has the owner public key
docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo -e "call rt_assign_device_to_customer('$devSerialNum','all')"
chk $? 'assign voucher to owner'
printf "Device serial and owner in the DB: "
docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo --skip-column-names -s -e "select rt_ownership_voucher.device_serial_no, rt_customer_public_key.customer_descriptor from rt_ownership_voucher inner join rt_customer_public_key on rt_customer_public_key.customer_public_key_id=rt_ownership_voucher.customer_public_key_id"

# get the voucher from the db
if [[ -f voucher.json ]]; then
    mkdir -p saved
    mv voucher.json saved
fi
#httpCode=$(curl -sS -w "%{http_code}" -X GET -o voucher.json http://localhost:8039/api/v1/vouchers/$devSerialNum)   # this no longer works
docker exec -t $sdoMariaDbDockerName mysql -u$dbUser -p$dbPw -D sdo --skip-column-names -s -e "select voucher from rt_ownership_voucher where device_serial_no = '$devSerialNum'" > voucher.json
chk $? 'getting voucher from SCT DB'
#if [[ $httpCode -ne 200 ]]; then
#    echo "Error: HTTP code $httpCode when trying to get the voucher from the SCT service"
#    exit 5
#elif [[ ! -f voucher.json ]]; then
if [[ ! -f voucher.json ]]; then
    echo "Error: file voucher.json not created"
    exit 5
fi

# Verify that the device UUID in the voucher is the same as what we found above
voucherDevUuid=$(parseVoucher voucher.json)
if [[ -n "$deviceOcFileUuid" && "$deviceOcFileUuid" != "$voucherDevUuid" ]]; then
    echo "Error: the device uuid in creds ($deviceOcFileUuid) does not equal the device uuid in the voucher ($voucherDevUuid)"
    exit 4
fi

# Note: originally to-docker.sh would at this point put the voucher in the ocs db, but our 'hzn voucher import' does that later

if [[ $useNativeClient == 'true' ]]; then
    # Install systemd service that will run at boot time to complete the SDO process
    #Future: consider supporting sdo_to.service for the java client/VM case
    cp /usr/sdo/sdo_to.service /lib/systemd/system
    chk $? 'copying sdo_to.service to systemd'
    systemctl enable sdo_to.service
    chk $? 'enabling sdo_to.service'
    echo "Systemd service sdo_to.service has been enabled"
    # After importing the voucher to sdo-owner-services, if you want to you can initiate the sdo boot process by running: systemctl start sdo_to.service
    # And you can view the output with: journalctl -f --no-tail -u sdo_to.service
else
    # Java client. Switch the device into owner mode
    cd $deviceBinaryDir/device
    echo "Switching the device into owner mode with credential file $deviceOcFile ..."
    #mv creds/saved/$deviceOcFile creds   # no longer need
    #chk $? 'moving device .oc file'
    sed -i -e "s|^#*org.sdo.device.credentials=.*$|org.sdo.device.credentials=creds/$deviceOcFile|" application.properties
    chk $? 'switching device to owner mode'
    cd ../..
fi

# Shutdown mfg services
if [[ "$SDO_SAMPLE_MFG_KEEP_SVCS" == '1' || "$SDO_SAMPLE_MFG_KEEP_SVCS" == 'true' ]]; then
    echo "Leaving SCT services running, because SDO_SAMPLE_MFG_KEEP_SVCS=$SDO_SAMPLE_MFG_KEEP_SVCS"
else
    echo "Shutting down SDO SCT services..."
    #docker-compose --project-name SCT down
    docker-compose down
    chk $? 'shutting down SDO SCT services'
fi

echo '-------------------------------------------------'
echo "Device UUID: $voucherDevUuid"
echo '-------------------------------------------------'

echo "The extended ownership voucher is in file: ${workingDir}/voucher.json"
echo "Device manufacturing initialization complete."