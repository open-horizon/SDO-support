# Open Horizon SDO Support

Edge devices built with [Intel SDO](https://software.intel.com/en-us/secure-device-onboard) (Secure Device Onboard) can be added to an Open Horizon instance by simply importing their associated ownership vouchers and then powering on the devices. The software in this git repository provides integration between SDO and Open Horizon, making it easy to use SDO-enabled edge devices with Horizon.

The following versions of SDO have been integrated with Horizon. Use the version of the README that is the same as the `sdo-owner-service` container running on your Horizon management hub.

- [Horizon SDO 1.11 README](README-1.11.md)
- [Horizon SDO 1.10 README](README-1.10.md)
- [Horizon SDO 1.8 README](README-1.8.md)

**Note:** If you are unsure which version you are running, use the version API below to query it:

```bash
export HZN_ORG_ID=<exchange-org>
export HZN_EXCHANGE_USER_AUTH=<user>:<password>
export HZN_SDO_SVC_URL=<protocol>://<sdo-owner-svc-host>:<ocs-api-port>/<ocs-api-path>
curl -k -sS $HZN_SDO_SVC_URL/version && echo
```
