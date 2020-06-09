# SDO-support

Edge devices built with [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) (Secure Device Onboard) can be easily added to an open-horizon instance with true single-touch (plug the device in and power on).

The software in this git repository makes it easy to use SDO edge devices with open-horizon. The horizon SDO support consists of main components:

1. A consolidated docker image of all of the SDO "owner" services (those that run in the horizon management hub). It also includes a small REST API that enables remote configuration of the SDO OCS owner service.
1. A command to import an owner voucher into a horizon instance.
1. A sample script to run the SDO manufacturing components (SCT - Supply Chain Tools) on a test VM device to initialize it with SDO, create the voucher, and extend it to the customer/owner.
1. A script that simulates booting the test VM device.

## Run Sample SDO Device Manufacturing Services to Initialize a Device

To develop/test/demo the SDO owner services, you need to initialize a VM to simulate an SDO device, and create an ownership voucher. To do this, see [sample-mfg/README.md](sample-mfg/README.md).

## Import the Ownership Voucher

On an "admin" host:

1. Install the `horizon-cli` package
1. Set environment variables: `HZN_EXCHANGE_URL`, `HZN_SDO_SVC_URL`, `HZN_ORG_ID`, `HZN_EXCHANGE_USER_AUTH`
1. Copy the `voucher.json` file from your VM device to here
1. `hzn voucher import voucher.json -e helloworld`

## Configure the Device and Connect it to the Horizon Management Hub

Back on your VM device:

```bash
cd $HOME/sdo
curl --progress-bar -O https://raw.githubusercontent.com/open-horizon/SDO-support/master/tools/owner-boot-device
chmod +x owner-boot-device
./owner-boot-device ibm.helloworld
hzn service log -f ibm.helloworld
```

## Developers Only

These steps only need to be performed by developers of this project.

### Build the SDO Owner Services for the Open-horizon Management Hub

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

### Start a Test Instance of the SDO Owner Services

If the SDO owner services docker image is not already running on the Horizon management hub, or you want to run a newer/test version:

1. Get `run-sdo-owner-services.sh`:

  ```bash
  mkdir $HOME/sdo; cd $HOME/sdo
  curl --progress-bar -O https://raw.githubusercontent.com/open-horizon/SDO-support/master/docker/run-sdo-owner-services.sh
  ```

1. Review the usage with `run-sdo-owner-services.sh -h` and ensure you set all of the necessary environment variables correctly.

1. Start the SDO owner services docker image and view the log:

  ```bash
  ./run-sdo-owner-services.sh   # can specify args: latest <owner-private-key-file>
  docker logs -f sdo-owner-services
  ```

### Verify the SDO Owner Services API Endpoints

These simple SDO APIs verify that the services within the docker container are accessible and responding properly:

1. Query the OCS API version:

  ```bash
  curl -sS $HZN_SDO_SVC_URL/version && echo
  ```

1. Query the ownership vouchers that have already been imported (initially it will be an empty list):

  ```bash
  curl -sS -w "%{http_code}" -u "$HZN_ORG_ID/$HZN_EXCHANGE_USER_AUTH" $HZN_SDO_SVC_URL/vouchers | jq
  ```

1. "Ping" the development rendezvous server:

  ```bash
  curl -sS -w "%{http_code}" -X POST $SDO_RV_URL/mp/113/msg/20 | jq
  ```
