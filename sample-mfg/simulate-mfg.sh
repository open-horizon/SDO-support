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
${0##*/} <priv-key-file> [<customer-pub-key-file>]

Arguments:
  <priv-key-file>  Device manufacturer private key?
  <owner-pub-key-file>  Device customer/owner public key. If not specified, it will use a sample public key.

Environment Variables that must be set:
  SDO_RV_DEV_IP (will no longer be required when using the real RV service)

${0##*/} must be run in a directory where it has access to create a few files and directories.
EndOfMessage
    exit $exitCode
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage 0
elif [[ -z "$1" ]]; then
    usage 1
fi
: ${SDO_RV_DEV_IP:?}

privateKeyFile="$1"   # not yet sure what this is
rvIp="$SDO_RV_DEV_IP"   #todo: the mfg won't have to specify this when using the real/intel RV
sampleMfgRepo=${SDO_SAMPLE_MFG_REPO:-https://raw.githubusercontent.com/open-horizon/SDO-support/master}
ownerPubKeyFile=${2:-$sampleMfgRepo/sample-mfg/owner-key.pub}

if [[ ! -f $privateKeyFile ]]; then
    echo "Error: $privateKeyFile does not exist"
    exit 1
fi

if [[ ${ownerPubKeyFile:0:4} != 'http' && ! -f $ownerPubKeyFile ]]; then
    echo "Error: $ownerPubKeyFile does not exist"
    exit 1
fi

# Only echo this if VERBOSE is 1 or true
verbose() {
    if [[ "$VERBOSE" == "1" || "$VERBOSE" == "true" ]]; then
        echo 'verbose:' $*
    fi
}

# Check the exit code passed in and exit if non-zero
checkexitcode() {
    local exitCode=$1
    local task=$2
    local dontExit=$3   # set to 'continue' to not exit for this error
    if [[ $1 == 0 ]]; then return; fi
    echo "Error: exit code $exitCode from: $task"
    if [[ $dontExit != 'continue' ]]; then
        exit $exitCode
    fi
}

# Verify that the prereq commands we need are installed
function confirmcmds {
    for c in $*; do
        #echo "checking $c..."
        if ! which $c >/dev/null; then
            echo "Error: $c is not installed but required, exiting"
            exit 2
        fi
    done
}

# Define the hostname used to find the SCT services (only if its not already set)
echo "Adding SCT to /etc/hosts, if not there ..."
grep -qxF '127.0.0.1 SCT' /etc/hosts || sudo sh -c "echo '127.0.0.1 SCT' >> /etc/hosts"
checkexitcode $? 'adding SCT to /etc/hosts'

#todo: remove this when it is time to use the real RV
echo "Adding '$rvIp RVSDO' to /etc/hosts, if not there ..."
if grep -q RVSDO /etc/hosts; then
    # In case we are using a different RV IP than before
    [ $(uname) == "Darwin" ] || sudo sed -i -e "s/^.\+ RVSDO.*$/$rvIp RVSDO/" /etc/hosts
else
    sudo sh -c "echo \"$rvIp RVSDO\" >> /etc/hosts"
fi
checkexitcode $? 'adding RVSDO to /etc/hosts'

# Get the other files we need from our git repo
echo "Getting docker files from $sampleMfgRepo ..."
#set -x
curl --progress-bar -o Dockerfile-mariadb $sampleMfgRepo/sample-mfg/Dockerfile-mariadb
checkexitcode $? 'getting sample-mfg/Dockerfile-mariadb'
curl --progress-bar -o Dockerfile-manufacturer $sampleMfgRepo/sample-mfg/Dockerfile-manufacturer
checkexitcode $? 'getting sample-mfg/Dockerfile-manufacturer'
curl --progress-bar -o docker-compose.yml $sampleMfgRepo/sample-mfg/docker-compose.yml
checkexitcode $? 'getting sample-mfg/docker-compose.yml'
# { set +x; } 2>/dev/null

# The owner public key is either a URL we retrieve, or a file we use as-is
mkdir -p keys
if [[ ${ownerPubKeyFile:0:4} == 'http' ]]; then
    echo "Getting $ownerPubKeyFile ..."
    curl --progress-bar -o keys/owner-key.pub $ownerPubKeyFile
    checkexitcode $? 'getting owner public key'
    ownerPubKeyFile='keys/owner-key.pub'
fi

# Copy the mfg private key to keys/sdo.p12, unless it is already there
if [[ $privateKeyFile != 'keys/sdo.p12' || $privateKeyFile != './keys/sdo.p12' ]]; then
    cp $privateKeyFile keys/sdo.p12
fi

# Start mfg services (this and next step were done in SCT/startup-docker.sh)
echo "Pulling and starting the SDO SCT services..."
docker pull openhorizon/manufacturer:latest
docker tag openhorizon/manufacturer:latest manufacturer:latest
docker pull openhorizon/sct_mariadb:latest
docker tag openhorizon/sct_mariadb:latest sct_mariadb:latest
# need to explicitly set the project name, because it was built under Services/SCT which by default sets the project name to SCT
docker-compose --project-name SCT up -d --no-build
checkexitcode $? 'starting SDO SCT services'

# Add the customer public key to the mariadb
verbose "adding $ownerPubKeyFile to the SCT services..."
docker exec -t mariadb mysql -usdo_admin -psdo -h localhost -e "use intel_sdo; call rt_add_customer_public_key('all','$(cat $ownerPubKeyFile)')"
checkexitcode $? 'adding owner public key to SDO SCT services'
# it can be listed with: docker exec -t mariadb mysql -usdo_admin -psdo -h localhost -e "use intel_sdo; select customer_descriptor from rt_customer_public_key"
exit

# Device initialization
cd ../sdo_sdk_binaries_1.7.0.89_linux_x64/demo/device
vi application.properties
  #com.intel.sdo.device.credentials=creds/6584d23f-2e8d-4129-84c2-bd94fa803651.oc  # comment this out to initiate DI
  com.intel.sdo.di.uri=http://SCT:8039
./device   # gives manufacturer container info for ownership voucher
#cd ../../../Services

# Extend the voucher to the owner
cd SCT && ./sct-docker.sh && cd ..  #  get vouchers from mariadb and runs to-docker.sh (which copies the voucher files into ocs's file db)

# Switch the device into owner mode
cd $HOME/sdo/sdo_sdk_binaries_1.7.0.89_linux_x64/demo/device
cp creds/saved/${SDO_DEVICE_UUID}.oc creds
vi application.properties   # switch device into mode of booting at customer site
  com.intel.sdo.device.credentials=creds/${SDO_DEVICE_UUID}.oc

# Shutdown mfg services

