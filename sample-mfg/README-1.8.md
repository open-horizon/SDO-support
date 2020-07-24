# Sample SDO Manufacturer Scripts and Docker Images

### Warning: This readme is under construction. Do not use yet!!

These sample scripts and docker images enable you to develop/test/demo the SDO owner services by initializing a VM to simulate an SDO-enabled  device and creating an ownership voucher. See the [../README.md](../README.md) for instructions on how to use them in the context of the overall SDO process.

## Developers Only

These steps only need to be performed by developers of this project.

### Build a tar file of the SDO files needed on the device

1. Now create the small tar file that will be needed on each simulated device:

  ```bash
  make sdo_device_binaries_1.8_linux_x64.tar.gz
  ```

2. Upload the tar file to https://github.com/open-horizon/SDO-support/releases with the title `SDO device binaries 1.8`, so the tar file download URL will be https://github.com/open-horizon/SDO-support/releases/download/sdo_device_binaries_1.8/sdo_device_binaries_1.8_linux_x64.tar.gz

### Build the Sample SDO Manufacturer Docker Images

1. Build the SDO manufacturer services:

  ```bash
  make sdo-mfg-services
  ```

2. After testing the services, push them to docker hub:

  ```bash
  make publish-sdo-mfg-services
  ```
