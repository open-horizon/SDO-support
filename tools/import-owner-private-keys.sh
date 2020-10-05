#!/bin/bash
# This script will generate a Key-Pair for Owner Attestation.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << EndOfMessage
Usage: ${0##*/} [<owner-keys-tar-file>]

Arguments:
  <owner-keys-tar-file>  A tar file containing the 3 private keys and associated 3 certs

Required environment variables:
  SDO_KEY_PWD - The password for your generated keystore. This password must be passed into run-sdo-owner-services.sh if you are passing in your own master keystore. This will allow it to be mounted to $containerHome/ocs/config/application.properties/fs.owner.keystore-password
  HZN_ORG_ID - The custom org the user chooses. Necessary information to import keystore into our master keystore.

EndOfMessage
    exit 1
fi

tarFile="$1"
PWD="$(grep fs.owner.keystore-password ocs/config/application.properties)"
SDO_KEY_PWD=${PWD#fs.owner.keystore-password=}

#If the argument passed for this script does not equal one of the encryption keyTypes, send error code and exit.
#BY DEFAULT THE keyType WILL BE SET TO all

if [[ ! -f $tarFile ]]; then
    echo "Error: No owner keys tarfile '$tarFile' found."
    exit 2
fi

#============================FUNCTIONS=================================

chk() {
    local exitCode=$1
    local task=$2
    local dontExit=$3   # set to 'continue' to not exit for this error
    if [[ $exitCode == 0 ]]; then return; fi
    echo "Error: exit code $exitCode from: $task"
    if [[ $dontExit != 'continue' ]]; then
        exit $exitCode
    fi
}

ensureWeAreUser() {
    if [[ $(whoami) = 'root' ]]; then
        echo "Error: must be normal user to run ${0##*/}"
        exit 2
    fi
}

function untarKeyFiles(){
  if [[ -n "$tarFile" && -f "$tarFile" ]]; then
    tar -xf $tarFile
    chk $? 'Extracting key pairs from tarball'
  else
    echo "owner-keys.tar.gz is not found"
    exit 1
  fi
}

#This function will create a private key that is needed to create a private keystore. Encryption keyType passed will decide which command to run for private key creation
function genKeyStore(){
  # This function is ran after the private key and owner certificate has been created. This function will create a public key to correspond with
  # the owner private key/certificate. After the public key is made it will then place the private key and certificate inside a keystore.
  # Generate a public key from the certificate file
  for i in "rsa" "ecdsa256" "ecdsa384"
      do
        # Convert the keyCertificate and private key into ‘PKCS12’ keystore format:
        cd "$i"Key/ && openssl pkcs12 -export -in "$i"Cert.crt -inkey "$i"private-key.pem -name "${HZN_ORG_ID}"_"$i" -out "${HZN_ORG_ID}"_"$i".p12 -password pass:"$SDO_KEY_PWD"
        chk $? 'Converting private key and cert into keystore'
        cp "${HZN_ORG_ID}"_"$i".p12 .. && rm -- *
        cd .. && rmdir "$i"Key
      done
}

function insertKeys(){
  #This function will insert all private keystores into the master keystore
  if [[ -f "${HZN_ORG_ID}"_"$i".p12 ]]; then
    for i in "rsa" "ecdsa256" "ecdsa384"
      do
        echo "yes" | /usr/lib/jvm/openjre-11-manual-installation/bin/keytool -importkeystore -destkeystore ocs/config/db/v1/creds/owner-keystore.p12 -deststorepass "$SDO_KEY_PWD" -srckeystore "${HZN_ORG_ID}"_"$i".p12 -srcstorepass "$SDO_KEY_PWD" -srcstoretype PKCS12 -alias "${HZN_ORG_ID}"_"$i"
        chk $? 'Inserting all keypairs into ocs/config/db/v1/creds/owner-keystore.p12'
      done
    rm -- *.p12
  else
    echo "One or more of the keystores are missing. There should be three keystores of type rsa, ecdsa256, and ecdsa384"
    exit 2
fi
}


#============================MAIN CODE=================================

ensureWeAreUser
untarKeyFiles
genKeyStore
insertKeys



