# Sample SDO Manufacturer Scripts and Docker Images

These sample scripts and docker images enable you to develop/test/demo the SDO owner services by initializing VMs to simulate an SDO device and creating ownership vouchers.

## Build the Sample SDO Manufacturer Docker Images

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

## Use the Sample SDO Manufacturer Services Initialize a Device and Extend the Voucher

This simulates the process of a manufacturer initializing a device with SDO and credentials, creating an ownership voucher and extending it to the owner. Do these things on the device to be initialized:

```bash
apt install openjdk-11-jre-headless docker docker-compose
mkdir -p $HOME/sdo/keys
# get sdo private key from Services/SCT/keys/sdo.p12 and put it in above dir
cd $HOME/sdo
curl -sS --progress-bar -o simulate-mfg.sh $SDO_SAMPLE_MFG_REPO/sample-mfg/simulate-mfg.sh
./simulate-mfg.sh keys/sdo.p12
```
