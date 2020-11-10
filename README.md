# SDO-support

## Overview of the Open Horizon SDO Support

Edge devices built with [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) (Secure Device Onboard) can be added to an Open Horizon instance by simply importing their associated ownership vouchers and then powering on the devices.

The software in this git repository provides integration between SDO and Open Horizon, making it easy to use SDO-enabled edge devices with Horizon. The Horizon SDO support consists of these components:

1. A consolidated docker image of all of the SDO "owner" services (those that run on the Horizon management hub).
1. An SDO rendezvous server (RV) that is the first service that booting SDO-enabled devices contact. The rendezvous server redirects the device to the correct Horizon instance for configuration.
1. A script called `generate-key-pair.sh` to automate the process of creating private keys, certificates, and public keys so each tenant is able to import and use their own key pairs so that they can securely use SDO.
1. An `hzn voucher` sub-command to import one or more ownership vouchers into a horizon instance. (An ownership voucher is a file that the device manufacturer gives to the purchaser (owner) along with the physical device.)
1. A sample script called `simulate-mfg.sh` to run the SDO-enabling steps on a VM "device" that a device manufacturer would run on a physical device. This enables you to try out the SDO process with your Horizon instance before purchasing SDO-enabled devices.
1. A script called `owner-boot-device` that performs the second half of using a simulated VM "device" by initiating the same SDO booting process on the VM that runs on a physical SDO-enabled device when it boots.

## <a name="use-sdo"></a>Using the SDO Support

Perform the following steps to try out the Horizon SDO support:

