# Sample SDO Manufacturer Scripts and Docker Images

These sample scripts and docker images enable you to develop/test/demo the SDO owner services by initializing a VM to simulate an SDO device and creating an ownership voucher.

## Build the Sample SDO Manufacturer Docker Images

1. Build a tar file of the SDO files needed on the device:

  ```bash
  cd ..
  tar -zcvf sample-mfg/sdo_device_binaries_linux_x64.tar.gz sdo_sdk_binaries_linux_x64/cri/device-*.jar sdo_sdk_binaries_linux_x64/demo/device
  cd -
  ```

1. Build the SDO manufacturer services:

  ```bash
  make sdo-mfg-services
  ```

1. After testing the service, push it to docker hub:

  ```bash
  make publish-sdo-mfg-services
  ```

## Use the Sample SDO Manufacturer Services to Initialize a Device and Extend the Voucher

This simulates the process of a manufacturer initializing a device with SDO and credentials, creating an ownership voucher, and extending it to the owner. Do these things on the VM device to be initialized:

```bash
apt update && apt install -y openjdk-11-jre-headless docker docker-compose
mkdir -p $HOME/sdo && cd $HOME/sdo
scp $SDO_BUILD_USER_AND_HOST:src/github.com/open-horizon/SDO-support/sample-mfg/sdo_device_binaries_linux_x64.tar.gz .
tar -zxvf sdo_device_binaries_linux_x64.tar.gz
curl --progress-bar -o simulate-mfg.sh https://raw.githubusercontent.com/open-horizon/SDO-support/sample-mfg/simulate-mfg.sh
chmod +x simulate-mfg.sh
export SDO_RV_URL=http://<hzn-sdo-owner-svcs-host>:8040   # if using that
export VERBOSE=true   # if you want
# Note: if you don't specify a mfg private key as the 1st arg, it will use a sample manufacturer key. For device owners and IoT platform vendors it is ok to use this for dev/test/demo.
./simulate-mfg.sh    # can specify args: <mfg-priv-key-file> <owner-pub-key-file>
```
