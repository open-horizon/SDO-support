#!/bin/bash
# This script will check the master keystore to see if there are any imported keys using the org id, key name combo provided

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} <org-id>[<key-name>]

Arguments:
  <org-id>  The organizational unit or Horizon Org ID the user is in.
  <key-name> The custom key pair name the user chooses. Necessary information to keep track of imported keystores into our master keystore.

EndOfMessage
    exit 0
fi


if [[ -z "$1" ]]; then
    echo "Error: Org ID not specified: $1"
    exit 1
fi

HZN_ORG_ID="$1"
ORG_UNIT=$HZN_ORG_ID
KEY_NAME="${2:-owner_rsa_2048}"

keypwd="$(grep -E '^ *FS_OWNER_KEYSTORE_PASSWORD=' ocs/ocs.env)"
SDO_KEY_PWD=${keypwd#FS_OWNER_KEYSTORE_PASSWORD=}

function checkOrgKeys() {
  echo "Here is a list of all key pairs using org id: "${ORG_UNIT}

  #Check for existance of a specific key . If it isn't found exit 0, if it is found exit 2
  
  /usr/lib/jvm/openjre-11-manual-installation/bin/keytool -list -v -keystore ocs/config/db/v1/creds/owner-keystore.p12 -storepass "${SDO_KEY_PWD}" | grep -E "^Owner:.*OU=${HZN_ORG_ID}," -B 5 | grep 'Alias name:'

  #/usr/lib/jvm/openjre-11-manual-installation/bin/keytool -list -v -keystore ocs/config/db/v1/creds/owner-keystore.p12 -storepass "${SDO_KEY_PWD}" | grep -E "^Owner:.*OU=${HZN_ORG_ID}," #\|Alias name
  }


function getKeyPair() {

  #Check for existance of a specific key . If it isn't found exit 0, if it is found exit 2
  echo "Checking for private keys and concatenated public key using key name: "${HZN_ORG_ID}_${KEY_NAME}
  if [[ $(/usr/lib/jvm/openjre-11-manual-installation/bin/keytool -list -v -keystore ocs/config/db/v1/creds/owner-keystore.p12 -storepass "${SDO_KEY_PWD}" | grep -E "^Alias name: *${HZN_ORG_ID}_${KEY_NAME}_rsa$") > 0 ]]; then
    echo "Key Name Already Used"
    /usr/lib/jvm/openjre-11-manual-installation/bin/keytool -list -v -keystore ocs/config/db/v1/creds/owner-keystore.p12 -storepass "${SDO_KEY_PWD}" | grep -E "^Alias name: *${HZN_ORG_ID}_${KEY_NAME}_rsa$"
    cat ocs/config/db/v1/creds/publicKeys/${ORG_UNIT}/${ORG_UNIT}_${KEY_NAME}_public-key.pem
    exit 2
  else
    echo "Key Name Not Found"
  fi
  
  }
#============================MAIN CODE=================================

if [[ ! -z "$1" ]] && [[ -z "$2" ]] ; then
  checkOrgKeys
fi

if [[ ! -z "$1" ]] && [[ ! -z "$2" ]] ; then
  getKeyPair
fi




