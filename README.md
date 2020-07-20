# SDO-support

## Overview of the Open Horizon SDO Support

Edge devices built with [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) (Secure Device Onboard) can be added to an Open Horizon instance by simply importing their associated ownership vouchers and then powering on the devices.

The software in this git repository makes it easy to use SDO-enabled edge devices with Open Horizon. The Horizon SDO support consists of these components:

1. A consolidated docker image of all of the [SDO](https://software.intel.com/en-us/secure-device-onboard) "owner" services (those that run as peers to the Horizon management hub). It also includes a small REST API that enables remote configuration of the SDO OCS owner service.
1. An `hzn` sub-command to import one or more ownership vouchers into a horizon instance. (An ownership voucher is a file that the device manufacturer gives to the purchaser along with the physical device.)
1. A sample script called `simulate-mfg.sh` to run the SDO manufacturing components (SCT - Supply Chain Tools) on a test VM device to initialize it with SDO, create the voucher, and extend it to the customer/owner. This script performs the same steps that a real SDO-enabled device manufacturer would.
1. A script called `owner-boot-device` that initiates the same SDO booting process on a test VM device that runs on a physical SDO-enabled device when it boots.

### Technology Preview

The current status of this project is "tech-preview". At this time it should only be used to test the SDO process and get familiar with it, for the purpose of planning for its use in the future. Enhancements to this project will be made over the next several months as it moves toward production-ready status.

## Using the SDO Support

Perform the following steps to try out the Horizon SDO support:

- [Start the SDO Owner Services](#start-services) (only has to be done the first time)
- [Initialize a Device with SDO](#init-device)
- [Import the Ownership Voucher](#import-voucher)
- [Boot the Device to Have it Configured](#boot-device)

### <a name="start-services"></a>Start the SDO Owner Services

The SDO owner services respond to booting devices and enable administrators to import ownership vouchers. These 4 services are provided:

- **RV**: A development version of the rendezvous server, the initial service that every SDO-enabled booting device contacts. The RV redirects the device to the OPS associated with the correct Horizon management hub.
- **OPS**: The Owner Protocol Service communicates with the devices and securely downloads the device configuration scripts and files.
- **OCS**: The Owner Companion Service manages the database files that contain the device configuration information.
- **OCS-API**: A REST API that enables importing and querying ownership vouchers.

The SDO owner services are packaged as a single docker container that can be run on any server that has network access to the Horizon management hub, and that the SDO devices can reach over the network.

1. Get `run-sdo-owner-services.sh`, which is used to start the container:

  ```bash
  mkdir $HOME/sdo; cd $HOME/sdo
  curl --progress-bar -O https://raw.githubusercontent.com/open-horizon/SDO-support/master/docker/run-sdo-owner-services.sh
  chmod +x run-sdo-owner-services.sh
  ```

2. Run `./run-sdo-owner-services.sh -h` to see the usage, and set all of the necessary environment variables.

3. Start the SDO owner services docker container and view the log:

  ```bash
  ./run-sdo-owner-services.sh
  docker logs -f sdo-owner-services
  ```

#### Verify the SDO Owner Services API Endpoints

**On a Horizon "admin" host** run these simple SDO APIs to verify that the services within the docker container are accessible and responding properly. (A Horizon admin host is one that has the `horizon-cli` package, which provides the `hzn` command, and has the environment variables `HZN_EXCHANGE_URL`, `HZN_SDO_SVC_URL`, `HZN_ORG_ID`, and `HZN_EXCHANGE_USER_AUTH` set correctly for your Horizon management hub.)

1. Query the OCS API version:

  ```bash
  curl -sS $HZN_SDO_SVC_URL/version && echo
  ```

2. Query the ownership vouchers that have already been imported (initially it will be an empty list):

  ```bash
  curl -sS -w "%{http_code}" -u "$HZN_ORG_ID/$HZN_EXCHANGE_USER_AUTH" $HZN_SDO_SVC_URL/vouchers | jq
  ```

3. "Ping" the development rendezvous server:

  ```bash
  curl -sS -w "%{http_code}" -X POST $SDO_RV_URL/mp/113/msg/20 | jq
  ```

### <a name="init-device"></a>Initialize a Device with SDO

The sample script called `simulate-mfg.sh` simulates the process of a manufacturer initializing a device with SDO and credentials, creating an ownership voucher, and extending it to the owner. Perform these steps **on the VM device to be initialized** (these steps are written for Ubuntu 18.04):

```bash
apt update && apt install -y openjdk-11-jre-headless docker docker-compose
mkdir -p $HOME/sdo && cd $HOME/sdo
curl --progress-bar -O https://raw.githubusercontent.com/open-horizon/SDO-support/master/sample-mfg/simulate-mfg.sh
chmod +x simulate-mfg.sh
export SDO_RV_URL=http://<sdo-owner-svcs-host>:8040
./simulate-mfg.sh
```

### <a name="import-voucher"></a>Import the Ownership Voucher

The ownership voucher created for the device in the previous step needs to be imported to the SDO owner services. **On the Horizon admin host**:

1. When you purchase a physical SDO-enabled device, you receive an ownership voucher from the manufacturer. In the case of the VM device you have configured to simulate an SDO-enabled device, the analogous step is to copy the file `~/sdo/voucher.json` from your VM device to here.
2. Import the ownership voucher, specifying that this device should be initialized with policy to run the helloworld example edge service:

  ```bash
  hzn voucher import voucher.json -e helloworld
  ```

### <a name="boot-device"></a>Boot the Device to Have it Configured

When an SDO-enabled device boots, it starts the SDO process which contacts the SDO owner services to configure the device for this Horizon instance. **Back on your VM device**, simulate the booting of the device and watch SDO configure it:

1. Get the `owner-boot-device` script:

  ```bash
  cd $HOME/sdo
  curl --progress-bar -O https://raw.githubusercontent.com/open-horizon/SDO-support/master/tools/owner-boot-device
  chmod +x owner-boot-device
  ```

2. Run the `owner-boot-device` script. This starts the SDO process the normally runs when an SDO-enabled device is booted.

  ```bash
  ./owner-boot-device ibm.helloworld
  ```

3. Your VM device is now configured as a Horizon edge node and registered with your Horizon management hub to run the helloworld example edge service. View the log of the edge service:

  ```bash
  hzn service log -f ibm.helloworld
  ```

## Developers Only

These steps only need to be performed by developers of this project.

### Build the SDO Owner Services for Open Horizon

1. Request and download the SDO SDK binaries tar file from [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) and unpack it in directory `sdo_sdk_binaries_linux_x64`:

  ```bash
  tar -zxvf ~/Downloads/sdo_sdk_binaries_1.7.*_linux_x64.tar.gz
  mv sdo_sdk_binaries_1.7.*_linux_x64 sdo_sdk_binaries_linux_x64
  ```

2. Build the docker container that will run all of the SDO services needed for Open Horizon:

  ```bash
  # first update the VERSION variable value in Makefile, then:
  make sdo-owner-services
  ```

3. After testing the service, push it to docker hub:

  ```bash
  make publish-sdo-owner-services
  ```
