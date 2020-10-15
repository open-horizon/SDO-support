# Sample Owner/Customer Keys

The `sample-owner-key*` files are a sample key pair for the device owner/customer to use in dev/test/demos:

- `sample-owner-key.pub` was originally taken from `Services.tar` file `SCT/startup-docker.sh` . This is used by default in `sample-mfg/simulate-mfg.sh` if you don't pass your own owner public key.
- `sample-owner-keystore.p12` was taken from `iot-platform-sdk-v1.8.0/ocs/config/db/v1/creds/owner-keystore.p12` . (It is the same as the SDO 1.7 SDK binary download, file `SDOIotPlatformSDK/ocs/config/db/v1/creds/owner-keystore.p12`.) This is used by default in `run-sdo-owner-services.sh` if you don't pass your own owner private key. You can find the keystore password and then use it to see what is in the p12 bundle:

  ```bash
  grep fs.owner.keystore-password ../sdo/iot-platform-sdk-v1.8.0/ocs/config/application.properties
  # use the password from above cmd in this cmd:
  keytool -list -v -storetype PKCS12 -keystore ../sdo/iot-platform-sdk-v1.8.0/ocs/config/db/v1/creds/owner-keystore.p12 -storepass '<keystore-password>'
  ```  
  
# Generating Owner/Customer Keys
If you want to expedite the process of creating key pairs, you can run `keys/generate-key-pair.sh`
To run this script you must be using Ubuntu. 

### Install Script Into Directory Where You Want Your Key Pair Files

1. Go to the directory where you want your generated keys to be saved then download `generate-key-pair.sh`, which is used to create key pairs for Owner Attestation:

   ```bash
   curl -sSLO https://github.com/open-horizon/SDO-support/releases/download/v1.8/generate-key-pair.sh
   chmod +x generate-key-pair.sh
   ```
   
2. Run `generate-key-pair.sh` script. You will be prompted to answer a few questions in order to produce corresponding certificates to your private keys:

   ```bash
   ./generate-key-pair.sh
   ```
   
### Put Key Pairs To Use

Once you have created your key pair, pass them as arguments to these scripts:

- `curl -sS -w "%{http_code}" -u "$HZN_ORG_ID/$HZN_EXCHANGE_USER_AUTH" -X POST -H Content-Type:application/octet-stream --data-binary @owner-keys.tar.gz $HZN_SDO_SVC_URL/keys && echo`
- `sample-mfg/simulate-mfg.sh Owner-Public-Key.pem`


# Developers Only

These steps only need to be performed by developers of this project.

### Deciding Which Key Encryption Type To Use  

SCT, Device, and Owner keys must use the same key type. In order to run a successful test suite while passing your own generated key pair, you must first verify the type of encryption used for the device key and SCT key. We do this by inspecting the certificate that corresponds with the key file. 
The device certificate `device.crt` can be found in `sdo_device_binaries_1.8_linux_x64/device/creds/device.crt`. The SCT key certificate can be found inside `sdo_device_binaries_1.8_linux_x64/keys/manufacturer-keystore.p12`

1. Assuming that there is an existing owner's certificate and private key stored in a keystore as a PrivateKeyEntry under the alias 'Owner', run the following commands to list the contents of a keystore, then extract the owner's certificate into <owner_certificate.pem>:
   ```bash
   keytool -list -v -keystore path/to/owner-keystore.p12
   keytool -exportcert -alias Owner -file <owner-certificate.crt> -rfc -keystore /path/to/owner-keystore.p12
   ```
   **You will need to know the owner-keystore.p12 password in order to export a certificate.**
   
2. Once you have the certificate, you can find out the type of key by looking at the ```Subject Public Key Info: Public Key Algorithm``` that can be found by running the following command:
   ```bash
   openssl x509 -in <owner-certificate.crt> -text
   ```
3. To extract a private key from a .p12 file, then decrypt that key
    ```bush
    openssl pkcs12 -in <owner-keystore.p12> -nocerts -out <private-key.pem>
    cat <private-key.pem>
    openssl rsa -in <private-key.pem> -out <private-key.pem>
    ```

### Creating Your Own Owner Key Pair

The Intel documentation for doing this can be found in [secure-device-onboard/docs](https://github.com/secure-device-onboard/docs/blob/master/docs/iot-platform-sdk/running-the-demo.md) repository

1. Run one of these three commands to generate a private key using a specific encryption type. (ECDSA256, ECDSA384, or RSA):

   ```bash
   mkdir keyPair && cd keyPair
   openssl ecparam -genkey -name secp256r1 -out ec256private-key.pem
   openssl ecparam -genkey -name secp384r1 -out ec384private-key.pem
   openssl genrsa -out rsaprivate-key.pem 2048
   ```

2. Generate a self signed certificate that corresponds with one of the private keys that was just created.

   ```bash
   openssl req -x509 -sha256 -nodes -days 3650 -key ec256private-key.pem -out ec256cert.crt
   openssl req -x509 -sha384 -nodes -days 3650 -key ec384private-key.pem -out ec384cert.crt
   openssl req -x509 -days 365 -key rsaprivate-key.pem -out rsacert.pem
   ```
   
3. After the private key and owner certificate has been created, this command will create a public key corresponding with the owner certificate from the previous step. This command is the same for any encryption key type.

   ```bash
   openssl x509 -pubkey -noout -in <key-cert>.crt > <public-key>.pub
   ```
   
4. This is how to place a private key and certificate into a keystore. This keystore can be used as an argument when running `run-sdo-owner-services.sh` to pass your own Master Keystore. You will need to have a password for this key store. 

    ```bash
    openssl pkcs12 -export -in owner-cert.pem -inkey <owner-private-key>.pem -name Owner -out private-key-store.p12
    ```
    **(Optional) In the case of importing one keystore into another, you must know the password of both keystores**
    ```bash
    keytool -importkeystore -destkeystore path/to/owner-keystore.p12 -srckeystore private-key-store.p12 -srcstoretype PKCS12 -alias Owner
    ```
   
5. At this point you should have created a private key, public key, key certificate, and a key store containing the both key certificate and private key files.
Your 'Key Pair' is  `<owner-pub-key-file>.pem` and `<owner-private-key-store>.p12`




