# Open-horizon SDO Support Docs

## OCS-API

The `ocs-api-swagger.yaml` file documents the API that Horizon has added as a side-car to Intel's SDO OCS component. It enables several high-level remote operations like importing vouchers and keys.

View the high-level OCS-API using the [Swagger sample UI](https://petstore.swagger.io/?url=https://raw.githubusercontent.com/open-horizon/SDO-support/master/docs/ocs-api-swagger.yaml) .

## OCS Low-level API - For Developers

The `ocs-swagger.yaml` file documents the low-level REST API that the Intel SDO OCS component supports. This API is called internally by the SDO OPS component, and is provided here to help developers to better understand the SDO internals. The swagger file comes from the SDO source tar file `SDOIotPlatformSDK/swagger.yaml`. 

View the low-level OCS REST API using the [Swagger sample UI](https://petstore.swagger.io/?url=https://raw.githubusercontent.com/open-horizon/SDO-support/master/docs/ocs-swagger.yaml) .
