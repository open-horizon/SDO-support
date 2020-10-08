# SDO-support

## Overview of the Open Horizon SDO Support

Edge devices built with [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) (Secure Device Onboard) can be added to an Open Horizon instance by simply importing their associated ownership vouchers and then powering on the devices.

The software in this git repository makes it easy to use SDO-enabled edge devices with Open Horizon. The Horizon SDO support consists of these components:

1. A consolidated docker image of all of the [SDO](https://software.intel.com/en-us/secure-device-onboard) "owner" services (those that run as peers to the Horizon management hub). It also includes a small REST API that enables remote configuration of the SDO OCS owner service.
1. A script called `generate-key-pair.sh` to automate the process of creating private keys, certifications, and public keys so each tenant is able to import and use their key pairs.
1. An `hzn` sub-command to import one or more ownership vouchers into a horizon instance. (An ownership voucher is a file that the device manufacturer gives to the purchaser along with the physical device.)
1. A sample script called `simulate-mfg.sh` to run the SDO manufacturing components (SCT - Supply Chain Tools) on a test VM device to initialize it with SDO, create the voucher, and extend it to the customer/owner. This script performs the same steps that a real SDO-enabled device manufacturer would.
1. A script called `owner-boot-device` that initiates the same SDO booting process on a test VM device that runs on a physical SDO-enabled device when it boots.

## <a name="use-sdo"></a>Using the SDO Support

Perform the following steps to try out the Horizon SDO support:

- [Start the SDO Owner Services](#start-services) (only has to be done the first time)
- [Generate Owner Key Pairs](#init-device)
- [Initialize a Device with SDO](#init-device)
- [Import the Ownership Voucher](#import-voucher)
- [Boot the Device to Have it Configured](#boot-device)

### <a name="start-services"></a>Start the SDO Owner Services

**Note:** This section can be removed once the SDO owner services are being deployed in the mgmt hub by default.

The SDO owner services respond to booting devices and enable administrators to import ownership vouchers. These 4 services are provided:

- **RV**: A development version of the rendezvous server, the initial service that every SDO-enabled booting device contacts. The RV redirects the device to the OPS associated with the correct Horizon management hub.
- **OPS**: The Owner Protocol Service communicates with the devices and securely downloads the device configuration scripts and files.
- **OCS**: The Owner Companion Service manages the database files that contain the device configuration information.
- **OCS-API**: A REST API that enables importing and querying ownership vouchers.

The SDO owner services are packaged as a single docker container that can be run on any server that has network access to the Horizon management hub, and that the SDO devices can reach over the network.

1. Get `run-sdo-owner-services.sh`, which is used to start the container:

   ```bash
   mkdir $HOME/sdo; cd $HOME/sdo
   curl -sSLO https://raw.githubusercontent.com/open-horizon/SDO-support/stable/docker/run-sdo-owner-services.sh
   chmod +x run-sdo-owner-services.sh
   ```

2. Run `./run-sdo-owner-services.sh -h` to see the usage, and set all of the necessary environment variables. For example:

   ```bash
   export HZN_EXCHANGE_URL=https://<cluster-url>/edge-exchange/v1
   export HZN_FSS_CSSURL=https://<cluster-url>/edge-css
   export HZN_ORG_ID=<exchange-org>
   export HZN_EXCHANGE_USER_AUTH=iamapikey:<api-key>
   ```

3. Either choose or generate a password for the Master Keystore inside the container to support Owner Attestation. For example:
   ```bash
   export SDO_KEY_PWD=123456
   ```
   **Note:** If you want to restart sdo-owner-services but wish to continue using an existing master keystore with an existing custom password, **DO NOT** forget your SDO_KEY_PWD. If you forget the password for the existing master keystore, then you must delete the container, delete the volume, and go back through [Start the SDO Owner Services](#start-services) 

4. As part of installing the Horizon management hub, you should have run [edgeNodeFiles.sh](https://github.com/open-horizon/anax/blob/master/agent-install/edgeNodeFiles.sh), which created a tar file containing `agent-install.crt`. Use that to export this environment variable:

   ```bash
   export HZN_MGMT_HUB_CERT=$(cat agent-install.crt | base64)
   ```

4. Start the SDO owner services docker container and view the log:

   ```bash
   ./run-sdo-owner-services.sh
   docker logs -f sdo-owner-services
   ```
   *In the logs you will find `<sdo-owner-svc-host>` that is needed for the subsequent steps*

#### Verify the SDO Owner Services API Endpoints

**On a Horizon "admin" host** run these simple SDO APIs to verify that the services within the docker container are accessible and responding properly. (A Horizon admin host is one that has the `horizon-cli` package, which provides the `hzn` command, and has the environment variables `HZN_EXCHANGE_URL`, `HZN_SDO_SVC_URL`, `HZN_ORG_ID`, and `HZN_EXCHANGE_USER_AUTH` set correctly for your Horizon management hub.)

1. Export these environment variables for the subsequent steps:

   ```bash
   export HZN_ORG_ID=<exchange-org>
   export HZN_EXCHANGE_USER_AUTH=iamapikey:<api-key>
   export HZN_SDO_SVC_URL=http://<sdo-owner-svc-host>:9008/api
   export SDO_RV_URL=http://<sdo-owner-svc-host>:8040
   ```

2. Query the OCS API version:

   ```bash
   curl -sS $HZN_SDO_SVC_URL/version && echo
   ```

3. Query the ownership vouchers that have already been imported (initially it will be an empty list):

   ```bash
   curl -sS -w "%{http_code}" -u "$HZN_ORG_ID/$HZN_EXCHANGE_USER_AUTH" $HZN_SDO_SVC_URL/vouchers | jq
   ```

4. "Ping" the development rendezvous server:

   ```bash
   curl -sS -w "%{http_code}" -X POST $SDO_RV_URL/mp/113/msg/20 | jq
   ```
   
### <a name="gen-keypair"></a>Generate Owner Key Pairs

If you want to expedite the process of creating key pairs, you can run `keys/generate-key-pair.sh`
To run this script you must be using Ubuntu. 

1. Go to the directory where you want your generated keys to be saved then download `generate-key-pair.sh`, which is used to create key pairs for Owner Attestation:

   ```bash
   curl -sSLO https://raw.githubusercontent.com/open-horizon/SDO-support/master/keys/generate-key-pair.sh
   chmod +x generate-key-pair.sh
   ```
   
2. Run `generate-key-pair.sh` script. If this process is being ran for a non production environment you **do not** need to create your own keys. 
You will be prompted to answer a few questions in order to produce corresponding certificates to your private keys:

   ```bash
   ./generate-key-pair.sh
   ```

3. After running `generate-key-pair.sh` you will have created and been left with two files.
- `owner-keys.tar.gz`: A tar file containing the 3 private keys and associated 3 certifications
- `Owner-Public-Key.pem`: Device customer/owner public key. This is needed to extend the voucher to the owner. Either pass it as an argument in `simulate-mfg.sh` or give this public key to a device manufacturer.
    Import your `owner-keys.tar.gz` to the master keystore inside the container by running this command 
    
   ```bash
   curl -sS -w "%{http_code}" -u "$HZN_ORG_ID/$HZN_EXCHANGE_USER_AUTH" -X POST -H Content-Type:application/octet-stream --data-binary @owner-keys.tar.gz $HZN_SDO_SVC_URL/keys && echo
   ```
### <a name="init-device"></a>Initialize a Device with SDO

The sample script called `simulate-mfg.sh` simulates the process of a manufacturer initializing a device with SDO and credentials, creating an ownership voucher, and extending it to the owner. Perform these steps **on the VM device to be initialized** (these steps are written for Ubuntu 18.04):

```bash
mkdir -p $HOME/sdo && cd $HOME/sdo
curl -sSLO https://raw.githubusercontent.com/open-horizon/SDO-support/stable/sample-mfg/simulate-mfg.sh
chmod +x simulate-mfg.sh
export SDO_RV_URL=http://<sdo-owner-svcs-host>:8040
export SDO_SAMPLE_MFG_KEEP_SVCS=true   # makes it faster if you run multiple tests
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

1. Run the `owner-boot-device` script. This starts the SDO process the normally runs when an SDO-enabled device is booted.

   ```bash
   /usr/sdo/bin/owner-boot-device ibm.helloworld
   ```

2. Your VM device is now configured as a Horizon edge node and registered with your Horizon management hub to run the helloworld example edge service. View the log of the edge service:

   ```bash
   hzn service log -f ibm.helloworld
   ```

#### Troubleshooting

- If the edge device does not get registered with your Horizon management hub, look in `/var/sdo/agent-install.log` for error messages.
- If the edge device is registered, but no edge service starts, run these commands to debug:

   ```bash
   hzn eventlog list
   hzn deploycheck all -b policy-ibm.helloworld_1.0.0 -o <exchange-org> -u iamapikey:<api-key>
   ```

## Developers Only

These steps only need to be performed by developers of this project.

### Build the SDO Owner Services for Open Horizon

1. Download these tar files from [Intel SDO Release 1.8](https://github.com/secure-device-onboard/release/releases/tag/v1.8.0) to directory `sdo/` and uppack them:

   ```bash
   mkdir -p sdo && cd sdo
   curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.8.0/iot-platform-sdk-v1.8.0.tar.gz
   tar -zxf iot-platform-sdk-v1.8.0.tar.gz
   curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.8.0/rendezvous-service-v1.8.0.tar.gz
   tar -zxf rendezvous-service-v1.8.0.tar.gz
   curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.8.0/pri-v1.8.0.tar.gz
   tar -zxf pri-v1.8.0.tar.gz
   curl --progress-bar -LO https://github.com/secure-device-onboard/release/releases/download/v1.8.0/NOTICES.tar.gz
   tar -zxf NOTICES.tar.gz
   cd ..
   ```

2. Build the docker container that will run all of the SDO services needed for Open Horizon:

   ```bash
   # first update the VERSION variable value in Makefile, then:
   make sdo-owner-services
   ```

3. After you have personally tested the service, push it to docker hub with the `testing` tag, so others from the development team can test it:

   ```bash
   make push-sdo-owner-services
   ```

4. After the development team has validated the service, publish it to docker hub as the latest patch release with the `latest` tag:

   ```bash
   make publish-sdo-owner-services
   ```

5. On a fully tested release boundary (usually when the 2nd number of the version changes), publish it to docker hub with the `stable` tag:

   ```bash
   make promote-sdo-owner-services
   ```

### Running the SDO Support During Dev/Test

When following the instructions in [Using the SDO Support](#use-sdo), set the following environment variables to work with the most recent files and docker images that you or others on the team are developing:

- In [Start the SDO Owner Services](#start-services) set:

   ```bash
   # to use the most recently committed version of agent-install.sh:
   export AGENT_INSTALL_URL=https://raw.githubusercontent.com/open-horizon/anax/master/agent-install/agent-install.sh
   # if the hostname of this host is not resolvable by the device, provide the IP address to RV instead
   export SDO_OWNER_SVC_HOST="1.2.3.4"
   # when curling run-sdo-owner-services.sh use the master branch instead of the stable tag
   ```

- In [Initialize a Device with SDO](#init-device) set:

   ```bash
   # set SDO_SUPPORT_REPO 1 of these 2 ways:
   export SDO_SUPPORT_REPO=https://raw.githubusercontent.com/open-horizon/SDO-support/master   # using owner-boot-device from the most recent committed upstream
   export SDO_SUPPORT_REPO=https://raw.githubusercontent.com/<my-github-id>/SDO-support/<my-branch>   # using owner-boot-device from the branch you are working on
   # set SDO_MFG_IMAGE_TAG 1 of these 2 ways:
   export SDO_MFG_IMAGE_TAG=testing   # using the most recent development docker image from the team
   export SDO_MFG_IMAGE_TAG=1.2.3   # using the docker image you are still working on
   # this will speed repetitive testing, because it will leave the mfg containers running if they haven't changed
   export SDO_SAMPLE_MFG_KEEP_SVCS=true
   # when curling simulate-mfg.sh use the master branch instead of the stable tag
   ```

- In [Import the Ownership Voucher](#import-voucher) set: (nothing special so far)
- In [Boot the Device to Have it Configured](#boot-device) set: (nothing special so far)
