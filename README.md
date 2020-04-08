# SDO-support

Components to make it easy to use Intel's SDO (Secure Device Onboard) with open-horizon

## Build the SDO Owner Services

To build the docker container that will run all of the SDO services needed on the open-horizon management hub:

```bash
# first update the VERSION variable value in Makefile, then:
make sdo-owner-services
```

After testing the service, push it to docker hub:

```bash
make publish-sdo-owner-services
```

## Build Sample SDO Device Manufacturing Services

To develop/test/demo the SDO owner services, you need to initialize VMs to simulate an SDO device and create ownership vouchers. To do this, see [sample-mfg/README.md](sample-mfg/README.md).