- [Start the SDO Owner Services](#start-services) (only has to be done the first time)
- [Generate Owner Key Pairs](#gen-keypair)
- [Initialize a Device with SDO](#init-device)
- [Import the Ownership Voucher](#import-voucher)
- [Boot the Device to Have it Configured](#boot-device)

### <a name="start-services"></a>Start the SDO Owner Services

The SDO owner services respond to booting devices and enable administrators to import ownership vouchers. These owner services are bundled into a single container which is normally started as part of installing the Horizon management hub, by either the [All-in-1 developer management hub](https://github.com/open-horizon/devops/blob/master/mgmt-hub/README.md) or by a vendor that provides a production version of Horizon.

If you need to run your own instance of the SDO owner services for development purposes, see [Starting Your Own Instance of the SDO Owner Services](#start-services-developer).

#### <a name="verify-services"></a>Verify the SDO Owner Services API Endpoints

Before continuing with the rest of the SDO process, it is good to verify that you have the correct information necessary to reach the SDO owner service endpoints. **On a Horizon "admin" host** run these simple SDO APIs to verify that the services within the docker container are accessible and responding properly. (A Horizon admin host is one that has the `horizon-cli` package installed, which provides the `hzn` command, and has the environment variables `HZN_EXCHANGE_URL`, `HZN_SDO_SVC_URL`, `HZN_ORG_ID`, and `HZN_EXCHANGE_USER_AUTH` set correctly for your Horizon management hub.)

1. Export these environment variables for the subsequent steps. Contact the management hub installer for the exact values:

   ```bash
   export HZN_ORG_ID=<exchange-org>
   export HZN_EXCHANGE_USER_AUTH=<user>:<password>
   export HZN_SDO_SVC_URL=<protocol>://<sdo-owner-svc-host>:<ocs-api-port>/<ocs-api-path>
   export SDO_RV_URL=http://sdo-sbx.trustedservices.intel.com:80
   ```

   **Note:**
   * The Open Horizon SDO support code includes a built-in rendezvous server that can be used during development or air-gapped environments. See [Running the SDO Support During Dev/Test](#running-dev-test).

2. Query the OCS API version:

   ```bash
   curl -sS $HZN_SDO_SVC_URL/version && echo
   ```

3. Query the ownership vouchers that have already been imported (initially it will be an empty list):

   ```bash
   # either use curl directly
   curl -sS -w "%{http_code}" -u "$HZN_ORG_ID/$HZN_EXCHANGE_USER_AUTH" $HZN_SDO_SVC_URL/vouchers | jq
   # or use the hzn command, if you have the horizon-cli package installed
   hzn voucher list
   ```

4. "Ping" the rendezvous server:

   ```bash
   curl -sS -w "%{http_code}" -H Content-Type:application/json -X POST $SDO_RV_URL/mp/113/msg/20 | jq
   ```
   
### <a name="gen-keypair"></a>Generate Owner Key Pairs

For production use of SDO, you need to create 3 key pairs and import them into the owner services container. These key pairs enable you to securely take over ownership of SDO ownership vouchers from SDO-enabled device manufacturers, and to securely configure your booting SDO devices. Use the provided `generate-key-pair.sh` script to easily create the necessary key pairs. (If you are only trying out SDO in a dev/test environment, you can use the built-in sample key pairs and skip this section. You can always add your own key pairs later.)

Note: you only have to perform the steps in this section once. The keys create and import can be used with all of your devices.

1. Go to the directory where you want your generated keys to be saved then download `generate-key-pair.sh`.

   ```bash
   curl -sSLO https://github.com/open-horizon/SDO-support/releases/download/v1.8/generate-key-pair.sh
   chmod +x generate-key-pair.sh
   ```
   
2. Run the `generate-key-pair.sh` script. You will be prompted to answer a few questions in order to produce certificates for your private keys. (The prompts can be avoided by setting environment variables. Run `./generate-key-pair.sh -h` for details.) You must be using Ubuntu to run this script.

   ```bash
   ./generate-key-pair.sh
   ```

3. Two files are created by `generate-key-pair.sh`:
   - `owner-keys.tar.gz`: A tar file containing the 3 private keys and associated certificates. This file will be imported into the owner services container in the next step.
   - `owner-public-key.pem`: The corresponding customer/owner public keys (all in a single file). This is used by the device manufacturer to securely extend the vouchers to the owner. Pass this file as an argument whenever running simulate-mfg.sh, and give this public key to each device manufacturer producing SDO-enabled devices for you.
    
4. **On your admin host** import `owner-keys.tar.gz` into the SDO owner services: 
    
   ```bash
   curl -sS -w "%{http_code}" -u "$HZN_ORG_ID/$HZN_EXCHANGE_USER_AUTH" -X POST -H Content-Type:application/octet-stream --data-binary @owner-keys.tar.gz $HZN_SDO_SVC_URL/keys && echo
   ```

### <a name="init-device"></a>Initialize a Test VM Device with SDO

If you already have a physical SDO-enabled device, you can use that instead, and skip this section.

The sample script called `simulate-mfg.sh` simulates the steps of an SDO-enabled device manufacturer: initializes your "device" with SDO and credentials, creates an ownership voucher, and extends it to you the owner. Perform these steps **on the VM device to be initialized** (these steps are written for Ubuntu 18.04):

```bash
mkdir -p $HOME/sdo && cd $HOME/sdo
curl -sSLO https://github.com/open-horizon/SDO-support/releases/download/v1.8/simulate-mfg.sh
chmod +x simulate-mfg.sh
export SDO_RV_URL=http://sdo-sbx.trustedservices.intel.com:80
export SDO_SAMPLE_MFG_KEEP_SVCS=true   # makes it faster if you run multiple tests
./simulate-mfg.sh
```

This creates an ownership voucher in the file `/var/sdo/voucher.json`.

### <a name="import-voucher"></a>Import the Ownership Voucher

The ownership voucher created for the device in the previous step needs to be imported to the SDO owner services. **On the Horizon admin host**:

1. When you purchase a physical SDO-enabled device, you receive an ownership voucher from the manufacturer. In the case of the VM device you have configured to simulate an SDO-enabled device, the analogous step is to copy the file `/var/sdo/voucher.json` from your VM device to here.
2. Import the ownership voucher, specifying that this device should be initialized with policy to run the helloworld example edge service:

   ```bash
   hzn voucher import voucher.json -e helloworld
   ```

### <a name="boot-device"></a>Boot the Device to Have it Configured

When an SDO-enabled device boots, it starts the SDO process. The first thing it does is contact the rendezvous server, which redirects it to the SDO owner services in your Horizon instance. To simulate this process in your VM device, perform these steps:

1. **Back on your VM device** run the `owner-boot-device` script:

   ```bash
   /usr/sdo/bin/owner-boot-device ibm.helloworld
   ```

2. Your VM device is now configured as a Horizon edge node and registered with your Horizon management hub to run the helloworld example edge service. View the log of the edge service:

   ```bash
   hzn service log -f ibm.helloworld
   ```

Now that SDO has configured your edge device, it is automatically disabled on this device so that when the device is rebooted SDO will not run. (The sole purpose of SDO is configuration of a brand new device.) For ongoing maintenance and configuration of the edge device, use the `hzn` command. For example, you can update the node policy to cause other edge services to be deployed to it by either of these two ways:

* On this edge device: `hzn policy update ...`
* Centrally, on an admin host: `hzn exchange node updatepolicy <node-id> ...`

(Use the `-h` flag to see the help for each of these commands.)

#### <a name="troubleshooting"></a>Troubleshooting

- If the edge device does not get registered with your Horizon management hub, look in `/var/sdo/agent-install.log` for error messages.
- If the edge device is registered, but no edge service starts, run these commands to debug:

   ```bash
   hzn eventlog list
   hzn deploycheck all -b policy-ibm.helloworld_1.0.0 -o <exchange-org> -u iamapikey:<api-key>
   ```

## <a name="developers-only"></a>Developers Only

These steps only need to be performed by developers of this project.

### <a name="build-owner-svcs"></a>Build the SDO Owner Services for Open Horizon

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

5. On a fully tested release boundary (usually when the 2nd number of the version changes), publish it to docker hub with the tag considered stable:

   ```bash
   make promote-sdo-owner-services
   ```

### <a name="build-simulated-mfg"></a>Build the Simulated Device Manufacturer Files

These steps are found in the [Developers Only section of Sample SDO Manufacturer Scripts and Docker Images](sample-mfg/README.md#developers-only).

### <a name="start-services-developer"></a>Starting Your Own Instance of the SDO Owner Services

The SDO owner services respond to booting devices and enable administrators to import ownership vouchers. These 4 services are provided:

- **RV**: A development version of the rendezvous server, the initial service that every SDO-enabled booting device contacts. The RV redirects the device to the OPS associated with the correct Horizon management hub.
- **OPS**: The Owner Protocol Service communicates with the devices and securely downloads the device configuration scripts and files.
- **OCS**: The Owner Companion Service manages the database files that contain the device configuration information.
- **OCS-API**: A REST API that enables importing and querying ownership vouchers.

The SDO owner services are packaged as a single docker container that can be run on any server that has network access to the Horizon management hub, and that the SDO devices can reach over the network.

1. Get `run-sdo-owner-services.sh`, which is used to start the container:

   ```bash
   mkdir $HOME/sdo; cd $HOME/sdo
   curl -sSLO https://raw.githubusercontent.com/open-horizon/SDO-support/master/docker/run-sdo-owner-services.sh
   chmod +x run-sdo-owner-services.sh
   ```

2. Run `./run-sdo-owner-services.sh -h` to see the usage, and set all of the necessary environment variables. For example:

   ```bash
   export HZN_EXCHANGE_URL=https://<cluster-url>/edge-exchange/v1
   export HZN_FSS_CSSURL=https://<cluster-url>/edge-css
   export HZN_ORG_ID=<exchange-org>
   export HZN_EXCHANGE_USER_AUTH=iamapikey:<api-key>
   ```

3. Either choose or generate a password for the master keystore inside the owner services container and assign it to SDO_KEY_PWD. For example:
   ```bash
   export SDO_KEY_PWD=123456
   ```
   **Note:** Save the password in a secure, persistent, place. You will need to pass this same password into the owner services container each time it is restarted. If you forget the password for the existing master keystore, then you must delete the container, delete the volume, and go back through [Start the SDO Owner Services](#start-services) 

4. As part of installing the Horizon management hub, you should have run [edgeNodeFiles.sh](https://github.com/open-horizon/anax/blob/master/agent-install/edgeNodeFiles.sh), which created a tar file containing `agent-install.crt`. Use that to export this environment variable:

   ```bash
   export HZN_MGMT_HUB_CERT=$(cat agent-install.crt | base64)
   ```

4. Start the SDO owner services docker container and view the log:

   ```bash
   ./run-sdo-owner-services.sh
   docker logs -f sdo-owner-services
   ```

5. Perform the user verification steps in [Verify the SDO Owner Services API Endpoints](#verify-services).

6. Perform these additional developer verification steps:

   ```bash
   guid=$(jq -r .oh.g voucher.json)   # if you have a current voucher
   guid='ox0fh+4kSJC6vbpCTpKbLg=='  # if you do NOT have a current voucher
   curl -sS -w "%{http_code}" -H Content-Type:application/json -d '{"g2":"'$guid'","n5":"qoVoYKjUn7d6g3KaBrFXfQ==","pe":1,"kx":"ECDH","cs":"AES128/CTR/HMAC-SHA256","eA":[13,0,""]}' -X POST http://$SDO_OWNER_SVC_HOST:$SDO_OPS_EXTERNAL_PORT/mp/113/msg/40 | jq
   # an http code of 200 or 400 means it can successfully communicate with OPS
   curl -sS -w "%{http_code}" -H Content-Type:application/json -d '{"g2":"'$guid'","eA":[13,0,""]}' -X POST $SDO_RV_URL/mp/113/msg/30 | jq
   # an http code of 200 or 500 means it can successfully communicate with RV
   ```

### <a name="running-dev-test"></a>Running the SDO Support During Dev/Test

When following the instructions in [Using the SDO Support](#use-sdo), set the following environment variables to work with the most recent files and docker images that you or others on the team are developing:

- In [Start the SDO Owner Services](#start-services) set:

   ```bash
   # to use the most recently committed version of agent-install.sh:
   export AGENT_INSTALL_URL=https://raw.githubusercontent.com/open-horizon/anax/master/agent-install/agent-install.sh
   # if the hostname of this host is not resolvable by the device, provide the IP address to RV instead
   export SDO_OWNER_SVC_HOST="1.2.3.4"
   # use the built-in rendezvous server instead of Intel's global RV
   export SDO_RV_URL=http://<sdo-owner-svc-host>:8040
   # when running agent-install.sh on the edge device, it should get pkgs from CSS
   export SDO_GET_PKGS_FROM=css:
   # set your own password for the master keystore
   export SDO_KEY_PWD=<pw>
   # when curling run-sdo-owner-services.sh use the master branch instead of the 1.8 tag
   ```

- In [Initialize a Device with SDO](#init-device) set:

   ```bash
   # set SDO_SUPPORT_REPO 1 of these 2 ways:
   export SDO_SUPPORT_REPO=https://raw.githubusercontent.com/open-horizon/SDO-support/master   # using owner-boot-device from the most recent committed upstream
   export SDO_SUPPORT_REPO=https://raw.githubusercontent.com/<my-github-id>/SDO-support/<my-branch>   # using owner-boot-device from the branch you are working on
   # use the built-in rendezvous server instead of Intel's global RV
   export SDO_RV_URL=http://<sdo-owner-svc-host>:8040
   # set SDO_MFG_IMAGE_TAG 1 of these 2 ways:
   export SDO_MFG_IMAGE_TAG=testing   # using the most recent development docker image from the team
   export SDO_MFG_IMAGE_TAG=1.2.3   # using the docker image you are still working on
   # this will speed repetitive testing, because it will leave the mfg containers running if they haven't changed
   export SDO_SAMPLE_MFG_KEEP_SVCS=true
   # when curling simulate-mfg.sh use the master branch instead of the 1.8 tag
   ```

- In [Import the Ownership Voucher](#import-voucher) set: (nothing special so far)
- In [Boot the Device to Have it Configured](#boot-device) set: (nothing special so far)
