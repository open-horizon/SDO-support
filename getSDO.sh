#!/bin/bash
SCRIPT_LOCATION=$(dirname "$0")

echo "This script only needs to be run by developers when needing to move up to a new version of SDO."
echo "Retrieving Intel SDO Release 1.10.0 dependencies..."
mkdir ${SCRIPT_LOCATION}/sdo && cd ${SCRIPT_LOCATION}/sdo
echo "Getting iot-platform-sdk"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.0/iot-platform-sdk-v1.10.0.tar.gz
tar -zxf iot-platform-sdk-v1.10.0.tar.gz
echo "Getting Protocol Reference Implementation"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.0/pri-v1.10.0.tar.gz
tar -zxf pri-v1.10.0.tar.gz
echo "Getting NOTICES"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.0/NOTICES-v1.10.0.tar.gz
tar -zxf NOTICES-v1.10.0.tar.gz
echo "Getting Rendezvous Service demo"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.0/rendezvous-service-v1.10.0.tar.gz
tar -zxf rendezvous-service-v1.10.0.tar.gz
echo "Getting Supply Chain Tools demo"
curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.0/supply-chain-tools-v1.10.0.tar.gz
tar -zxf supply-chain-tools-v1.10.0.tar.gz
cd ${SCRIPT_LOCATION}
echo "Complete."