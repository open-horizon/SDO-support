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
${0##*/} <priv-key-file> <customer-pub-key-file>

Environment Variables that must be set:
  SDO_RV_DEV_IP (will no longer be required when using the real RV service)
EndOfMessage
    exit $exitCode
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage 0
elif [[ -z "$2" ]]; then
    usage 1
fi
: ${SDO_RV_DEV_IP:?}

privateKeyFile="$1"   # not yet sure what this is
customerPubKeyFile="$2"
rvIp="$SDO_RV_DEV_IP"   #todo: the mfg won't have to specify this when using the real/intel RV

# Only echo this if VERBOSE is 1 or true
verbose() {
    if [[ "$VERBOSE" == "1" || "$VERBOSE" == "true" ]]; then
        echo $*
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
if grep RVSDO /etc/hosts; then
    # In case we are using a different RV IP than before
    [ $(uname) == "Darwin" ] || sudo sed -i -e "s/^.\+ RVSDO.*$/$rvIp RVSDO/" /etc/hosts
else
    sudo sh -c "echo \"$rvIp RVSDO\" >> /etc/hosts"
fi
checkexitcode $? 'adding RVSDO to /etc/hosts'

# Start mfg services (this and next step were done in SCT/startup-docker.sh)
echo "Starting the SDO SCT services..."
docker pull openhorizon/manufacturer:latest
docker tag openhorizon/manufacturer:latest manufacturer:latest
docker pull openhorizon/sct_mariadb:latest
docker tag openhorizon/sct_mariadb:latest sct_mariadb:latest
#docker tag openhorizon/sct_mariadb:latest mariadb:latest
#docker pull mariadb:bionic
# need to explicitly set the project name, because it was built under Services/SCT which by default sets the project name to SCT
docker-compose --project-name SCT up -d --no-build
exit

# Add the customer public key to the mariadb
docker exec -t mariadb mysql -usdo_admin -psdo -h localhost -e "use intel_sdo; call rt_add_customer_public_key('all','-----BEGIN PUBLIC KEY-----
MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE4RFfGVQdojLIODXnUT6NqB6KpmmPV2Rl
aVWXzdDef83f/JT+/XLPcpAZVoS++pwZpDoCkRU+E2FqKFdKDDD4g7obfqWd87z1
EtjdVaI1qiagqaSlkul2oQPBAujpIaHZ
-----END PUBLIC KEY-----
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtE58Wx9S4BWTNdrTmj3+
kJXNKuOAk3sgQwvF0Y8uXo3/ECeS/hj5SDmxG5fSnBlmGVKJwGV1bTVERDZ4uh4a
W1fWMmoUd4xcxun4N4B9+WDSQlX/+Rd3wBLEkKQfNr7lU9ZitfaGkBKxs23Y0GCY
Hfwh91TjXzNtGzAzv4F/SqQ45KrSafQIIEj72yuadBrQuN+XHkagpJwFtLYr0rbt
RZfSLcSvoGZtpwW9JfIDntC+eqoqcwOrMRWZAnyAY52GFZqK9+cjJlXuoAS4uH+q
6KHgLC5u0rcpLiDYJgiv56s4pwd4ILSuRGSohCYsIIIk9rD+tVWqFsGZGDcZXU0z
CQIDAQAB
-----END PUBLIC KEY-----
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEWVUE2G0GLy8scmAOyQyhcBiF/fSU
d3i/Og7XDShiJb2IsbCZSRqt1ek15IbeCI5z7BHea2GZGgaK63cyD15gNA==
-----END PUBLIC KEY-----')"
# it can be listed with: docker exec -t mariadb mysql -usdo_admin -psdo -h localhost -e "use intel_sdo; select customer_descriptor from rt_customer_public_key"

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

