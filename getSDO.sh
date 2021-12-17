#!/bin/bash

# This script only needs to be run by developers of this project when needing to move up to a new version of SDO.
# Before running, update the versions of the tar files as necessary.

SCRIPT_LOCATION=$(dirname "$0")

# Check the exit code passed in and exit if non-zero
chk() {
    local exitCode=$1
    local task=$2
    if [[ $exitCode == 0 ]]; then return; fi
    echo "Error: exit code $exitCode from: $task"
    exit $exitCode
}

echo "Retrieving Intel SDO Release 1.10.4 dependencies..."
mkdir -p ${SCRIPT_LOCATION}/sdo && cd ${SCRIPT_LOCATION}/sdo
chk $? 'making sdo dir'

echo "Getting iot-platform-sdk"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.4/iot-platform-sdk-v1.10.4.tar.gz
chk $? 'downloading iot-platform-sdk'
tar -zxf iot-platform-sdk-v1.10.4.tar.gz
chk $? 'unpacking iot-platform-sdk'

echo "Getting Protocol Reference Implementation"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.4/pri-v1.10.4.tar.gz
chk $? 'downloading pri'
tar -zxf pri-v1.10.4.tar.gz
chk $? 'unpacking pri'

echo "Getting NOTICES"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.4/NOTICES-v1.10.4.tar.gz
chk $? 'downloading NOTICES'
tar -zxf NOTICES-v1.10.4.tar.gz
chk $? 'unpacking NOTICES'

echo "Getting Rendezvous Service"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.4/rendezvous-service-v1.10.4.tar.gz
chk $? 'downloading RV'
tar -zxf rendezvous-service-v1.10.4.tar.gz
chk $? 'unpacking RV'

echo "Getting Supply Chain Tools"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.4/supply-chain-tools-v1.10.4.tar.gz
chk $? 'downloading SCT'
tar -zxf supply-chain-tools-v1.10.4.tar.gz
chk $? 'unpacking SCT'

cd ${SCRIPT_LOCATION}
echo "Complete."