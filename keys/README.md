# Sample Owner/Customer Keys

The `sample-owner-key.*` files are a sample key pair for the device owner/customer for use in dev/test/demos:

- `sample-owner-key.pub` was originally taken from `Services.tar` file `SCT/startup-docker.sh` . This is used by default in `sample-mfg/simulate-mfg.sh` if you don't pass your own owner public key.
- `sample-owner-keystore.p12` was originally taken from the SDO SDK binary download, file `SDOIotPlatformSDK/ocs/config/db/v1/creds/owner-keystore.p12` . It is used in the sdo-owner-services container, if not overridden. You can find the keystore password and then use it to see what is in the p12 bundle:

  ```bash
  cd ../sdo_sdk_binaries_linux_x64
  grep fs.owner.keystore SDOIotPlatformSDK/ocs/config/application.properties
  # use the password from above cmd in this cmd:
    keytool -list -v -storetype PKCS12 -keystore SDOIotPlatformSDK/ocs/config/db/v1/creds/owner-keystore.p12 -storepass '<keystore-password>'
  ```
