# Sample Owner/Customer Keys

The `sample-owner-key*` files are a sample key pair for the device owner/customer to use in dev/test/demos:

- `sample-owner-key.pub` was originally taken from `Services.tar` file `SCT/startup-docker.sh` . This is used by default in `sample-mfg/simulate-mfg.sh` if you don't pass your own owner public key.
- `sample-owner-keystore.p12` was originally taken from the SDO SDK binary download, file `SDOIotPlatformSDK/ocs/config/db/v1/creds/owner-keystore.p12` . This is used by default in `run-sdo-owner-services.sh` if you don't pass your own owner private key. You can find the keystore password and then use it to see what is in the p12 bundle:

  ```bash
  cd ../sdo_sdk_binaries_linux_x64
  grep fs.owner.keystore SDOIotPlatformSDK/ocs/config/application.properties
  # use the password from above cmd in this cmd:
    keytool -list -v -storetype PKCS12 -keystore SDOIotPlatformSDK/ocs/config/db/v1/creds/owner-keystore.p12 -storepass '<keystore-password>'
  ```

## Creating Your Own Owner Key Pair

The instructions for doing this are in **Intel-SDO-IoT-Platform-Integration-SDK-Reference-Guide.pdf**, section **Generating RSA Key-Pair for Owner Attestation**.

Once you have created your key pair, pass them as arguments to these scripts:

- `sample-mfg/simulate-mfg.sh sample-mfg/keys/sample-mfg-key.p12 <owner-pub-key-file>`
- `docker/run-sdo-owner-services.sh latest <owner-private-key-file>`
