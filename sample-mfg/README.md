# Sample SDO Manufacturer Scripts and Docker Images

These sample scripts and docker images enable you to develop/test/demo the SDO owner services by initializing a VM to simulate an SDO-enabled  device and creating an ownership voucher. See the [../README.md](../README.md) for instructions on how to use them in the context of the overall SDO process.

## Developers Only

These steps only need to be performed by developers of this project.

### Build a tar file of the SDO files needed on the device

1. Create the small tar file that will be needed on each simulated device:

  ```bash
  make sdo_device_binaries_1.10_linux_x64.tar.gz
  ```

2. Create a new release in https://github.com/open-horizon/SDO-support/releases with the title `SDO 1.10` and tag `v1.10`. Upload the tar file you just made to that release. The download URL should be https://github.com/open-horizon/SDO-support/releases/download/v1.10/sdo_device_binaries_1.10_linux_x64.tar.gz

### <a name="bld-mfg-images"></a>Build the Sample SDO Manufacturer Docker Images

1. If you have not already done so, download this tar file from [Intel SDO Release 1.10.1](https://github.com/secure-device-onboard/release/releases/tag/v1.10.1) to directory `../sdo/` and unpack it:

  ```bash
  mkdir -p ../sdo && cd ../sdo
  curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.10.1/supply-chain-tools-v1.10.1.tar.gz
  tar -zxf supply-chain-tools-v1.10.1.tar.gz
  cd ../sample-mfg
  ```

2. Build the SDO manufacturer services:

  ```bash
  make sdo-mfg-services
  ```

3. After you have personally tested the services, push them to docker hub with the `testing` tag, so others from the development team can test it:

  ```bash
  make push-sdo-mfg-services
  ```

4. After the development team has validated the services, publish them to docker hub as the latest patch release with the `latest` tag:

  ```bash
  make publish-sdo-mfg-services
  ```

5. On a fully tested release boundary (usually when the 2nd number of the version changes), publish them to docker hub with the tag considered stable:

  ```bash
  make promote-sdo-mfg-services
  ```
