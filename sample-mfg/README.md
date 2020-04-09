# Sample SDO Manufacturer Scripts and Docker Images

These sample scripts and docker images enable you to develop/test/demo the SDO owner services by initializing VMs to simulate an SDO device and creating ownership vouchers.

## Build the Sample SDO Manufacturer Docker Images

Build a tar file of the SDO files needed on the device:

```bash
cd ..
tar -zcvf sample-mfg/sdo_device_binaries_linux_x64.tar.gz sdo_sdk_binaries_linux_x64/cri/device-*.jar sdo_sdk_binaries_linux_x64/demo/device
cd -
```

Get the SDO Services.tar file from Intel and unpack it here:

```bash
tar -zxvf ~/Downloads/SDO/FromNima/Services.tar
```

Build the SDO manufacturer services:

```bash
make sdo-mfg-services
```

After testing the service, push it to docker hub:

```bash
make publish-sdo-mfg-services
```

## Use the Sample SDO Manufacturer Services to Initialize a Device and Extend the Voucher

This simulates the process of a manufacturer initializing a device with SDO and credentials, creating an ownership voucher and extending it to the owner. Do these things on the device to be initialized:

```bash
apt update && apt install -y openjdk-11-jre-headless docker docker-compose
mkdir -p $HOME/sdo/keys
cd $HOME/sdo
scp $SDO_BUILD_USER_AND_HOST:src/github.com/open-horizon/SDO-support/sample-mfg/Services/SCT/keys/sdo.p12 keys
scp $SDO_BUILD_USER_AND_HOST:src/github.com/open-horizon/SDO-support/sample-mfg/sdo_device_binaries_linux_x64.tar.gz .
tar -zxvf sdo_device_binaries_linux_x64.tar.gz
curl -sS --progress-bar -o simulate-mfg.sh $SDO_SAMPLE_MFG_REPO/sample-mfg/simulate-mfg.sh
chmod +x simulate-mfg.sh
export SDO_RV_DEV_IP=<local-dev-rv>   # if using that
export VERBOSE=true   # if you want
./simulate-mfg.sh keys/sdo.p12
```
