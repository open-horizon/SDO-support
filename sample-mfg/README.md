# Sample SDO Manufacturer Scripts and Docker Images

These sample scripts and docker images enable you to develop/test/demo the SDO owner services by initializing a VM to simulate an SDO-enabled  device and creating an ownership voucher. See the [../README.md](../README.md) for instructions on how to use them in the context of the overall SDO process.

## Developers Only

These steps only need to be performed by developers of this project.

### Build a tar file of the SDO files needed on the device

1. Rebuild the device jar file with a longer timeout. The default device jar that runs on the VM simulated device has a timeout of 60 seconds for the agent install script to be downloaded and run to completion. In some cases this isn't enough time, so rebuild the device jar with a timeout of 10 minutes. On an ubuntu 18.04 host with `openjdk-11-jdk:amd64` and `maven` installed:

    - Get and unpack `sdo_sdk_source_1.7.0.89.tar.gz`
    - `cd sdo_sdk_source_1.7.0.89/cri`
    - Change the timeout: `sed -i -e 's/execTimeout = Duration.ofSeconds(60)/execTimeout = Duration.ofSeconds(600)/' protocol/src/main/java/com/intel/sdo/SdoSysModuleDevice.java`
    - Build all of the jar/war files: `mvn package`
    - `cd ../..`
    - Copy `sdo_sdk_source_1.7.0.89/cri/device/target/device-1.7.0.jar` back to this host and into `sdo_device_binaries_1.7_linux_x64/cri/`

1. Now create the small tar file that will be needed on each simulated device:

  ```bash
  make sdo_device_binaries_1.7_linux_x64.tar.gz
  ```

1. Upload the tar file to https://github.com/open-horizon/SDO-support/releases with the title `SDO device binaries 1.7`, so the tar file download URL will be https://github.com/open-horizon/SDO-support/releases/download/sdo_device_binaries_1.7/sdo_device_binaries_1.7_linux_x64.tar.gz

### Build the Sample SDO Manufacturer Docker Images

1. Build the SDO manufacturer services:

  ```bash
  make sdo-mfg-services
  ```

1. After testing the services, push them to docker hub:

  ```bash
  make publish-sdo-mfg-services
  ```
