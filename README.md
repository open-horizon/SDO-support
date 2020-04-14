# SDO-support

Edge devices built with [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) (Secure Device Onboard) can be easily added to an open-horizon instance with true single-touch (plug the device in and power on).

The software in this git repository makes it easy to use SDO edge devices with open-horizon. The horizon SDO support consists of 3 main components:

1. A consolidated docker image of all of the SDO "owner" services (those that run in the horizon management hub). It also includes a small REST API that enables remote configuration of the SDO OCS owner service.
1. A command to import an owner voucher into a horizon instance.
1. A sample script to run the SDO manufacturing components (SCT - Supply Chain Tools) on a test VM device to initialize it with SDO, create the voucher, and extend it to the customer/owner.

## Build the SDO Owner Services for the Open-horizon Management Hub

1. Request and download the SDO SDK binaries tar file from [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) and unpack it in directory `sdo_sdk_binaries_linux_x64`:

  ```bash
  tar -zxvf ~/Downloads/sdo_sdk_binaries_1.7.*_linux_x64.tar.gz
  mv sdo_sdk_binaries_1.7.*_linux_x64 sdo_sdk_binaries_linux_x64
  ```

1. Build the docker container that will run all of the SDO services needed on the open-horizon management hub:

  ```bash
  # first update the VERSION variable value in Makefile, then:
  make sdo-owner-services
  ```

1. After testing the service, push it to docker hub:

  ```bash
  make publish-sdo-owner-services
  ```

## Start the SDO Owner Services on the Open-horizon Management Hub

1. On the management hub, pull the docker image:

  ```bash
  docker pull openhorizon/sdo-owner-services:latest
  ```

1. Run the docker image:

  ```bash
  # ensure all of the typical hzn environment variables are set, then:
  mkdir $HOME/sdo; cd $HOME/sdo
  curl -sS --progress-bar -o Makefile https://raw.githubusercontent.com/open-horizon/SDO-support/master/Makefile
  VERSION=latest make -W sdo-owner-services -W ocs-api/linux/ocs-api -W 'ocs-api/*.go' -W 'ocs-api/*/*.go' pull-sdo-owner-services run-sdo-owner-services
  docker logs -f sdo-owner-services
  ```

## Run Sample SDO Device Manufacturing Services to Initialize a Device

To develop/test/demo the SDO owner services, you need to initialize a VM to simulate an SDO device, and create an ownership voucher. To do this, see [sample-mfg/README.md](sample-mfg/README.md).

## Import the Ownership Voucher

From an "admin" host, copy the `voucher.json` file from the device to here, then:

```bash
tools/hzn-voucher-import voucher.json helloworld
```

## Configure the Device and Connect it to the Horizon Management Hub

Back on your VM device:

```bash
cd $HOME/sdo/sdo_sdk_binaries_linux_x64/demo/device
./device
hzn agreement list
docker ps
hzn service log -f ibm.helloworld
```
